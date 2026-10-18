import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/features/system/domain/entities/system_status.dart';
import 'package:aispeaker/features/system/domain/repositories/system_repository.dart';
import 'package:aispeaker/features/system/presentation/bloc/system_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements SystemRepository {}

const status = SystemStatus(firmware: '0.5.0', uptime: Duration(minutes: 5), wifiRssi: -51);
const me = RegisteredPhone(phoneId: 'p1', name: "Mom's Galaxy", self: true);
const dad = RegisteredPhone(phoneId: 'p2', name: "Dad's iPhone");

void main() {
  late MockRepo repo;

  setUp(() {
    repo = MockRepo();
    when(() => repo.status()).thenAnswer((_) async => const Right(status));
    when(() => repo.phones()).thenAnswer((_) async => const Right([me, dad]));
  });

  test('load: status and phone list, finds self', () async {
    final c = SystemCubit(repo);
    await c.load();
    expect(c.state.status, status);
    expect(c.state.phones, [me, dad]);
    expect(c.state.self, me);
    expect(c.state.failure, isNull);
  });

  test('load: a status failure is kept separate from a phone-list failure', () async {
    when(() => repo.status()).thenAnswer((_) async => const Left(NetworkFailure()));
    final c = SystemCubit(repo);
    await c.load();
    expect(c.state.status, isNull);
    expect(c.state.failure, const NetworkFailure());
    expect(c.state.phones, [me, dad]);
  });

  test('revoke: removes it from the list on success', () async {
    when(() => repo.revokePhone('p2')).thenAnswer((_) async => const Right(unit));
    final c = SystemCubit(repo);
    await c.load();
    expect(await c.revoke(dad), isNull);
    expect(c.state.phones, [me]);
    expect(c.state.busy, isFalse);
  });

  test('revoke: 404 means already gone — not a failure', () async {
    when(() => repo.revokePhone('p2'))
        .thenAnswer((_) async => Left(DeviceFailure.fromStatus(404, 'NOT_FOUND')));
    final c = SystemCubit(repo);
    await c.load();
    expect(await c.revoke(dad), isNull);
    expect(c.state.phones, [me]);
  });

  test('revoke: other failures are returned and the list is unchanged', () async {
    when(() => repo.revokePhone('p2')).thenAnswer((_) async => const Left(NetworkFailure()));
    final c = SystemCubit(repo);
    await c.load();
    expect(await c.revoke(dad), const NetworkFailure());
    expect(c.state.phones, [me, dad]);
  });

  test('reboot: 409 VOICE_ACTIVE during a conversation → in-conversation message key', () async {
    when(() => repo.reboot()).thenAnswer((_) async => Left(DeviceFailure.fromStatus(409, 'VOICE_ACTIVE')));
    final c = SystemCubit(repo);
    final f = await c.reboot();
    expect(f?.errorKey, ErrorKeys.deviceVoiceActive);
    expect(c.state.busy, isFalse);
  });

  test('reboot: success', () async {
    when(() => repo.reboot()).thenAnswer((_) async => const Right(unit));
    expect(await SystemCubit(repo).reboot(), isNull);
  });

  test('revokeSelf: loads the list if not loaded yet, then revokes this phone', () async {
    when(() => repo.revokePhone('p1')).thenAnswer((_) async => const Right(unit));
    final c = SystemCubit(repo);
    expect(await c.revokeSelf(), isTrue);
    verify(() => repo.revokePhone('p1')).called(1);
  });

  test('revokeSelf: false when unreachable (removal continues)', () async {
    when(() => repo.phones()).thenAnswer((_) async => const Left(NetworkFailure()));
    expect(await SystemCubit(repo).revokeSelf(), isFalse);
    verifyNever(() => repo.revokePhone(any()));
  });
}
