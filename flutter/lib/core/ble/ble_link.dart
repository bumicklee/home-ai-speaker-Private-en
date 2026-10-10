/// One BLE connection to the speaker (design document Sections 2.13, 3.4).
/// Scan (withServices FF50 + advName prefix) → connect → MTU → discover characteristics (Guid comparison) → **subscribe to notifications first** → read 0xFF61.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../constants/ble_protocol.dart';
import '../errors/exceptions.dart';
import 'ble_command_channel.dart';
import 'wifi_scan.dart';

/// A speaker found by scanning
class DiscoveredSpeaker {
  const DiscoveredSpeaker({required this.device, required this.name, required this.rssi});

  final BluetoothDevice device;

  /// Advertising name `JARVIS_XXXXXX` (we don't use platformName, which iOS caches)
  final String name;
  final int rssi;

  /// Last 6 characters of the advertising name = last 6 of the STA MAC
  String get shortId => name.substring(BleProtocol.namePrefix.length);
}

class BleScanner {
  /// Waits until BLE is on. If it's off, throws [BleException] adapterOff
  static Future<void> ensureOn({Duration wait = const Duration(seconds: 3)}) async {
    if (!await FlutterBluePlus.isSupported) {
      throw const BleException(BleErrorCode.adapterOff, 'BLE not supported');
    }
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(wait);
    } on TimeoutException {
      throw const BleException(BleErrorCode.adapterOff);
    }
  }

  /// Nearby speakers (strongest signal first). The stream ends after [timeout].
  ///
  /// There is only one scan start/stop for the whole phone. So stop **only when the subscription that started this scan is cancelled**,
  /// and only if no other scan started in the meantime (2026-10-03, real board: a scan left over from a closed screen
  /// immediately stopped the new screen's scan, so the speaker was never found).
  /// Android silently refuses more than 5 starts in 30 seconds (status=6) → wait ahead of time with [_waitForScanSlot].
  static Stream<List<DiscoveredSpeaker>> scan({Duration timeout = const Duration(seconds: 30)}) {
    final owner = Object();
    StreamSubscription<List<ScanResult>>? results;
    StreamSubscription<bool>? scanning;
    late final StreamController<List<DiscoveredSpeaker>> controller;

    Future<void> finish() async {
      await results?.cancel();
      await scanning?.cancel();
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<List<DiscoveredSpeaker>>(
      onListen: () async {
        try {
          await ensureOn();
          await _waitForScanSlot();
          if (controller.isClosed || !controller.hasListener) return;
          results = FlutterBluePlus.onScanResults.listen((list) {
            if (controller.isClosed) return;
            controller.add([
              for (final r in list)
                if (r.advertisementData.advName.startsWith(BleProtocol.namePrefix))
                  DiscoveredSpeaker(device: r.device, name: r.advertisementData.advName, rssi: r.rssi),
            ]..sort((a, b) => b.rssi.compareTo(a.rssi)));
          });
          var started = false;
          scanning = FlutterBluePlus.isScanning.listen((on) {
            if (on) {
              started = true;
            } else if (started) {
              finish(); // Time ran out or the OS stopped it
            }
          });
          _owner = owner;
          _starts.add(DateTime.now());
          await FlutterBluePlus.startScan(withServices: [BleProtocol.svcWifi], timeout: timeout);
        } on AppException catch (e) {
          if (!controller.isClosed) controller.addError(e);
          await finish();
        } on FlutterBluePlusException catch (e) {
          if (!controller.isClosed) controller.addError(BleException(BleErrorCode.protocol, e.description));
          await finish();
        }
      },
      onCancel: () async {
        await results?.cancel();
        await scanning?.cancel();
        if (identical(_owner, owner)) {
          _owner = null;
          if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
        }
      },
    );
    return controller.stream;
  }

  static Object? _owner;
  static final _starts = <DateTime>[];

  /// If 4 scans started within the last 30 seconds, wait until the oldest one is more than 30 seconds old
  static Future<void> _waitForScanSlot() async {
    const window = Duration(seconds: 30);
    final now = DateTime.now();
    _starts.removeWhere((t) => now.difference(t) > window);
    if (_starts.length >= 4) {
      await Future<void>.delayed(window - now.difference(_starts.first) + const Duration(milliseconds: 300));
      _starts.removeAt(0);
    }
  }
}

class BleLink implements BleCommandTransport {
  BleLink._(this.device);

  final BluetoothDevice device;
  late final BluetoothCharacteristic _ssid, _password, _status, _scan, _mac, _firmware, _cmdRx, _cmdTx, _provDone;
  late final BleCommandChannel commands;

  /// Device identifier: 0xFF61 STA MAC (12 uppercase hex characters). iOS remoteId is not a MAC, so we don't use it
  late final String mac;
  late final String firmware;

  final _statusController = StreamController<WifiProvStatus>.broadcast();
  final _scanController = StreamController<List<int>>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  final _disconnected = Completer<void>();
  bool _bondRetried = false;

  /// 0xFF53 status notifications
  Stream<WifiProvStatus> get wifiStatus => _statusController.stream;

  /// Completes when the connection drops
  Future<void> get disconnected => _disconnected.future;

  static Future<BleLink> connect(BluetoothDevice device, {Duration timeout = const Duration(seconds: 15)}) async {
    final link = BleLink._(device);
    try {
      await device.connect(autoConnect: false, timeout: timeout);
      await link._setup();
      return link;
    } on FlutterBluePlusException catch (e) {
      await link.disconnect();
      throw BleException(BleErrorCode.connectFailed, e.description);
    } catch (_) {
      await link.disconnect();
      rethrow;
    }
  }

  Future<void> _setup() async {
    _subs.add(device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) _onDisconnected();
    }));
    if (Platform.isAndroid) {
      await device.requestMtu(BleProtocol.androidMtuRequest); // On iOS the OS decides
    }
    final services = await device.discoverServices();
    BluetoothCharacteristic find(Guid svc, Guid chr) {
      for (final s in services) {
        if (s.uuid != svc) continue;
        for (final c in s.characteristics) {
          if (c.uuid == chr) return c;
        }
      }
      throw BleException(BleErrorCode.serviceMissing, '$svc/$chr');
    }

    _ssid = find(BleProtocol.svcWifi, BleProtocol.chrSsid);
    _password = find(BleProtocol.svcWifi, BleProtocol.chrPassword);
    _status = find(BleProtocol.svcWifi, BleProtocol.chrStatus);
    _scan = find(BleProtocol.svcWifi, BleProtocol.chrScan);
    _mac = find(BleProtocol.svcDevice, BleProtocol.chrMac);
    _firmware = find(BleProtocol.svcDevice, BleProtocol.chrFirmware);
    _cmdRx = find(BleProtocol.svcConfig, BleProtocol.chrCmdRx);
    _cmdTx = find(BleProtocol.svcConfig, BleProtocol.chrCmdTx);
    _provDone = find(BleProtocol.svcConfig, BleProtocol.chrProvDone);

    // Turn on notifications before writing (led-app turned them on later and missed the initial status)
    _subs.add(_status.onValueReceived.listen((v) {
      final s = v.isEmpty ? null : WifiProvStatus.fromCode(v[0]);
      if (s != null) _statusController.add(s);
    }));
    _subs.add(_scan.onValueReceived.listen(_scanController.add));
    commands = BleCommandChannel(this);
    await _status.setNotifyValue(true);
    await _scan.setNotifyValue(true);
    await _cmdTx.setNotifyValue(true);

    mac = utf8.decode(await _mac.read()).trim().toUpperCase();
    firmware = utf8.decode(await _firmware.read()).trim();
  }

  // ── BleCommandTransport ──

  @override
  int get payloadSize => device.mtuNow - BleProtocol.mtuOverhead;

  @override
  Stream<List<int>> get responses => _cmdTx.onValueReceived;

  @override
  Future<void> writeFrame(List<int> frame) => _write(_cmdRx, frame);

  // ── Wi-Fi ──

  /// The device scans nearby Wi-Fi (a device-side scan, so it works on iOS too)
  Future<List<WifiNetwork>> scanWifi({Duration timeout = const Duration(seconds: 15)}) async {
    final collector = WifiScanCollector();
    final done = Completer<List<WifiNetwork>>();
    final sub = _scanController.stream.listen((v) {
      try {
        final list = collector.add(v);
        if (list != null && !done.isCompleted) done.complete(list);
      } catch (e) {
        if (!done.isCompleted) done.completeError(e);
      }
    });
    try {
      await _write(_scan, const [1]);
      return await done.future.timeout(timeout,
          onTimeout: () => throw const BleException(BleErrorCode.timeout, 'wifi scan'));
    } finally {
      await sub.cancel();
    }
  }

  /// Writes SSID → password and returns the first terminal status (2–5). Device limit of 20 seconds + margin
  Future<WifiProvStatus> provisionWifi(String ssid, String password,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final ssidBytes = utf8.encode(ssid); // led-app used UTF-16 codeUnits, which broke Korean SSIDs
    final pwBytes = utf8.encode(password);
    if (ssidBytes.isEmpty || ssidBytes.length > BleProtocol.ssidMaxBytes || pwBytes.length > BleProtocol.passwordMaxBytes) {
      throw const BleException(BleErrorCode.tooLarge, 'ssid/password length');
    }
    final result = wifiStatus.firstWhere((s) => s.isFinal).timeout(timeout,
        onTimeout: () => throw const BleException(BleErrorCode.timeout, 'wifi status'));
    await _write(_ssid, ssidBytes);
    await _write(_password, pwBytes); // Writing starts the connection attempt. Length 0 for open networks
    return result;
  }

  /// 0xFF88: if Wi-Fi was changed, save and reboot; otherwise the same as prov.close
  Future<void> provisioningDone() => _write(_provDone, const [BleProtocol.provDoneValue]);

  // ── Common ──

  Future<void> _write(BluetoothCharacteristic c, List<int> value) async {
    try {
      await c.write(value, withoutResponse: false);
    } on FlutterBluePlusException catch (e) {
      if (!_isAuthError(e)) {
        throw BleException(BleErrorCode.protocol, e.description);
      }
      // A leftover old bond makes the encrypted write fail (design document 3.4 "Pairing failure handling")
      if (Platform.isAndroid && !_bondRetried) {
        _bondRetried = true;
        await device.removeBond();
        return _write(c, value);
      }
      throw BleException(BleErrorCode.bondFailed, e.description);
    }
  }

  /// ATT 0x05 insufficient authentication, 0x0F insufficient encryption
  static bool _isAuthError(FlutterBluePlusException e) => e.code == 5 || e.code == 15;

  void _onDisconnected() {
    if (_disconnected.isCompleted) return;
    _disconnected.complete();
    unawaited(commands.close().catchError((_) {}));
  }

  Future<void> disconnect() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await device.disconnect();
    } catch (_) {}
    if (!_disconnected.isCompleted) _disconnected.complete();
    await _statusController.close();
    await _scanController.close();
  }
}
