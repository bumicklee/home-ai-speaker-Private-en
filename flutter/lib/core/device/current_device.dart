import 'package:flutter/foundation.dart';

import '../network/device_api_client.dart';
import '../network/device_endpoint.dart';
import '../services/device_event_service.dart';

/// The currently selected speaker. Feature screens' data sources get their LAN client here.
/// When DevicesCubit changes the selection, the event WebSocket moves with it.
class CurrentDevice extends ChangeNotifier {
  CurrentDevice(this._clients, this._events);

  final DeviceApiClientFactory _clients;
  final DeviceEventService _events;
  DeviceEndpoint? _endpoint;
  void Function(DeviceEndpoint)? _onEndpointChanged;

  DeviceEndpoint? get endpoint => _endpoint;
  String? get deviceId => _endpoint?.deviceId;
  bool get hasDevice => _endpoint != null;

  /// The selected device's client. StateError if none (screens open only when there is a device)
  DeviceApiClient get client {
    final e = _endpoint;
    if (e == null) throw StateError('no device selected');
    return _clients.forDevice(e, onEndpointChanged: _changed);
  }

  /// [onEndpointChanged]: tells the caller to save the new IP when the client finds one via mDNS
  void select(DeviceEndpoint? endpoint, {void Function(DeviceEndpoint)? onEndpointChanged}) {
    _onEndpointChanged = onEndpointChanged;
    if (endpoint == _endpoint) return;
    _endpoint = endpoint;
    _events.select(endpoint);
    notifyListeners();
  }

  void _changed(DeviceEndpoint e) {
    _endpoint = e;
    _events.select(e);
    _onEndpointChanged?.call(e);
    notifyListeners();
  }
}
