import 'package:dartz/dartz.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/api_paths.dart';
import '../../../../core/constants/ble_protocol.dart';
import '../../../../core/device/current_device.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/repository/guard.dart';
import '../../../../core/services/device_event_service.dart';
import '../../domain/entities/lesson.dart';
import '../models/lesson_model.dart';

/// English Tutor (firmware lesson.c, LAN /api/v1/lesson)
class LessonRepository {
  LessonRepository(this._device, this._events, this._prefs);

  final CurrentDevice _device;
  final DeviceEventService _events;
  final SharedPreferences _prefs;

  static const _path = '/api/v1/lesson';
  static const _prefsKey = 'english_options';

  Future<Either<Failure, Lesson>> current() => guard(() async {
        final j = await _device.client.get<Map<String, dynamic>>(_path);
        return LessonModel.fromJson(j);
      });

  /// Whether the speaker has an OpenAI key (`/status.secrets`). English lessons always use OpenAI Live, so it is required
  Future<Either<Failure, bool>> openAiKeySaved() => guard(() async {
        final j = await _device.client.get<Map<String, dynamic>>(ApiPaths.status);
        return (j['secrets'] as Map<String, dynamic>? ?? const {})[SecretKey.openai] == true;
      });

  /// 409 VOICE_ACTIVE during a conversation, 409 NO_API_KEY without an OpenAI key (regardless of the AI setting), 409 without Wi-Fi
  Future<Either<Failure, Lesson>> start(LessonOptions options) => guard(() async {
        final j = await _device.client.post<Map<String, dynamic>>('$_path/start', options.toJson());
        return LessonModel.fromJson(j);
      });

  Future<Either<Failure, Unit>> stop() => guard(() async {
        await _device.client.post<dynamic>('$_path/stop');
        return unit;
      });

  Future<Either<Failure, Unit>> changeTopic() => guard(() async {
        await _device.client.post<dynamic>('$_path/topic');
        return unit;
      });

  /// WS `lesson` (the whole lesson each time its state or corrected expressions change)
  Stream<Lesson> updates() => _events.on('lesson').map((e) => LessonModel.fromJson(e.data));

  /// Last chosen course and options (on this phone)
  LessonOptions savedOptions() {
    final raw = _prefs.getStringList(_prefsKey);
    if (raw == null || raw.length != 4) return const LessonOptions();
    final minutes = int.tryParse(raw[3]) ?? 5;
    return LessonOptions(
      course: LessonCourse.fromId(raw[0]),
      explainKorean: raw[1] == 'ko',
      slow: raw[2] == 'slow',
      minutes: LessonOptions.allowedMinutes.contains(minutes) ? minutes : 5,
    );
  }

  Future<void> saveOptions(LessonOptions o) => _prefs.setStringList(
      _prefsKey, [o.course.id, o.explainKorean ? 'ko' : 'en', o.slow ? 'slow' : 'normal', '${o.minutes}']);
}
