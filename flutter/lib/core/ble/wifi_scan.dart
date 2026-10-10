/// Parses the 0xFF54 Wi-Fi scan notifications (design document Section 2.13).
/// Order: a 1-byte count (0–20, 0xFF = failure) → 34 bytes per AP [SSID 32B (zero-padded)][RSSI+128][security].
library;

import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../constants/ble_protocol.dart';
import '../errors/exceptions.dart';

class WifiNetwork extends Equatable {
  const WifiNetwork({required this.ssid, required this.rssi, required this.security});

  final String ssid;
  final int rssi;
  final WifiSecurity security;

  /// Signal bars 0–4
  int get bars => rssi >= -55
      ? 4
      : rssi >= -67
          ? 3
          : rssi >= -75
              ? 2
              : rssi >= -85
                  ? 1
                  : 0;

  static WifiNetwork parse(List<int> entry) {
    if (entry.length != BleProtocol.scanEntryBytes) {
      throw BleException(BleErrorCode.protocol, 'scan entry ${entry.length} bytes');
    }
    var end = 0;
    while (end < BleProtocol.ssidMaxBytes && entry[end] != 0) {
      end++;
    }
    return WifiNetwork(
      ssid: utf8.decode(entry.sublist(0, end), allowMalformed: true),
      rssi: entry[32] - 128,
      security: WifiSecurity.fromCode(entry[33]),
    );
  }

  @override
  List<Object?> get props => [ssid, rssi, security];
}

/// Feed the notifications in one by one; it returns the result once the whole list has arrived.
class WifiScanCollector {
  int? _expected;
  final _networks = <WifiNetwork>[];

  /// Once complete, the list sorted strongest signal first; otherwise null
  List<WifiNetwork>? add(List<int> notification) {
    if (_expected == null) {
      if (notification.length != 1) {
        throw const BleException(BleErrorCode.protocol, 'scan count expected');
      }
      final n = notification[0];
      if (n == BleProtocol.scanFailed) {
        throw const BleException(BleErrorCode.protocol, 'device scan failed');
      }
      if (n > BleProtocol.scanMaxEntries) {
        throw BleException(BleErrorCode.protocol, 'scan count $n');
      }
      _expected = n;
    } else {
      _networks.add(WifiNetwork.parse(notification));
    }
    if (_networks.length < _expected!) return null;
    return List.of(_networks)..sort((a, b) => b.rssi.compareTo(a.rssi));
  }
}
