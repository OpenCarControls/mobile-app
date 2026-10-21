import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
// Transport constants are identical in every vehicle's constants.g.dart.
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    show kBleMaxMessageBytes;
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';

import 'car_transport.dart';

class BleCarTransport implements CarTransport {
  final FlutterReactiveBle _ble;
  final QualifiedCharacteristic _txChar; // device → app (notify)
  final QualifiedCharacteristic _rxChar; // app → device (write)

  final _controller = StreamController<DeviceToApp>.broadcast();
  StreamSubscription<List<int>>? _notifySubscription;

  BleCarTransport({
    required FlutterReactiveBle ble,
    required String deviceId,
    required String serviceUuid,
    required String appToDeviceCharacteristicUuid,
    required String deviceToAppCharacteristicUuid,
  }) : _ble = ble,
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
    try {
      final msg = DeviceToApp.fromBuffer(bytes);
      if (kDebugMode) {
        dev.log('Received ${bytes.length} bytes', name: 'BleTransport');
      }
      if (!_controller.isClosed) _controller.add(msg);
    } on Exception catch (e) {
      dev.log('Malformed protobuf discarded: $e', name: 'BleTransport');
    }
  }

  void _onNotifyError(Object e) {
    dev.log('Notify error: $e', name: 'BleTransport');
    if (!_controller.isClosed) _controller.addError(e);
  }

  @override
  TransportType get transportType => TransportType.ble;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async {
    final bytes = message.writeToBuffer();
    // BLE messages aren't fragmented; the device can't receive a larger one.
    if (bytes.length > kBleMaxMessageBytes) {
      throw CarTransportException(
        'Command too large for BLE: ${bytes.length} bytes, '
        'limit is $kBleMaxMessageBytes',
      );
    }
    if (kDebugMode) {
      dev.log(
        'Sending ${bytes.length} bytes (msgId: ${message.messageId})',
        name: 'BleTransport',
      );
    }

    try {
      await _ble.writeCharacteristicWithResponse(_rxChar, value: bytes);
    } on Exception catch (e) {
      dev.log(
        'Write failed: $e — retrying after short delay',
        name: 'BleTransport',
      );
      // The OS may need a moment to complete bonding before the write
      // succeeds. One retry after a brief pause is sufficient for the
      // firmware-initiated bonding window.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _ble.writeCharacteristicWithResponse(_rxChar, value: bytes);
    }
  }

  @override
  void dispose() {
    _notifySubscription?.cancel();
    _controller.close();
    // Disconnect is managed by BleConnectionNotifier, not here.
  }
}
