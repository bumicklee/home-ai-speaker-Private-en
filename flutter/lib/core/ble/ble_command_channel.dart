/// The 0xFF81 (request) / 0xFF82 (response) JSON command channel.
/// One request at a time per connection (the device answers BUSY to concurrent requests), 10 seconds per request (design document Section 2.13).
library;

import 'dart:async';
import 'dart:convert';

import '../constants/ble_protocol.dart';
import '../errors/exceptions.dart';
import 'ble_frame.dart';

/// The BLE connection the channel uses (the real implementation is `BleLink`; tests use a fake)
abstract interface class BleCommandTransport {
  /// Frame payload size = current MTU − 5
  int get payloadSize;

  /// 0xFF82 notifications (the subscription must already be on at connect time)
  Stream<List<int>> get responses;

  /// Write with response to 0xFF81
  Future<void> writeFrame(List<int> frame);
}

class BleCommandChannel {
  BleCommandChannel(this._transport, {this.timeout = BleProtocol.cmdTimeout}) {
    _sub = _transport.responses.listen(_onFrame, onError: _fail);
  }

  final BleCommandTransport _transport;
  final Duration timeout;
  final _reassembler = BleFrameReassembler();
  late final StreamSubscription<List<int>> _sub;

  int _nextId = 1;
  Future<void> _queue = Future.value();
  Completer<Map<String, dynamic>>? _pending;
  int? _pendingId;

  /// Sends an [op] request and returns the `ok: true` response. `ok: false` throws [BleCommandException]
  Future<Map<String, dynamic>> request(String op, [Map<String, Object?> fields = const {}]) {
    final result = _queue.then((_) => _send(op, fields));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, dynamic>> _send(String op, Map<String, Object?> fields) async {
    final id = _nextId++;
    final body = utf8.encode(jsonEncode({'id': id, 'op': op, ...fields}));
    final frames = BleFrameCodec.encode(body, _transport.payloadSize);
    final completer = Completer<Map<String, dynamic>>();
    _pending = completer;
    _pendingId = id;
    _reassembler.reset();
    try {
      for (final f in frames) {
        await _transport.writeFrame(f);
      }
      final response = await completer.future.timeout(
        timeout,
        onTimeout: () => throw BleException(BleErrorCode.timeout, '$op timed out'),
      );
      if (response['ok'] != true) {
        throw BleCommandException(response['error'] as String? ?? BleCmdError.invalidArg,
            data: response, message: op);
      }
      return response;
    } finally {
      _pending = null;
      _pendingId = null;
    }
  }

  void _onFrame(List<int> frame) {
    try {
      final message = _reassembler.add(frame);
      if (message == null) return;
      final decoded = jsonDecode(utf8.decode(message));
      if (decoded is! Map<String, dynamic>) {
        throw const BleException(BleErrorCode.protocol, 'response is not an object');
      }
      // Discard late responses to an earlier request (one we gave up on after a timeout)
      if (decoded['id'] == _pendingId) {
        _pending?.complete(decoded);
      }
    } on FormatException catch (e) {
      _fail(BleException(BleErrorCode.protocol, e.message));
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object error) {
    final p = _pending;
    if (p != null && !p.isCompleted) {
      p.completeError(error is AppException ? error : BleException(BleErrorCode.protocol, '$error'));
    }
  }

  /// When the connection drops: fail the pending request and clean up the subscription
  Future<void> close() async {
    _fail(const BleException(BleErrorCode.disconnected));
    await _sub.cancel();
  }
}
