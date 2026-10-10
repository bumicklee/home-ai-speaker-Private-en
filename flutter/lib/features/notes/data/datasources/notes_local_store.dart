import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/entities/note.dart';
import '../models/note_model.dart';

/// Copy kept on the phone: `notes_<deviceId>.json` in the app documents folder (`{rev, items, settings}`)
class NotesLocalStore {
  NotesLocalStore({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file(String deviceId) async {
    final safe = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${(await _directory()).path}/notes_$safe.json');
  }

  /// Empty copy if missing or corrupt
  Future<NotesCache> read(String deviceId) async {
    try {
      final f = await _file(deviceId);
      if (!await f.exists()) return const NotesCache();
      final j = jsonDecode(await f.readAsString());
      return j is Map<String, dynamic> ? NotesCacheModel.fromJson(j) : const NotesCache();
    } on Exception {
      return const NotesCache();
    }
  }

  /// Writes to a temp file and renames it (so the previous copy survives if the app dies mid-write)
  Future<void> write(String deviceId, NotesCache cache) async {
    final f = await _file(deviceId);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(NotesCacheModel.toJson(cache)), flush: true);
    await tmp.rename(f.path);
  }
}
