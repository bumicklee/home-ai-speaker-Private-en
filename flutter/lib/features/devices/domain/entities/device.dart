import 'package:equatable/equatable.dart';

/// One speaker registered on this phone
class Device extends Equatable {
  const Device({required this.id, required this.name, this.host, this.port = 80});

  /// STA MAC, 12 uppercase characters (BLE 0xFF61). The last 6 digits of the advertised name and the mDNS TXT `id` come from the same value
  final String id;

  /// Name shown on screen (at first, the advertised name `JARVIS_XXXXXX`)
  final String name;

  /// Last IP found. null if mDNS could not find it right after registration (Home searches again)
  final String? host;
  final int port;

  String get shortId => id.length >= 6 ? id.substring(id.length - 6) : id;

  Device copyWith({String? name, String? Function()? host, int? port}) =>
      Device(id: id, name: name ?? this.name, host: host != null ? host() : this.host, port: port ?? this.port);

  @override
  List<Object?> get props => [id, name, host, port];
}
