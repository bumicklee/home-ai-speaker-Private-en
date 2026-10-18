import 'dart:convert';

import 'package:aispeaker/core/ble/wifi_scan.dart';
import 'package:aispeaker/core/constants/ble_protocol.dart';
import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> entry(String ssid, int rssi, int security) {
  final b = List<int>.filled(34, 0);
  final s = utf8.encode(ssid);
  b.setRange(0, s.length, s);
  b[32] = rssi + 128;
  b[33] = security;
  return b;
}

void main() {
  test('non-ASCII SSID (UTF-8), RSSI, security type', () {
    final n = WifiNetwork.parse(entry('Café Wi-Fi €', -48, 6));
    expect(n.ssid, 'Café Wi-Fi €');
    expect(n.rssi, -48);
    expect(n.security, WifiSecurity.wpa2Wpa3);
    expect(n.bars, 4);
  });

  test('SSID filling all 32 bytes', () {
    expect(WifiNetwork.parse(entry('A' * 32, -70, 3)).ssid, 'A' * 32);
  });

  test('unknown security value is other', () {
    expect(WifiNetwork.parse(entry('x', -90, 42)).security, WifiSecurity.other);
  });

  test('count → entries, sorted strongest signal first', () {
    final c = WifiScanCollector();
    expect(c.add([2]), isNull);
    expect(c.add(entry('weak', -80, 3)), isNull);
    final list = c.add(entry('strong', -40, 0))!;
    expect(list.map((n) => n.ssid), ['strong', 'weak']);
    expect(list.first.security.needsPassword, isFalse);
  });

  test('zero count gives an empty list right away', () {
    expect(WifiScanCollector().add([0]), isEmpty);
  });

  test('0xFF = device scan failed', () {
    expect(() => WifiScanCollector().add([BleProtocol.scanFailed]), throwsA(isA<BleException>()));
  });
}
