/// Finds speakers on the same Wi-Fi (mDNS `_aispeaker._tcp`, design document Section 2.14).
/// On iOS this service must be listed in Info.plist `NSBonjourServices` (`multicast_dns` needs an entitlement, so we use `nsd`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../constants/api_paths.dart';
import '../network/device_endpoint.dart';

class FoundSpeaker extends Equatable {
  const FoundSpeaker({required this.shortId, required this.host, required this.port, this.protocolVersion});

  /// TXT `id` = last 6 of the STA MAC (the end of the 12-character device identifier)
  final String shortId;
  final String host;
  final int port;
  final int? protocolVersion;

  bool matches(String deviceId) => deviceId.toUpperCase().endsWith(shortId.toUpperCase());

  @override
  List<Object?> get props => [shortId, host, port, protocolVersion];
}

class DeviceDiscoveryService implements DeviceResolver {
  /// Speakers found within [timeout]
  Future<List<FoundSpeaker>> discover({Duration timeout = const Duration(seconds: 4)}) async {
    final found = <String, FoundSpeaker>{};
    final discovery = await nsd.startDiscovery(LanDiscovery.serviceType, ipLookupType: nsd.IpLookupType.v4);
    try {
      void collect() {
        for (final s in discovery.services) {
          final speaker = _parse(s);
          if (speaker != null) found[speaker.shortId] = speaker;
        }
      }

      discovery.addListener(collect);
      await Future<void>.delayed(timeout);
      discovery.removeListener(collect);
      collect();
    } finally {
      await nsd.stopDiscovery(discovery);
    }
    return found.values.toList();
  }

  /// Returns as soon as one device is found
  Future<FoundSpeaker?> find(String deviceId, {Duration timeout = const Duration(seconds: 4)}) async {
    final discovery = await nsd.startDiscovery(LanDiscovery.serviceType, ipLookupType: nsd.IpLookupType.v4);
    final result = Completer<FoundSpeaker?>();
    void check() {
      for (final s in discovery.services) {
        final speaker = _parse(s);
        if (speaker != null && speaker.matches(deviceId) && !result.isCompleted) result.complete(speaker);
      }
    }

    discovery.addListener(check);
    check();
    try {
      return await result.future.timeout(timeout, onTimeout: () => null);
    } finally {
      discovery.removeListener(check);
      await nsd.stopDiscovery(discovery);
    }
  }

  @override
  Future<DeviceEndpoint?> resolve(DeviceEndpoint stale) async {
    final speaker = await find(stale.deviceId);
    return speaker == null ? null : stale.copyWith(host: speaker.host, port: speaker.port);
  }

  static FoundSpeaker? _parse(nsd.Service s) {
    final id = _txt(s, LanDiscovery.txtId);
    final ip = s.addresses?.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => s.addresses!.first);
    if (id == null || id.isEmpty || ip == null) return null;
    return FoundSpeaker(
      shortId: id.toUpperCase(),
      host: ip.address,
      port: s.port ?? LanDiscovery.port,
      protocolVersion: int.tryParse(_txt(s, LanDiscovery.txtProtocol) ?? ''),
    );
  }

  static String? _txt(nsd.Service s, String key) {
    final v = s.txt?[key];
    return v == null ? null : utf8.decode(v, allowMalformed: true);
  }
}
