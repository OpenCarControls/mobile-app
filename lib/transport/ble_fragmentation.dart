import 'dart:typed_data';

// Transport constants are identical in every vehicle's constants.g.dart.
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    show
        kBleAttMtu,
        kBleChunkHeaderBytes,
        kBleChunkIndexMask,
        kBleChunkLastFlag,
        kBleMaxChunks,
        kBleMaxMessageBytes,
        kBleMinAttMtu,
        kBleReassemblyTimeoutMs;

import 'car_transport.dart';

// Every GATT write/notification is one chunk: a 1-byte header (LAST flag in
// bit 7, chunk index in bits 0-6) followed by a slice of the encoded message.
// See contracts/docs/ble-fragmentation.md.

/// Bytes of message data per chunk for a negotiated ATT MTU: the MTU minus the
/// 3-byte ATT header and the chunk header. Null when the MTU is below
/// [kBleMinAttMtu], which can't carry the largest message.
int? bleChunkDataSize(int attMtu) {
  if (attMtu < kBleMinAttMtu) return null;
  // A bigger MTU than the one the app requests never produces bigger chunks.
  final mtu = attMtu < kBleAttMtu ? attMtu : kBleAttMtu;
  return mtu - 3 - kBleChunkHeaderBytes;
}

/// Splits [message] into chunks (header included) for a link with [attMtu].
/// Throws [CarTransportException] if the MTU is too small or the message is
/// empty or over the limit.
List<Uint8List> splitIntoBleChunks(Uint8List message, int attMtu) {
  final chunkData = bleChunkDataSize(attMtu);
  if (chunkData == null) {
    throw CarTransportException(
      'ATT MTU $attMtu is below the $kBleMinAttMtu BLE needs',
    );
  }
  final maxLength = kBleMaxChunks * chunkData < kBleMaxMessageBytes
      ? kBleMaxChunks * chunkData
      : kBleMaxMessageBytes;
  if (message.isEmpty || message.length > maxLength) {
    throw CarTransportException(
      'Message of ${message.length} bytes does not fit BLE, limit is '
      '$maxLength',
    );
  }
  final chunks = <Uint8List>[];
  for (
    var offset = 0, index = 0;
    offset < message.length;
    offset += chunkData, index++
  ) {
    final end = offset + chunkData < message.length
        ? offset + chunkData
        : message.length;
    final isLast = end == message.length;
    final chunk = Uint8List(kBleChunkHeaderBytes + end - offset)
      ..[0] = (isLast ? kBleChunkLastFlag : 0) | index
      ..setRange(
        kBleChunkHeaderBytes,
        kBleChunkHeaderBytes + end - offset,
        message,
        offset,
      );
    chunks.add(chunk);
  }
  return chunks;
}

/// Why [BleReassembler] dropped a chunk or a partial message.
enum BleReassemblyDrop {
  /// An empty chunk, with no header.
  empty,

  /// A chunk after the first arrived with no partial message.
  noStart,

  /// The chunk index isn't the one after the previous chunk (missing or
  /// duplicate chunk).
  gap,

  /// The next chunk came later than [kBleReassemblyTimeoutMs].
  timeout,

  /// The message would exceed [kBleMaxMessageBytes].
  tooLarge,
}

/// Rebuilds messages from chunks. Keeps at most one partial message and drops
/// it on any error; chunks are then ignored until the next chunk 0. Create one
/// per connection: a new instance has no partial message, which is how
/// partial messages are dropped on disconnect.
class BleReassembler {
  /// [clock] must be monotonic; tests inject their own.
  BleReassembler({Duration Function()? clock, this.onDrop})
    : _clock = clock ?? _defaultClock();

  /// Called each time a chunk or a partial message is dropped.
  final void Function(BleReassemblyDrop reason)? onDrop;
  final Duration Function() _clock;

  final _buffer = BytesBuilder(copy: false);
  int? _nextIndex;
  Duration _lastChunkAt = Duration.zero;

  static Duration Function() _defaultClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// Drops any partial message.
  void reset() {
    _buffer.clear();
    _nextIndex = null;
  }

  /// Feeds one chunk. Returns the whole message when [chunk] was the last one,
  /// otherwise null.
  Uint8List? push(List<int> chunk) {
    if (chunk.length < kBleChunkHeaderBytes) {
      return _drop(BleReassemblyDrop.empty);
    }
    final header = chunk[0];
    final index = header & kBleChunkIndexMask;
    final isLast = header & kBleChunkLastFlag != 0;
    final now = _clock();

    if (index == 0) {
      // A new message always replaces a partial one.
      reset();
    } else {
      final expected = _nextIndex;
      if (expected == null) return _drop(BleReassemblyDrop.noStart);
      if (now - _lastChunkAt >
          const Duration(milliseconds: kBleReassemblyTimeoutMs)) {
        return _drop(BleReassemblyDrop.timeout);
      }
      if (index != expected) return _drop(BleReassemblyDrop.gap);
    }
    if (_buffer.length + chunk.length - kBleChunkHeaderBytes >
        kBleMaxMessageBytes) {
      return _drop(BleReassemblyDrop.tooLarge);
    }
    _buffer.add(chunk.sublist(kBleChunkHeaderBytes));
    _lastChunkAt = now;
    if (isLast) {
      _nextIndex = null;
      return _buffer.takeBytes();
    }
    _nextIndex = (index + 1) & kBleChunkIndexMask;
    return null;
  }

  Uint8List? _drop(BleReassemblyDrop reason) {
    reset();
    onDrop?.call(reason);
    return null;
  }
}
