/// Device real-time events (WS `/api/v1/events`, design document Section 2.14). Replaces MqttService.
/// Connects only to the one selected device and reconnects when the device changes. If dropped, reconnects at intervals from 1 second up to 30 seconds.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/api_paths.dart';
import '../network/device_endpoint.dart';

/// One event. [data] is the remaining fields without `event`
class DeviceEvent extends Equatable {
  const DeviceEvent(this.type, this.data);

  factory DeviceEvent.fromJson(Map<String, dynamic> j) =>
      DeviceEvent(j['event'] as String? ?? '', Map.of(j)..remove('event'));

  final String type;
  final Map<String, dynamic> data;

  @override
  List<Object?> get props => [type, data];
}

class DeviceEventType {
  DeviceEventType._();
  static const voiceState = 'voice_state';
  static const mediaState = 'media_state';
  static const volume = 'volume';
  static const tgMessage = 'tg_message';
  static const tgPaired = 'tg_paired';
  static const tgStatus = 'tg_status';
  static const wakeTest = 'wake_test';
  static const otaProgress = 'ota_progress';
  static const error = 'error';
}

enum EventConnection { disconnected, connecting, connected }

typedef WebSocketConnector = WebSocketChannel Function(Uri uri, Map<String, String> headers);

class DeviceEventService {
  DeviceEventService({WebSocketConnector? connector}) : _connect = connector ?? _defaultConnect;

  final WebSocketConnector _connect;
  final _events = StreamController<DeviceEvent>.broadcast();
  final _state = StreamController<EventConnection>.broadcast();

  DeviceEndpoint? _endpoint;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Duration _backoff = _minBackoff;
  EventConnection _connection = EventConnection.disconnected;

  static const _minBackoff = Duration(seconds: 1);
  static const _maxBackoff = Duration(seconds: 30);

  Stream<DeviceEvent> get events => _events.stream;
  Stream<DeviceEvent> on(String type) => events.where((e) => e.type == type);
  Stream<EventConnection> get connection => _state.stream;
  EventConnection get connectionNow => _connection;

  /// Switches device (null just disconnects)
  void select(DeviceEndpoint? endpoint) {
    if (endpoint == _endpoint) return;
    _endpoint = endpoint;
    _backoff = _minBackoff;
    _close();
    if (endpoint != null) _open();
  }

  void _open() {
    final ep = _endpoint;
    if (ep == null) return;
    _setState(EventConnection.connecting);
    final uri = ep.baseUri.replace(scheme: 'ws', path: ApiPaths.events);
    // The token goes in a header, not the URL query
    final channel = _connect(uri, {'Authorization': 'Bearer ${ep.token}'});
    _channel = channel;
    channel.ready.then((_) {
      if (_channel != channel) return;
      _backoff = _minBackoff;
      _setState(EventConnection.connected);
    }, onError: (_) => _scheduleRetry(channel));
    _sub = channel.stream.listen(
      _onMessage,
      onError: (_) => _scheduleRetry(channel),
      onDone: () => _scheduleRetry(channel),
      cancelOnError: true,
    );
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final j = jsonDecode(message);
      if (j is Map<String, dynamic> && j['event'] is String) _events.add(DeviceEvent.fromJson(j));
    } on FormatException {
      // Discard malformed messages
    }
  }

  void _scheduleRetry(WebSocketChannel channel) {
    if (_channel != channel) return; // A connection that has already been replaced
    _close();
    _retry = Timer(_backoff, _open);
    _backoff = Duration(milliseconds: min(_backoff.inMilliseconds * 2, _maxBackoff.inMilliseconds));
  }

  void _close() {
    _retry?.cancel();
    _retry = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _setState(EventConnection.disconnected);
  }

  void _setState(EventConnection s) {
    if (_connection == s) return;
    _connection = s;
    _state.add(s);
  }

  Future<void> dispose() async {
    _endpoint = null;
    _close();
    await _events.close();
    await _state.close();
  }

  static WebSocketChannel _defaultConnect(Uri uri, Map<String, String> headers) =>
      IOWebSocketChannel.connect(uri, headers: headers, pingInterval: const Duration(seconds: 30));
}
