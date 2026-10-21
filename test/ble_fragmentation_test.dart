import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    show
        kBleAttMtu,
        kBleMaxChunkBytes,
        kBleMaxChunks,
        kBleMaxMessageBytes,
        kBleMinAttMtu,
        kBleReassemblyTimeoutMs;
import 'package:open_car_app/transport/ble_fragmentation.dart';
import 'package:open_car_app/transport/car_transport.dart';

Uint8List _message(int length) =>
    Uint8List.fromList(List.generate(length, (i) => i & 0xFF));

void main() {
  group('splitIntoBleChunks', () {
    test('a small message is one chunk with the last flag', () {
      final chunks = splitIntoBleChunks(
        Uint8List.fromList([1, 2, 3]),
        kBleAttMtu,
      );
      expect(chunks.map((c) => c.toList()), [
        [0x80, 1, 2, 3],
      ]);
    });

    test('headers count up and the last chunk carries the flag', () {
      // 500 bytes = 243 + 243 + 14 at the requested MTU.
      final chunks = splitIntoBleChunks(_message(500), kBleAttMtu);
      expect(chunks.map((c) => c[0]), [0x00, 0x01, 0x82]);
      expect(chunks.map((c) => c.length), [244, 244, 15]);
    });

    test('an exact multiple of the chunk size ends on a full chunk', () {
      final chunks = splitIntoBleChunks(_message(243 * 2), kBleAttMtu);
      expect(chunks.map((c) => c[0]), [0x00, 0x81]);
      expect(chunks.last.length, 244);
    });

    test('no chunk is bigger than one ATT packet', () {
      final chunks = splitIntoBleChunks(
        _message(kBleMaxMessageBytes),
        kBleAttMtu,
      );
      expect(chunks.every((c) => c.length <= kBleMaxChunkBytes), isTrue);
    });

    test('a smaller MTU gives smaller chunks', () {
      final chunks = splitIntoBleChunks(_message(300), 100);
      expect(chunks.every((c) => c.length <= 97), isTrue);
      expect(chunks, hasLength(4));
    });

    test('an MTU above the requested one does not grow chunks', () {
      expect(bleChunkDataSize(512), kBleAttMtu - 4);
    });

    test('the minimum MTU still carries the largest message', () {
      final chunkData = bleChunkDataSize(kBleMinAttMtu)!;
      expect(
        kBleMaxChunks * chunkData,
        greaterThanOrEqualTo(kBleMaxMessageBytes),
      );
      expect(
        splitIntoBleChunks(_message(kBleMaxMessageBytes), kBleMinAttMtu),
        hasLength(lessThanOrEqualTo(kBleMaxChunks)),
      );
    });

    test('an MTU below the minimum is refused', () {
      expect(bleChunkDataSize(kBleMinAttMtu - 1), isNull);
      expect(
        () => splitIntoBleChunks(_message(10), 23),
        throwsA(isA<CarTransportException>()),
      );
    });

    test('empty and oversized messages are refused', () {
      expect(
        () => splitIntoBleChunks(Uint8List(0), kBleAttMtu),
        throwsA(isA<CarTransportException>()),
      );
      expect(
        () => splitIntoBleChunks(_message(kBleMaxMessageBytes + 1), kBleAttMtu),
        throwsA(isA<CarTransportException>()),
      );
    });
  });

  group('BleReassembler', () {
    late Duration now;
    late List<BleReassemblyDrop> drops;
    late BleReassembler reassembler;

    setUp(() {
      now = Duration.zero;
      drops = [];
      reassembler = BleReassembler(clock: () => now, onDrop: drops.add);
    });

    Uint8List? feed(List<Uint8List> chunks) {
      Uint8List? result;
      for (final chunk in chunks) {
        result = reassembler.push(chunk);
      }
      return result;
    }

    test('round-trips messages of every interesting length', () {
      for (final length in [1, 242, 243, 244, 486, 1000, kBleMaxMessageBytes]) {
        final message = _message(length);
        expect(
          feed(splitIntoBleChunks(message, kBleAttMtu)),
          message,
          reason: 'length $length',
        );
      }
    });

    test('round-trips across MTUs', () {
      for (final mtu in [kBleMinAttMtu, 100, 185, kBleAttMtu]) {
        final message = _message(1500);
        expect(feed(splitIntoBleChunks(message, mtu)), message, reason: '$mtu');
      }
    });

    test('a gap drops the message and later chunks wait for a new start', () {
      final chunks = splitIntoBleChunks(_message(800), kBleAttMtu);
      expect(reassembler.push(chunks[0]), isNull);
      expect(reassembler.push(chunks[2]), isNull);
      expect(reassembler.push(chunks[3]), isNull);
      expect(drops, [BleReassemblyDrop.gap, BleReassemblyDrop.noStart]);
      // The next message gets through.
      expect(reassembler.push(Uint8List.fromList([0x80, 9])), [9]);
    });

    test('a duplicate chunk drops the message', () {
      final chunks = splitIntoBleChunks(_message(800), kBleAttMtu);
      reassembler
        ..push(chunks[0])
        ..push(chunks[1]);
      expect(reassembler.push(chunks[1]), isNull);
      expect(drops, [BleReassemblyDrop.gap]);
    });

    test('a new first chunk replaces a partial message', () {
      final chunks = splitIntoBleChunks(_message(800), kBleAttMtu);
      reassembler.push(chunks[0]);
      expect(reassembler.push(Uint8List.fromList([0x80, 1, 2])), [1, 2]);
      expect(drops, isEmpty);
    });

    test('a late chunk drops the message', () {
      final chunks = splitIntoBleChunks(_message(800), kBleAttMtu);
      reassembler.push(chunks[0]);
      now += const Duration(milliseconds: kBleReassemblyTimeoutMs);
      expect(reassembler.push(chunks[1]), isNull);
      expect(drops, isEmpty, reason: 'exactly the timeout is still in time');
      now += const Duration(milliseconds: kBleReassemblyTimeoutMs + 1);
      expect(reassembler.push(chunks[2]), isNull);
      expect(drops, [BleReassemblyDrop.timeout]);
    });

    test('a message over the size limit is dropped', () {
      final data = Uint8List(243);
      for (var i = 0; i <= kBleMaxMessageBytes ~/ 243 + 1; i++) {
        reassembler.push(Uint8List.fromList([i, ...data]));
        if (drops.isNotEmpty) break;
      }
      expect(drops, [BleReassemblyDrop.tooLarge]);
    });

    test('reset drops the partial message', () {
      final chunks = splitIntoBleChunks(_message(800), kBleAttMtu);
      reassembler
        ..push(chunks[0])
        ..reset();
      expect(reassembler.push(chunks[1]), isNull);
      expect(drops, [BleReassemblyDrop.noStart]);
    });

    test('an empty chunk is dropped', () {
      expect(reassembler.push(Uint8List(0)), isNull);
      expect(drops, [BleReassemblyDrop.empty]);
    });
  });
}
