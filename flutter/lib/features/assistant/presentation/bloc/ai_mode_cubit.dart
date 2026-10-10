import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/ai/ai_choice.dart';
import '../../../../core/constants/ble_protocol.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/storage/key_vault.dart';
import '../../../system/domain/repositories/system_repository.dart';
import '../../data/models/assistant_settings_model.dart';
import '../../domain/entities/assistant_settings.dart';
import '../../domain/repositories/assistant_repository.dart';

/// Why an AI/mode card can't be tapped
enum AiLock {
  none,

  /// The speaker has no key for this provider ("키 없음 · 쓸 수 없어요")
  noKey,

  /// This firmware can't do it yet (not in `/status.ai.available`, "준비 중")
  notReady,
}

class AiModeState extends Equatable {
  const AiModeState({
    this.settings,
    this.secrets,
    this.ai = AiStatus.legacy,
    this.loading = false,
    this.saving = false,
    this.failure,
  });

  /// The speaker's assistant settings (ai_provider, mode_openai, mode_gemini)
  final AssistantSettings? settings;

  /// `/status.secrets`. null if the status couldn't be read (then don't lock by key; the speaker blocks it once more)
  final Map<String, bool>? secrets;
  final AiStatus ai;
  final bool loading;

  /// Changing (cards can't be tapped)
  final bool saving;

  /// Load failed (whole screen)
  final Failure? failure;

  AiProvider get provider => settings?.aiProvider ?? AiProvider.openai;
  AiMode get mode => settings?.aiMode ?? AiMode.live;

  /// Whether the speaker has the key (null if unknown)
  bool? hasKey(AiProvider p) => secrets == null ? null : (secrets![p.secretKey] ?? false);

  AiLock providerLock(AiProvider p) {
    if (hasKey(p) == false) return AiLock.noKey;
    if (!ai.providerAvailable(p)) return AiLock.notReady;
    return AiLock.none;
  }

  AiLock modeLock(AiProvider p, AiMode m) => ai.isAvailable(p, m) ? AiLock.none : AiLock.notReady;

  AiModeState copyWith({
    AssistantSettings? settings,
    Map<String, bool>? Function()? secrets,
    AiStatus? ai,
    bool? loading,
    bool? saving,
    Failure? Function()? failure,
  }) =>
      AiModeState(
        settings: settings ?? this.settings,
        secrets: secrets != null ? secrets() : this.secrets,
        ai: ai ?? this.ai,
        loading: loading ?? this.loading,
        saving: saving ?? this.saving,
        failure: failure != null ? failure() : this.failure,
      );

  @override
  List<Object?> get props => [settings, secrets, ai, loading, saving, failure];
}

/// Assistant > AI · Conversation mode (design docs/design-voice-saver-mode.md Sections 9 and 11.8).
/// Changes go straight to LAN `PUT /settings/assistant` (partial). Keys go over BLE only (same path as System > Keys)
class AiModeCubit extends Cubit<AiModeState> {
  AiModeCubit(this._assistant, this._system, this._vault) : super(const AiModeState());

  final AssistantRepository _assistant;
  final SystemRepository _system;
  final KeyVault _vault;

  /// The speaker refused because it has no key (LAN 409 / BLE `NO_API_KEY`)
  static bool isNoKey(Failure f) => f.code == BleCmdError.noApiKey;

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: () => null));
    final settings = _assistant.settings();
    final status = _system.status();
    final s = await settings;
    final st = await status;
    if (isClosed) return;
    s.fold(
      (f) => emit(state.copyWith(loading: false, failure: () => f)),
      (v) => st.fold(
        (_) => emit(AiModeState(settings: v)),
        (x) => emit(AiModeState(settings: v, secrets: x.secrets, ai: x.ai)),
      ),
    );
  }

  /// ① Change the AI. If that provider's last mode doesn't work on this speaker, switch to one that does at the same time
  Future<Failure?> chooseProvider(AiProvider p) async {
    final s = state.settings;
    if (s == null || state.saving || p == s.aiProvider || state.providerLock(p) != AiLock.none) return null;
    var m = s.modeOf(p);
    if (!state.ai.isAvailable(p, m)) {
      m = AiMode.values.firstWhere((x) => state.ai.isAvailable(p, x), orElse: () => m);
    }
    final changes = <String, dynamic>{
      AssistantSettingsModel.keyAiProvider: p.id,
      if (m != s.modeOf(p)) p.modeSettingKey: m.id,
    };
    return _put(changes, provider: p);
  }

  /// ② Change the mode of the current AI
  Future<Failure?> chooseMode(AiMode m) async {
    final s = state.settings;
    final p = state.provider;
    if (s == null || state.saving || m == s.modeOf(p) || state.modeLock(p, m) != AiLock.none) return null;
    return _put({p.modeSettingKey: m.id}, provider: p);
  }

  Future<Failure?> _put(Map<String, dynamic> changes, {required AiProvider provider}) async {
    emit(state.copyWith(saving: true));
    final r = await _assistant.update(changes);
    if (isClosed) return r.fold((f) => f, (_) => null);
    return r.fold((f) {
      // The key was erased on the speaker: lock the card
      final secrets =
          isNoKey(f) && state.secrets != null ? {...state.secrets!, provider.secretKey: false} : state.secrets;
      emit(state.copyWith(saving: false, secrets: () => secrets));
      return f;
    }, (saved) {
      emit(state.copyWith(saving: false, settings: saved));
      return null;
    });
  }

  /// Key remembered on the phone (pre-fills the "키 넣기" field)
  Future<String> rememberedKey(AiProvider p) async =>
      (p == AiProvider.openai ? await _vault.openAiKey() : await _vault.geminiKey()) ?? '';

  /// "○○ 키 넣기" (enter key): BLE `secret.set` (after the user holds Key2 for 3 seconds to open the BLE window). On success, the phone remembers it too
  Future<Failure?> sendKey(AiProvider p, String value) async {
    final r = await _system.sendKeyOverBle(p.secretKey, value);
    if (isClosed) return r.fold((f) => f, (_) => null);
    final failure = r.fold((f) => f, (_) => null);
    if (failure != null) return failure;
    await (p == AiProvider.openai ? _vault.saveOpenAiKey(value) : _vault.saveGeminiKey(value));
    if (isClosed) return null;
    emit(state.copyWith(secrets: () => {...?state.secrets, p.secretKey: true}));
    return null;
  }
}
