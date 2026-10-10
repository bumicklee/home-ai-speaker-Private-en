/// Per-device LAN API client (design document Sections 2.14, 3.2).
/// Bundles baseUrl and token per device. No token-refresh interceptor (401 = revoked).
/// If the connection fails, find the IP again via mDNS and retry once.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../errors/exceptions.dart';
import 'device_endpoint.dart';

class DeviceApiClient {
  DeviceApiClient(this._endpoint, {DeviceResolver? resolver, Dio? dio, this.onEndpointChanged})
      : _resolver = resolver,
        _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 4)
      ..receiveTimeout = const Duration(seconds: 15)
      ..sendTimeout = const Duration(seconds: 15)
      ..responseType = ResponseType.json;
    _apply();
  }

  final Dio _dio;
  final DeviceResolver? _resolver;
  DeviceEndpoint _endpoint;

  /// Notifies the caller to save the IP when it changes
  final void Function(DeviceEndpoint)? onEndpointChanged;

  DeviceEndpoint get endpoint => _endpoint;

  void _apply() {
    _dio.options
      ..baseUrl = _endpoint.baseUri.toString()
      // The device rejects requests with an Origin header (to block browsers). Dio doesn't send one
      ..headers = {'Authorization': 'Bearer ${_endpoint.token}'};
  }

  Future<T> get<T>(String path) => _run(() => _dio.get<T>(path));

  Future<T> put<T>(String path, Object? body) => _run(() => _dio.put<T>(path, data: body));

  Future<T> post<T>(String path, [Object? body]) => _run(() => _dio.post<T>(path, data: body));

  Future<T> delete<T>(String path) => _run(() => _dio.delete<T>(path));

  /// Large uploads such as OTA. Content-Length required (the device checks the size first)
  Future<T> upload<T>(String path, Stream<List<int>> data, int length,
          {void Function(int sent, int total)? onProgress, Duration timeout = const Duration(minutes: 5)}) =>
      _run(() => _dio.post<T>(path,
          data: data,
          options: Options(
            headers: {Headers.contentLengthHeader: length, Headers.contentTypeHeader: 'application/octet-stream'},
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
          onSendProgress: onProgress),
          retry: false); // A stream can't be sent again

  Future<T> _run<T>(Future<Response<T>> Function() call, {bool retry = true}) async {
    try {
      return (await call()).data as T;
    } on DioException catch (e) {
      if (retry && _isUnreachable(e) && await _rediscover()) {
        try {
          return (await call()).data as T;
        } on DioException catch (e2) {
          throw _map(e2);
        }
      }
      throw _map(e);
    }
  }

  Future<bool> _rediscover() async {
    final fresh = await _resolver?.resolve(_endpoint);
    if (fresh == null || fresh == _endpoint) return false;
    _endpoint = fresh;
    _apply();
    onEndpointChanged?.call(fresh);
    return true;
  }

  static bool _isUnreachable(DioException e) =>
      e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout;

  static AppException _map(DioException e) {
    final r = e.response;
    if (r != null) {
      final body = r.data;
      final code = body is Map ? body['error'] as String? : null;
      return DeviceApiException(r.statusCode ?? 0, code, e.message, body is Map<String, dynamic> ? body : null);
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return DeviceTimeoutException(e.message);
      default:
        return NetworkException(e.message);
    }
  }
}

/// One client per device (DI registers only this factory)
class DeviceApiClientFactory {
  DeviceApiClientFactory({this.resolver});

  final DeviceResolver? resolver;
  final _clients = <String, DeviceApiClient>{};

  DeviceApiClient forDevice(DeviceEndpoint endpoint, {void Function(DeviceEndpoint)? onEndpointChanged}) {
    final existing = _clients[endpoint.deviceId];
    if (existing != null && existing.endpoint.token == endpoint.token) return existing;
    return _clients[endpoint.deviceId] =
        DeviceApiClient(endpoint, resolver: resolver, onEndpointChanged: onEndpointChanged);
  }

  void remove(String deviceId) => _clients.remove(deviceId);
}
