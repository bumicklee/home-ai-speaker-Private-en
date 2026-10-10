import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/storage/key_vault.dart';
import '../../domain/entities/telegram.dart';
import '../../domain/repositories/telegram_repository.dart';

enum TokenCheck {
  idle,
  checking,
  valid, // getMe succeeded
  invalid, // Telegram rejected it (or the shape is wrong)
  failed, // could not reach Telegram
}

enum TokenSave { idle, saving, saved, failed }

enum Pairing {
  idle,
  requesting,
  waiting, // code shown, waiting for tg_paired
  expired,
  paired,
  noToken, // 409: the speaker has no token
  failed,
}

class TelegramConnectState extends Equatable {
  const TelegramConnectState({
    this.token = '',
    this.check = TokenCheck.idle,
    this.botName = '',
    this.save = TokenSave.idle,
    this.pairing = Pairing.idle,
    this.code,
    this.remaining = Duration.zero,
    this.pairedChat,
    this.failure,
  });

  final String token;
  final TokenCheck check;

  /// Bot name checked with getMe (without @)
  final String botName;
  final TokenSave save;
  final Pairing pairing;
  final PairingCode? code;
  final Duration remaining;
  final PairedChat? pairedChat;

  /// Saving or getting the code failed (BLE or LAN)
  final Failure? failure;

  /// Bot name used for the t.me link and group command (the name the app checked, if the speaker doesn't know it yet)
  String get bot => (code?.bot.isNotEmpty ?? false) ? code!.bot : botName;

  TelegramConnectState copyWith({
    String? token,
    TokenCheck? check,
    String? botName,
    TokenSave? save,
    Pairing? pairing,
    PairingCode? Function()? code,
    Duration? remaining,
    PairedChat? Function()? pairedChat,
    Failure? Function()? failure,
  }) =>
      TelegramConnectState(
        token: token ?? this.token,
        check: check ?? this.check,
        botName: botName ?? this.botName,
        save: save ?? this.save,
        pairing: pairing ?? this.pairing,
        code: code != null ? code() : this.code,
        remaining: remaining ?? this.remaining,
        pairedChat: pairedChat != null ? pairedChat() : this.pairedChat,
        failure: failure != null ? failure() : this.failure,
      );

  @override
  List<Object?> get props => [token, check, botName, save, pairing, code, remaining, pairedChat, failure];
}

/// Telegram connection: check the token (getMe) → save it to the speaker over BLE → pairing code → wait for `tg_paired` (design document, Sections 3.4 and 3.5)
class TelegramConnectCubit extends Cubit<TelegramConnectState> {
  TelegramConnectCubit(this._repo, this._vault, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now,
        super(const TelegramConnectState()) {
    _pairedSub = _repo.paired().listen(_onPaired);
  }

  final TelegramRepository _repo;
  final KeyVault _vault;
  final DateTime Function() _now;
  late final StreamSubscription<PairedChat> _pairedSub;
  Timer? _ticker;
  DateTime? _expiresAt;

  /// Fill in the token remembered on the phone
  Future<void> init() async {
    final saved = await _vault.telegramToken() ?? '';
    if (isClosed || saved.isEmpty || state.token.isNotEmpty) return;
    emit(state.copyWith(token: saved));
  }

  void tokenChanged(String value) {
    final token = value.trim();
    if (token == state.token) return;
    emit(state.copyWith(token: token, check: TokenCheck.idle, botName: '', save: TokenSave.idle, failure: () => null));
  }

  /// If valid, remember it on the phone (user request 2026-10-03)
  Future<void> checkToken() async {
    final token = state.token;
    if (token.isEmpty) return;
    emit(state.copyWith(check: TokenCheck.checking, failure: () => null));
    final r = await _repo.checkToken(token);
    if (isClosed || token != state.token) return;
    final name = r.fold((_) => null, (v) => v);
    if (r.isLeft()) {
      emit(state.copyWith(check: TokenCheck.failed));
    } else if (name == null) {
      emit(state.copyWith(check: TokenCheck.invalid));
    } else {
      await _vault.saveTelegramToken(token);
      emit(state.copyWith(check: TokenCheck.valid, botName: name));
    }
  }

  /// After the user holds Key2 for 3 seconds. With [pairAfter], get a pairing code as soon as it is saved
  Future<void> saveToSpeaker({bool pairAfter = true}) async {
    if (state.check != TokenCheck.valid || state.save == TokenSave.saving) return;
    emit(state.copyWith(save: TokenSave.saving, failure: () => null));
    final r = await _repo.saveTokenToSpeaker(state.token);
    if (isClosed) return;
    final ok = r.fold((f) {
      emit(state.copyWith(save: TokenSave.failed, failure: () => f));
      return false;
    }, (_) => true);
    if (!ok) return;
    emit(state.copyWith(save: TokenSave.saved));
    if (pairAfter) await startPairing();
  }

  /// New code (5 minutes, single use). Calling again voids the previous code
  Future<void> startPairing() async {
    _ticker?.cancel();
    emit(state.copyWith(pairing: Pairing.requesting, code: () => null, pairedChat: () => null, failure: () => null));
    final r = await _repo.startPairing();
    if (isClosed) return;
    r.fold((f) {
      final noToken = f is DeviceFailure && (f.status == 409 || f.code == 'NO_TOKEN');
      emit(state.copyWith(pairing: noToken ? Pairing.noToken : Pairing.failed, failure: () => f));
    }, (code) {
      _expiresAt = _now().add(code.expiresIn);
      emit(state.copyWith(pairing: Pairing.waiting, code: () => code, remaining: code.expiresIn));
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    });
  }

  /// Counts the time left down every second and expires at zero (tests call it directly)
  @visibleForTesting
  void tick() {
    final end = _expiresAt;
    if (end == null || isClosed || state.pairing != Pairing.waiting) return;
    final left = end.difference(_now());
    if (left <= Duration.zero) {
      _ticker?.cancel();
      emit(state.copyWith(pairing: Pairing.expired, remaining: Duration.zero));
    } else {
      emit(state.copyWith(remaining: left));
    }
  }

  void _onPaired(PairedChat chat) {
    if (state.pairing != Pairing.waiting) return;
    _ticker?.cancel();
    emit(state.copyWith(pairing: Pairing.paired, pairedChat: () => chat));
  }

  @override
  Future<void> close() async {
    _ticker?.cancel();
    await _pairedSub.cancel();
    return super.close();
  }
}
