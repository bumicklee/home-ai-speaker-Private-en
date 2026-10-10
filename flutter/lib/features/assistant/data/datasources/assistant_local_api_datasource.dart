import '../../../../core/constants/api_paths.dart';
import '../../../../core/device/current_device.dart';

/// Assistant LAN API (firmware `local_api.c` get/put_settings, get_voices, get_memories, delete_memory)
class AssistantLocalApiDataSource {
  AssistantLocalApiDataSource(this._device);

  final CurrentDevice _device;

  Future<Map<String, dynamic>> settings() async =>
      Map<String, dynamic>.from(await _device.client.get<Map<String, dynamic>>(ApiPaths.settings(SettingsGroup.assistant)));

  /// On success, returns the full settings the device saved. Invalid values give 400 INVALID_ARG
  Future<Map<String, dynamic>> update(Map<String, dynamic> changes) async => Map<String, dynamic>.from(
      await _device.client.put<Map<String, dynamic>>(ApiPaths.settings(SettingsGroup.assistant), changes));

  /// `{"voices": ["alloy", …]}`
  Future<List<String>> voices() async {
    final j = await _device.client.get<Map<String, dynamic>>(ApiPaths.voices);
    return [for (final v in j['voices'] as List<dynamic>? ?? const []) v as String];
  }

  /// `{"key": "value", …}` (up to 12)
  Future<Map<String, String>> memories() async {
    final j = await _device.client.get<Map<String, dynamic>>(ApiPaths.memories);
    return {for (final e in j.entries) e.key: e.value as String};
  }

  /// Deleting a missing key still succeeds. A malformed key gives 400 INVALID_ARG
  Future<void> forget(String key) => _device.client.delete<dynamic>(ApiPaths.memory(key));
}
