import 'dart:convert';

import 'package:aispeaker/core/ble/ble_frame.dart';
import 'package:aispeaker/core/constants/ble_protocol.dart';
import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BleFrameCodec.encode', () {
    test('a single chunk sets both first and last flags', () {
      final frames = BleFrameCodec.encode(utf8.encode('{"id":1}'), 20);
      expect(frames, hasLength(1));
      expect(frames[0][0], 0);
      expect(frames[0][1], BleProtocol.flagFirst | BleProtocol.flagLast);
      expect(utf8.decode(frames[0].sublist(2)), '{"id":1}');
    });

    test('multiple chunks: seq increments, first/last flags, payload size', () {
      final msg = List<int>.generate(50, (i) => i);
      final frames = BleFrameCodec.encode(msg, 20);
      expect(frames.map((f) => f[0]), [0, 1, 2]);
      expect(frames.map((f) => f[1]), [BleProtocol.flagFirst, 0, BleProtocol.flagLast]);
      expect(frames.map((f) => f.length - 2), [20, 20, 10]);
      expect(frames.expand((f) => f.sublist(2)).toList(), msg);
    });

    test('rejects more than 4096 bytes', () {
      expect(() => BleFrameCodec.encode(List.filled(4097, 0), 200), throwsA(isA<BleException>()));
      expect(BleFrameCodec.encode(List.filled(4096, 0), 200), hasLength(21));
    });

    test('rejects more than 256 chunks (no seq wraparound)', () {
      expect(() => BleFrameCodec.encode(List.filled(257, 0), 1), throwsA(isA<BleException>()));
    });
  });

  group('BleFrameReassembler', () {
    test('reassembles what was split', () {
      final msg = utf8.encode(jsonEncode({'id': 3, 'ok': true, 'token': 'x' * 300}));
      final r = BleFrameReassembler();
      final frames = BleFrameCodec.encode(msg, 182);
      for (final f in frames.take(frames.length - 1)) {
        expect(r.add(f), isNull);
      }
      expect(r.add(frames.last), msg);
    });

    test('out-of-order chunk is an error, restarts from the next first chunk', () {
      final r = BleFrameReassembler();
      final frames = BleFrameCodec.encode(List.filled(30, 7), 10);
      r.add(frames[0]);
      expect(() => r.add(frames[2]), throwsA(isA<BleException>()));
      expect(r.add(frames[0]), isNull);
      expect(r.add(frames[1]), isNull);
      expect(r.add(frames[2]), List.filled(30, 7));
    });

    test('a chunk without a first chunk is an error', () {
      expect(() => BleFrameReassembler().add([1, 0, 9]), throwsA(isA<BleException>()));
    });
  });
}
