/// LAN API paths (design document Section 2.14). The device side is `local_api.c`.
library;

class LanDiscovery {
  LanDiscovery._();

  /// mDNS service (must match iOS Info.plist `NSBonjourServices`)
  static const serviceType = '_aispeaker._tcp';
  static const hostPrefix = 'jarvis-';
  static const port = 80;

  /// TXT record keys
  static const txtId = 'id';
  static const txtProtocol = 'pv';
}

class ApiPaths {
  ApiPaths._();

  static const base = '/api/v1';
  static const status = '$base/status';
  static String settings(String group) => '$base/settings/$group';
  static const voices = '$base/voices';
  static const memories = '$base/memories';
  static String memory(String key) => '$memories/${Uri.encodeComponent(key)}';
  static const radioPresets = '$base/radio/presets';
  static const mediaPlay = '$base/media/play';
  static String mediaControl(String action) => '$base/media/$action';
  static const mediaNow = '$base/media/now';
  static const spotify = '$base/spotify';
  static const telegramChats = '$base/telegram/chats';
  static String telegramChat(int chatId) => '$telegramChats/$chatId';
  static const telegramPair = '$base/telegram/pair';
  static const telegramOptions = '$base/telegram/options';
  static const notes = '$base/notes';
  static String notesSince(int rev) => '$notes?since=$rev';
  static String note(String id) => '$notes/${Uri.encodeComponent(id)}';
  static String noteRestore(String id) => '${note(id)}/restore';
  static const notesSettings = '$notes/settings';
  static String key(String key) => '$base/keys/$key';
  static String voice(String action) => '$base/voice/$action';
  static const testTone = '$base/audio/test-tone';
  static const wakeTest = '$base/wake/test';
  static const ota = '$base/ota';
  static const reboot = '$base/system/reboot';
  static const phones = '$base/system/phones';
  static String phone(String phoneId) => '$phones/$phoneId';
  static const events = '$base/events';
}

/// The group in `/settings/{group}`
class SettingsGroup {
  SettingsGroup._();
  static const audio = 'audio';
  static const wake = 'wake';
  static const assistant = 'assistant';
  static const led = 'led';
}
