/// 0xFF81/0xFF82 frame format `[seq:1B][flags:1B][payload…]` (design document Section 2.13, firmware `ble_cmd.c`).
/// flags bit0 = last, bit1 = first frame. A single-frame message sets both.
library;

import 'dart:typed_data';

import '../constants/ble_protocol.dart';
import '../errors/exceptions.dart';

class BleFrameCodec {
  BleFrameCodec._();

  /// Splits [message] into frames. [payloadSize] = negotiated MTU − 5
  static List<Uint8List> encode(List<int> message, int payloadSize) {
    if (payloadSize < 1) {
      throw const BleException(BleErrorCode.protocol, 'payload size < 1');
    }
    if (message.isEmpty || message.length > BleProtocol.cmdMaxBytes) {
      throw BleException(BleErrorCode.tooLarge, '${message.length} bytes');
    }
    final count = (message.length + payloadSize - 1) ~/ payloadSize;
    if (count > BleProtocol.maxFrames) {
      throw BleException(BleErrorCode.tooLarge, '$count frames');
    }
    return List.generate(count, (i) {
      final start = i * payloadSize;
      final end = start + payloadSize < message.length ? start + payloadSize : message.length;
      final flags = (i == 0 ? BleProtocol.flagFirst : 0) | (i == count - 1 ? BleProtocol.flagLast : 0);
      return Uint8List(BleProtocol.frameHeaderBytes + end - start)
        ..[0] = i
        ..[1] = flags
        ..setRange(BleProtocol.frameHeaderBytes, BleProtocol.frameHeaderBytes + end - start, message, start);
    });
  }
}

/// Collects response frames. If the order is wrong or the total is too large, it discards everything and waits for the next first frame.
class BleFrameReassembler {
  final _buffer = BytesBuilder(copy: false);
  int _nextSeq = -1; // -1 = no message in progress

  /// The bytes once the message is complete, otherwise null. Format errors throw [BleException]
  Uint8List? add(List<int> frame) {
    if (frame.length < BleProtocol.frameHeaderBytes) {
      reset();
      throw const BleException(BleErrorCode.protocol, 'short frame');
    }
    final seq = frame[0];
    final flags = frame[1];
    if (flags & BleProtocol.flagFirst != 0) {
      _buffer.clear();
      _nextSeq = 0;
    }
    if (_nextSeq < 0 || seq != _nextSeq) {
      reset();
      throw BleException(BleErrorCode.protocol, 'unexpected seq $seq');
    }
    if (_buffer.length + frame.length - BleProtocol.frameHeaderBytes > BleProtocol.cmdMaxBytes) {
      reset();
      throw const BleException(BleErrorCode.tooLarge, 'response too large');
    }
    _buffer.add(frame.sublist(BleProtocol.frameHeaderBytes));
    if (flags & BleProtocol.flagLast != 0) {
      _nextSeq = -1;
      return _buffer.takeBytes();
    }
    _nextSeq = seq == 255 ? -1 : seq + 1;
    return null;
  }

  void reset() {
    _buffer.clear();
    _nextSeq = -1;
  }
}
