import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';

import 'ble_fragmentation.dart';
import 'car_transport.dart';

class BleCarTransport implements CarTransport {
  final FlutterReactiveBle _ble;
  final QualifiedCharacteristic _txChar; // device → app (notify)
  final QualifiedCharacteristic _rxChar; // app → device (write)

  /// ATT MTU negotiated for this connection; sizes the outgoing chunks.
  final int _attMtu;

  final _controller = StreamController<DeviceToApp>.broadcast();
  StreamSubscription<List<int>>? _notifySubscription;

  // One transport per connection, so a partial message never outlives it.
  late final BleReassembler _reassembler = BleReassembler(
    onDrop: (reason) =>
        dev.log('Dropped BLE chunk: ${reason.name}', name: 'BleTransport'),
  );

  // Chunks of two messages must never interleave on the characteristic, so
  // sends run one after the other.
  Future<void> _writeQueue = Future<void>.value();

  // Message sequence number, the same on every chunk of a message.
  int _nextSeq = 0;

  BleCarTransport({
    required FlutterReactiveBle ble,
    required String deviceId,
    required String serviceUuid,
    required String appToDeviceCharacteristicUuid,
    required String deviceToAppCharacteristicUuid,
    required int attMtu,
  }) : _ble = ble,
       _attMtu = attMtu,
       _txChar = QualifiedCharacteristic(
         deviceId: deviceId,
         serviceId: Uuid.parse(serviceUuid),
         characteristicId: Uuid.parse(deviceToAppCharacteristicUuid),
       ),
       _rxChar = QualifiedCharacteristic(
         deviceId: deviceId,
         serviceId: Uuid.parse(serviceUuid),
         characteristicId: Uuid.parse(appToDeviceCharacteristicUuid),
       ) {
    _init();
  }

  void _init() {
    dev.log('Subscribing to device→app characteristic', name: 'BleTransport');
    _notifySubscription = _ble
        .subscribeToCharacteristic(_txChar)
        .listen(_onNotify, onError: _onNotifyError);
  }

  void _onNotify(List<int> bytes) {
    if (bytes.isEmpty) return;
    // Every notification is one chunk; decode once the last one arrives.
    final message = _reassembler.push(bytes);
    if (message == null) return;
    try {
      final msg = DeviceToApp.fromBuffer(message);
      if (kDebugMode) {
        dev.log('Received ${message.length} bytes', name: 'BleTransport');
      }
      if (!_controller.isClosed) _controller.add(msg);
    } on Exception catch (e) {
      dev.log('Malformed protobuf discarded: $e', name: 'BleTransport');
    }
  }

  void _onNotifyError(Object e) {
    dev.log('Notify error: $e', name: 'BleTransport');
    _reassembler.reset();
    if (!_controller.isClosed) _controller.addError(e);
  }

  @override
  TransportType get transportType => TransportType.ble;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async {
    final bytes = message.writeToBuffer();
    // Throws when the message is over the limit or the MTU is too small.
    final chunks = splitIntoBleChunks(bytes, _attMtu, _nextSeq);
    _nextSeq = (_nextSeq + 1) & 0xFF;
    if (kDebugMode) {
      dev.log(
        'Sending ${bytes.length} bytes in ${chunks.length} chunk(s) '
        '(msgId: ${message.messageId})',
        name: 'BleTransport',
      );
    }

    final write = _writeQueue.then((_) async {
      for (final chunk in chunks) {
        await _writeChunk(chunk);
      }
    });
    // A failed send must not block the ones queued behind it.
    _writeQueue = write.then((_) {}, onError: (Object _) {});
    await write;
  }

  Future<void> _writeChunk(Uint8List chunk) async {
    try {
      await _ble.writeCharacteristicWithResponse(_rxChar, value: chunk);
    } on Exception catch (e) {
      dev.log(
        'Write failed: $e — retrying after short delay',
        name: 'BleTransport',
      );
      // The OS may need a moment to complete bonding before the write
      // succeeds. One retry after a brief pause is sufficient for the
      // firmware-initiated bonding window.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _ble.writeCharacteristicWithResponse(_rxChar, value: chunk);
    }
  }

  @override
  void dispose() {
    _notifySubscription?.cancel();
    _reassembler.reset();
    _controller.close();
    // Disconnect is managed by BleConnectionNotifier, not here.
  }
}
