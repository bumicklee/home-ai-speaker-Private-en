import 'package:equatable/equatable.dart';

/// One device's LAN address and token
class DeviceEndpoint extends Equatable {
  const DeviceEndpoint({required this.deviceId, required this.host, this.port = 80, required this.token});

  /// STA MAC, 12 characters (0xFF61)
  final String deviceId;

  /// IP address (found via mDNS). `.local` names resolve unreliably on Android, so we use the IP
  final String host;
  final int port;
  final String token;

  Uri get baseUri => Uri(scheme: 'http', host: host, port: port);

  DeviceEndpoint copyWith({String? host, int? port}) =>
      DeviceEndpoint(deviceId: deviceId, host: host ?? this.host, port: port ?? this.port, token: token);

  @override
  List<Object?> get props => [deviceId, host, port, token];
}

/// When the connection fails, find the IP again via mDNS (implemented by DeviceDiscoveryService)
abstract interface class DeviceResolver {
  Future<DeviceEndpoint?> resolve(DeviceEndpoint stale);
}
