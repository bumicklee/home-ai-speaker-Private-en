import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/telegram.dart';
import '../../domain/repositories/telegram_repository.dart';

class TelegramViewState extends Equatable {
  const TelegramViewState({
    this.loading = true,
    this.overview,
    this.options = const TelegramOptions(),
    this.failure,
    this.actionFailure,
  });

  final bool loading;
  final TelegramOverview? overview;
  final TelegramOptions options;

  /// Loading failed (full-screen error)
  final Failure? failure;

  /// Saving an alias, delete, or option failed (snackbar). Cleared when an action starts
  final Failure? actionFailure;

  /// If the speaker has no token, show the connection screen
  bool get needsSetup => overview != null && !overview!.hasToken;

  TelegramViewState copyWith({
    bool? loading,
    TelegramOverview? Function()? overview,
    TelegramOptions? options,
    Failure? Function()? failure,
    Failure? Function()? actionFailure,
  }) =>
      TelegramViewState(
        loading: loading ?? this.loading,
        overview: overview != null ? overview() : this.overview,
        options: options ?? this.options,
        failure: failure != null ? failure() : this.failure,
        actionFailure: actionFailure != null ? actionFailure() : this.actionFailure,
      );

  @override
  List<Object?> get props => [loading, overview, options, failure, actionFailure];
}

/// Telegram screen: state, chats, notification options. Reflects WS `tg_status`, `tg_message`, and `tg_paired`
class TelegramCubit extends Cubit<TelegramViewState> {
  TelegramCubit(this._repo) : super(const TelegramViewState()) {
    _subs = [
      _repo.statusChanges().listen(_onStatus),
      _repo.unreadChanges().listen(_onUnread),
      _repo.paired().listen((_) => load()),
    ];
  }

  final TelegramRepository _repo;
  late final List<StreamSubscription<Object?>> _subs;

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: () => null));
    final results = await Future.wait([_repo.overview(), _repo.options()]);
    if (isClosed) return;
    final overview = results[0] as Either<Failure, TelegramOverview>;
    final options = results[1] as Either<Failure, TelegramOptions>;
    overview.fold(
      (f) => emit(state.copyWith(loading: false, failure: () => f)),
      (o) => emit(state.copyWith(
        loading: false,
        overview: () => o,
        // Show the chats even if the options can't be read (default 22–7)
        options: options.fold((_) => state.options, (v) => v),
      )),
    );
  }

  /// Update the screen first, and roll back on failure
  Future<bool> rename(int chatId, String alias) async {
    final before = state.overview;
    if (before == null) return false;
    _setChats(before, [for (final c in before.chats) c.chatId == chatId ? c.copyWith(alias: alias) : c]);
    return _act(() => _repo.rename(chatId, alias), revert: before);
  }

  Future<bool> remove(int chatId) async {
    final before = state.overview;
    if (before == null) return false;
    _setChats(before, [for (final c in before.chats) if (c.chatId != chatId) c]);
    return _act(() => _repo.remove(chatId), revert: before);
  }

  Future<void> setAutoRead(bool value) => _saveOptions(state.options.copyWith(autoRead: value));

  Future<void> setQuietHours(int start, int end) =>
      _saveOptions(state.options.copyWith(quietStart: start, quietEnd: end));

  Future<void> _saveOptions(TelegramOptions next) async {
    final before = state.options;
    emit(state.copyWith(options: next, actionFailure: () => null));
    final r = await _repo.saveOptions(next);
    if (isClosed) return;
    r.fold(
      (f) => emit(state.copyWith(options: before, actionFailure: () => f)),
      (saved) => emit(state.copyWith(options: saved)),
    );
  }

  void _setChats(TelegramOverview o, List<TelegramChat> chats) =>
      emit(state.copyWith(overview: () => o.copyWith(chats: chats), actionFailure: () => null));

  Future<bool> _act(Future<Either<Failure, Unit>> Function() run, {required TelegramOverview revert}) async {
    final r = await run();
    if (isClosed) return false;
    return r.fold((f) {
      emit(state.copyWith(overview: () => revert, actionFailure: () => f));
      return false;
    }, (_) => true);
  }

  void _onStatus(String s) {
    final o = state.overview;
    if (o == null) return;
    // If a token was added or removed, the bot name and token presence change, so reload
    if ((s == TelegramState.off) != (o.state == TelegramState.off) || (s == TelegramState.ok && o.bot.isEmpty)) {
      load();
    } else {
      emit(state.copyWith(overview: () => o.copyWith(state: s)));
    }
  }

  void _onUnread(int unread) {
    final o = state.overview;
    if (o != null) emit(state.copyWith(overview: () => o.copyWith(unread: unread)));
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
