import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/ble_protocol.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/storage/key_vault.dart';
import '../../domain/repositories/system_repository.dart';

class KeysState extends Equatable {
  const KeysState({
    this.loaded = false,
    this.onPhone = const {},
    this.onSpeaker,
    this.speakerFailure,
    this.sending,
    this.busy = false,
  });

  final bool loaded;

  /// Values remembered on the phone (KeyVault). key → value (absent if none)
  final Map<String, String> onPhone;

  /// Whether the speaker has each key saved (`/status` secrets). null if it can't connect
  final Map<String, bool>? onSpeaker;
  final Failure? speakerFailure;

  /// Key being sent over BLE
  final String? sending;

  /// Deleting over LAN
  final bool busy;

  KeysState copyWith({
    bool? loaded,
    Map<String, String>? onPhone,
    Map<String, bool>? Function()? onSpeaker,
    Failure? Function()? speakerFailure,
    String? Function()? sending,
    bool? busy,
  }) =>
      KeysState(
        loaded: loaded ?? this.loaded,
        onPhone: onPhone ?? this.onPhone,
        onSpeaker: onSpeaker != null ? onSpeaker() : this.onSpeaker,
        speakerFailure: speakerFailure != null ? speakerFailure() : this.speakerFailure,
        sending: sending != null ? sending() : this.sending,
        busy: busy ?? this.busy,
      );

  @override
  List<Object?> get props => [loaded, onPhone, onSpeaker, speakerFailure, sending, busy];
}

/// Key management: keys remembered on this phone (KeyVault) and keys saved on the speaker.
/// Sending to the speaker uses BLE only (D6). Deleting uses LAN `DELETE /keys/{key}`
class KeysCubit extends Cubit<KeysState> {
  KeysCubit(this._repo, this._vault) : super(const KeysState());

  final SystemRepository _repo;
  final KeyVault _vault;

  /// Keys handled on this screen (speaker `secret.set` names)
  static const keys = [SecretKey.openai, SecretKey.gemini, SecretKey.telegramBot];

  /// Show only the last 4 characters
  static String mask(String value) => '••••${value.substring(max(0, value.length - 4))}';

  Future<void> load() async {
    final phone = await _readVault();
    if (isClosed) return;
    emit(state.copyWith(loaded: true, onPhone: phone));
    final r = await _repo.status();
    if (isClosed) return;
    r.fold(
      (f) => emit(state.copyWith(onSpeaker: () => null, speakerFailure: () => f)),
      (s) => emit(state.copyWith(
        onSpeaker: () => {for (final k in keys) k: s.hasSecret(k)},
        speakerFailure: () => null,
      )),
    );
  }

  /// Delete from this phone only (the speaker's key stays)
  Future<void> forgetOnPhone(String key) async {
    await _save(key, null);
    if (isClosed) return;
    emit(state.copyWith(onPhone: {...state.onPhone}..remove(key)));
  }

  /// Change the speaker's key (BLE). On success, also remember it on the phone
  Future<Failure?> sendToSpeaker(String key, String value) async {
    emit(state.copyWith(sending: () => key));
    final r = await _repo.sendKeyOverBle(key, value);
    if (isClosed) return null;
    final failure = r.fold((f) => f, (_) => null);
    if (failure != null) {
      emit(state.copyWith(sending: () => null));
      return failure;
    }
    await _save(key, value);
    if (isClosed) return null;
    emit(state.copyWith(
      sending: () => null,
      onPhone: {...state.onPhone, key: value},
      onSpeaker: () => {...?state.onSpeaker, key: true},
    ));
    return null;
  }

  /// Delete from the speaker (LAN). The value remembered on the phone stays
  Future<Failure?> deleteOnSpeaker(String key) async {
    emit(state.copyWith(busy: true));
    final r = await _repo.deleteSpeakerKey(key);
    if (isClosed) return null;
    return r.fold((f) {
      emit(state.copyWith(busy: false));
      return f;
    }, (_) {
      emit(state.copyWith(busy: false, onSpeaker: () => {...?state.onSpeaker, key: false}));
      return null;
    });
  }

  Future<Map<String, String>> _readVault() async {
    final openAi = await _vault.openAiKey();
    final gemini = await _vault.geminiKey();
    final telegram = await _vault.telegramToken();
    return {
      if (openAi != null && openAi.isNotEmpty) SecretKey.openai: openAi,
      if (gemini != null && gemini.isNotEmpty) SecretKey.gemini: gemini,
      if (telegram != null && telegram.isNotEmpty) SecretKey.telegramBot: telegram,
    };
  }

  Future<void> _save(String key, String? value) => switch (key) {
        SecretKey.openai => _vault.saveOpenAiKey(value),
        SecretKey.gemini => _vault.saveGeminiKey(value),
        SecretKey.telegramBot => _vault.saveTelegramToken(value),
        _ => Future.value(),
      };
}
