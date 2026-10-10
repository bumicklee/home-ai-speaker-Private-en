import '../../../../core/constants/api_paths.dart';
import '../../../../core/device/current_device.dart';

/// Notes and schedule LAN API of the selected speaker (design document docs/design-notes-schedule.md Section 5.3). DeviceApiClient converts exceptions to AppException and throws them
class NotesRemoteDataSource {
  NotesRemoteDataSource(this._device);

  final CurrentDevice _device;

  /// `{rev, items}`: items changed after [since] (including deletion records). 0 means everything
  Future<Map<String, dynamic>> changes(int since) =>
      _device.client.get<Map<String, dynamic>>(ApiPaths.notesSince(since));

  /// The created item. 400 INVALID_ARG, 409 FULL
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) =>
      _device.client.post<Map<String, dynamic>>(ApiPaths.notes, body);

  /// The edited item. 404 NOT_FOUND, 409 CONFLICT (body `note` = latest)
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> body) =>
      _device.client.put<Map<String, dynamic>>(ApiPaths.note(id), body);

  /// Delete the original on the speaker → `{id, rev, state: "gone"}`
  Future<Map<String, dynamic>> delete(String id) => _device.client.delete<Map<String, dynamic>>(ApiPaths.note(id));

  /// The item restored from the trash
  Future<Map<String, dynamic>> restore(String id) =>
      _device.client.post<Map<String, dynamic>>(ApiPaths.noteRestore(id));

  /// `{enabled, default_remind, default_remind_all_day, all_day_time}`
  Future<Map<String, dynamic>> settings() => _device.client.get<Map<String, dynamic>>(ApiPaths.notesSettings);

  /// Sending only some fields is fine. Returns the full values after saving
  Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> body) =>
      _device.client.put<Map<String, dynamic>>(ApiPaths.notesSettings, body);
}
