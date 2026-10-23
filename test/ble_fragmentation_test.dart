import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    show
        kBleAttMtu,
        kBleChunkHeaderBytes,
        kBleCrcBytes,
        kBleMaxChunkBytes,
        kBleMaxChunks,
        kBleMaxMessageBytes,
        kBleMinAttMtu,
        kBleReassemblyTimeoutMs;
import 'package:open_car_app/transport/ble_fragmentation.dart';
import 'package:open_car_app/transport/car_transport.dart';

const _seq = 7;

Uint8List _message(int length) =>
    Uint8List.fromList(List.generate(length, (i) => i & 0xFF));

List<Uint8List> _split(Uint8List message, int mtu, [int seq = _seq]) =>
    splitIntoBleChunks(message, mtu, seq);

void main() {
  group('bleCrc32', () {
    test('matches the standard check value', () {
      expect(bleCrc32('123456789'.codeUnits), 0xCBF43926);
      expect(bleCrc32(const []), 0);
    });
  });

  group('splitIntoBleChunks', () {
    test('a small message is one chunk with the last flag and the CRC', () {
      final message = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final crc = ByteData(4)..setUint32(0, bleCrc32(message));
      final chunks = _split(message, kBleAttMtu);
      expect(chunks.map((c) => c.toList()), [
        [0x80, _seq, 0xAA, 0xBB, 0xCC, ...crc.buffer.asUint8List()],
      ]);
    });

    test('headers count up and the last chunk carries the flag', () {
      // 500 bytes + 4 CRC = 504 = 242 + 242 + 20 at the requested MTU.
      final chunks = _split(_message(500), kBleAttMtu);
      expect(chunks.map((c) => c[0]), [0x00, 0x01, 0x82]);
      expect(chunks.map((c) => c[1]), everyElement(_seq));
      expect(chunks.map((c) => c.length), [244, 244, 22]);
    });

    test('the CRC can straddle the last two chunks', () {
      final message = _message(240);
      final chunks = _split(message, kBleAttMtu);
      expect(chunks, hasLength(2));
      expect(chunks.last.length, kBleChunkHeaderBytes + 2);
      final reassembler = BleReassembler();
      expect(reassembler.push(chunks[0]), isNull);
      expect(reassembler.push(chunks[1]), message);
    });

    test('no chunk is bigger than one ATT packet', () {
      final chunks = _split(_message(kBleMaxMessageBytes), kBleAttMtu);
      expect(chunks.every((c) => c.length <= kBleMaxChunkBytes), isTrue);
    });

    test('a smaller MTU gives smaller chunks', () {
      final chunks = _split(_message(300), 100);
      expect(chunks.every((c) => c.length <= 97), isTrue);
      expect(chunks, hasLength(4));
    });

    test('an MTU above the requested one does not grow chunks', () {
      expect(bleChunkDataSize(512), kBleAttMtu - 5);
    });

    test('the minimum MTU still carries the largest message', () {
      final chunkData = bleChunkDataSize(kBleMinAttMtu)!;
      expect(
        kBleMaxChunks * chunkData,
        greaterThanOrEqualTo(kBleMaxMessageBytes + kBleCrcBytes),
      );
      expect(
        _split(_message(kBleMaxMessageBytes), kBleMinAttMtu),
        hasLength(lessThanOrEqualTo(kBleMaxChunks)),
      );
    });

    test('an MTU below the minimum is refused', () {
      expect(bleChunkDataSize(kBleMinAttMtu - 1), isNull);
      expect(
        () => _split(_message(10), 23),
        throwsA(isA<CarTransportException>()),
      );
    });

    test('empty and oversized messages are refused', () {
      expect(
        () => _split(Uint8List(0), kBleAttMtu),
        throwsA(isA<CarTransportException>()),
      );
      expect(
        () => _split(_message(kBleMaxMessageBytes + 1), kBleAttMtu),
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
      for (final length in [
        1,
        238,
        239,
        240,
        241,
        242,
        243,
        484,
        1000,
        kBleMaxMessageBytes,
      ]) {
        final message = _message(length);
        expect(
          feed(_split(message, kBleAttMtu)),
          message,
          reason: 'length $length',
        );
      }
    });

    test('round-trips across MTUs', () {
      for (final mtu in [kBleMinAttMtu, 100, 185, kBleAttMtu]) {
        final message = _message(1500);
        expect(feed(_split(message, mtu)), message, reason: '$mtu');
      }
    });

    test('a gap drops the message and later chunks wait for a new start', () {
      final chunks = _split(_message(800), kBleAttMtu);
      expect(reassembler.push(chunks[0]), isNull);
      expect(reassembler.push(chunks[2]), isNull);
      expect(reassembler.push(chunks[3]), isNull);
      expect(drops, [BleReassemblyDrop.gap, BleReassemblyDrop.noStart]);
      // The next message gets through.
      expect(feed(_split(Uint8List.fromList([9]), kBleAttMtu)), [9]);
    });

    test('a duplicate chunk drops the message', () {
      final chunks = _split(_message(800), kBleAttMtu);
      reassembler
        ..push(chunks[0])
        ..push(chunks[1]);
      expect(reassembler.push(chunks[1]), isNull);
      expect(drops, [BleReassemblyDrop.gap]);
    });

    test('chunks of two messages are never spliced', () {
      // A's chunk 1 and B's chunk 0 are lost; B's chunk 1 has the index the
      // receiver waits for, so only the sequence number catches it.
      final a = _split(_message(800), kBleAttMtu, 1);
      final b = _split(_message(800), kBleAttMtu, 2);
      reassembler.push(a[0]);
      expect(reassembler.push(b[1]), isNull);
      expect(drops, [BleReassemblyDrop.seqMismatch]);
    });

    test('a corrupted message fails the CRC', () {
      final chunks = _split(_message(800), kBleAttMtu);
      chunks[1][5] ^= 0x01;
      expect(feed(chunks), isNull);
      expect(drops, [BleReassemblyDrop.badCrc]);
    });

    test('a message shorter than its CRC is dropped', () {
      expect(reassembler.push(Uint8List.fromList([0x80, 0, 1, 2])), isNull);
      expect(drops, [BleReassemblyDrop.tooShort]);
    });

    test('a new first chunk replaces a partial message', () {
      final chunks = _split(_message(800), kBleAttMtu);
      reassembler.push(chunks[0]);
      final next = Uint8List.fromList([1, 2]);
      expect(feed(_split(next, kBleAttMtu, 9)), next);
      expect(drops, isEmpty);
    });

    test('a late chunk drops the message', () {
      final chunks = _split(_message(800), kBleAttMtu);
      reassembler.push(chunks[0]);
      now += const Duration(milliseconds: kBleReassemblyTimeoutMs);
      expect(reassembler.push(chunks[1]), isNull);
      expect(drops, isEmpty, reason: 'exactly the timeout is still in time');
      now += const Duration(milliseconds: kBleReassemblyTimeoutMs + 1);
      expect(reassembler.push(chunks[2]), isNull);
      expect(drops, [BleReassemblyDrop.timeout]);
    });

    test('a message over the size limit is dropped', () {
      final data = Uint8List(242);
      for (
        var i = 0;
        i <= (kBleMaxMessageBytes + kBleCrcBytes) ~/ 242 + 1;
        i++
      ) {
        reassembler.push(Uint8List.fromList([i, 0, ...data]));
        if (drops.isNotEmpty) break;
      }
      expect(drops, [BleReassemblyDrop.tooLarge]);
    });

    test('reset drops the partial message', () {
      final chunks = _split(_message(800), kBleAttMtu);
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
