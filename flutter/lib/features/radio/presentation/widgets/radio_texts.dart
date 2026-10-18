import '../../../../core/errors/error_localizer.dart';
import '../../../../core/errors/failures.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/radio_rules.dart';

/// Shared text for the radio screens
extension RadioTexts on AppLocalizations {
  String presetErrorText(PresetError e) => switch (e) {
        PresetError.tooMany => radioErrTooMany(RadioLimits.maxPresets),
        PresetError.nameEmpty => radioErrNameEmpty,
        PresetError.nameTooLong => radioErrNameTooLong,
        PresetError.urlInvalid => radioErrUrlInvalid,
        PresetError.urlTooLong => radioErrUrlTooLong,
        PresetError.genreTooLong => radioErrGenreTooLong,
        PresetError.tooLarge => radioErrTooLarge,
        PresetError.duplicate => radioErrDuplicate,
      };

  String presetGroupText(PresetGroup g) => switch (g) {
        PresetGroup.music => radioGroupMusic,
        PresetGroup.korean => radioGroupKorean,
        PresetGroup.news => radioGroupNews,
        PresetGroup.talk => radioGroupTalk,
        PresetGroup.other => radioGroupOther,
      };

  /// 409 NOT_PLAYING has no shared key, so pick it here (the shared one shows as "Busy")
  String radioFailureText(Failure f) =>
      f is DeviceFailure && f.code == 'NOT_PLAYING' ? radioNotPlaying : errorText(f);
}
