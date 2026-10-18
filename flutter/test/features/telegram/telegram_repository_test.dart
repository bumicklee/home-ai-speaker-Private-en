import 'dart:async';

import 'package:aispeaker/core/ble/ble_speaker.dart';
import 'package:aispeaker/core/constants/ble_protocol.dart';
import 'package:aispeaker/core/device/current_device.dart';
import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/services/device_event_service.dart';
import 'package:aispeaker/features/telegram/data/datasources/telegram_bot_api_datasource.dart';
import 'package:aispeaker/features/telegram/data/datasources/telegram_remote_datasource.dart';
import 'package:aispeaker/features/telegram/data/repositories/telegram_repository_impl.dart';
import 'package:aispeaker/features/telegram/domain/entities/telegram.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements TelegramRemoteDataSource {}

class MockBle extends Mock implements BleSpeakerDataSource {}

class MockSession extends Mock implements BleSpeakerSession {}

class MockCurrent extends Mock implements CurrentDevice {}

class MockEvents extends Mock implements DeviceEventService {}

class MockDio extends Mock implements Dio {}

const mac = 'A1B2C3EB1650';
const token = '7712345678:AAHabcdefghijklmnopqrstuvwxyz012345';

void main() {
  late MockRemote remote;
  late MockBle ble;
  late MockSession session;
  late MockCurrent current;
  late MockEvents events;
  late MockDio dio;
  late StreamController<DeviceEvent> stream;
  late TelegramRepositoryImpl repo;

  setUp(() {
    remote = MockRemote();
    ble = MockBle();
    session = MockSession();
    current = MockCurrent();
    events = MockEvents();
    dio = MockDio();
    stream = StreamController<DeviceEvent>.broadcast();
    when(() => current.deviceId).thenReturn(mac);
    when(() => events.on(any())).thenAnswer((i) {
      final type = i.positionalArguments.first as String;
      return stream.stream.where((e) => e.type == type);
    });
    when(() => ble.connectById(mac)).thenAnswer((_) async => session);
    when(() => session.setSecret(any(), any())).thenAnswer((_) async {});
    when(() => session.closeWindow()).thenAnswer((_) async {});
    when(() => session.disconnect()).thenAnswer((_) async {});
    repo = TelegramRepositoryImpl(remote, TelegramBotApiDataSource(dio), ble, current, events);
  });

  test('overview: reads the firmware JSON (chats, state, bot, unread)', () async {
    when(() => remote.chats()).thenAnswer((_) async => {
          'chats': [
            {'chat_id': 12345678, 'alias': 'Mom', 'title': 'Kim Mira', 'type': 'private'},
            {'chat_id': -1001234567890.0, 'alias': 'Family', 'title': 'Our Family', 'type': 'supergroup'},
          ],
          'state': 'ok',
          'bot': 'jarvis_home_bot',
          'unread': 2,
        });
    final r = await repo.overview();
    final o = r.getOrElse(() => throw 'fail');
    expect(o.state, TelegramState.ok);
    expect(o.bot, 'jarvis_home_bot');
    expect(o.unread, 2);
    expect(o.hasToken, isTrue);
    expect(o.chats[1], const TelegramChat(chatId: -1001234567890, alias: 'Family', title: 'Our Family', type: 'supergroup'));
    expect(o.chats[1].isGroup, isTrue);
    verifyNever(() => remote.secrets());
  });

  test('overview: when state is off, checks /status secrets for the token', () async {
    when(() => remote.chats()).thenAnswer((_) async => {'chats': [], 'state': 'off', 'bot': '', 'unread': 0});
    when(() => remote.secrets()).thenAnswer((_) async => {'openai_key': true, 'tg_bot_token': false});
    final o = (await repo.overview()).getOrElse(() => throw 'fail');
    expect(o.hasToken, isFalse);

    when(() => remote.secrets()).thenAnswer((_) async => {'tg_bot_token': true});
    expect((await repo.overview()).getOrElse(() => throw 'fail').hasToken, isTrue);
  });

  test('pair: code, expiry, bot name; 409 NO_TOKEN without a token', () async {
    when(() => remote.pair()).thenAnswer((_) async => {'code': '482913', 'expires_s': 300, 'bot': 'jarvis_home_bot'});
    expect(await repo.startPairing(),
        const Right(PairingCode(code: '482913', expiresIn: Duration(minutes: 5), bot: 'jarvis_home_bot')));

    when(() => remote.pair()).thenThrow(const DeviceApiException(409, 'NO_TOKEN'));
    final f = (await repo.startPairing()).swap().getOrElse(() => throw 'fail');
    expect(f, isA<DeviceFailure>().having((d) => d.status, 'status', 409).having((d) => d.code, 'code', 'NO_TOKEN'));
  });

  test('saveTokenToSpeaker: writes tg_bot_token over BLE, closes the window, disconnects', () async {
    expect(await repo.saveTokenToSpeaker(token), const Right(unit));
    verifyInOrder([
      () => ble.connectById(mac),
      () => session.setSecret(SecretKey.telegramBot, token),
      () => session.closeWindow(),
      () => session.disconnect(),
    ]);
  });

  test('saveTokenToSpeaker: BLE failure is BleFailure, still disconnects', () async {
    when(() => session.setSecret(any(), any())).thenThrow(const BleException(BleErrorCode.disconnected));
    final f = (await repo.saveTokenToSpeaker(token)).swap().getOrElse(() => throw 'fail');
    expect(f, isA<BleFailure>());
    verify(() => session.disconnect()).called(1);
    verifyNever(() => session.closeWindow());
  });

  test('saveTokenToSpeaker: BleFailure when the speaker is not found', () async {
    when(() => ble.connectById(mac)).thenThrow(const BleException(BleErrorCode.notFound));
    expect((await repo.saveTokenToSpeaker(token)).isLeft(), isTrue);
  });

  test('rename and options: firmware paths and bodies', () async {
    when(() => remote.rename(any(), any())).thenAnswer((_) async {});
    when(() => remote.saveOptions(any()))
        .thenAnswer((_) async => {'auto_read': true, 'quiet_start': 23, 'quiet_end': 6});
    expect(await repo.rename(-100123, 'Family'), const Right(unit));
    verify(() => remote.rename(-100123, 'Family')).called(1);
    final saved = await repo.saveOptions(const TelegramOptions(autoRead: true, quietStart: 23, quietEnd: 6));
    expect(saved, const Right(TelegramOptions(autoRead: true, quietStart: 23, quietEnd: 6)));
    verify(() => remote.saveOptions({'auto_read': true, 'quiet_start': 23, 'quiet_end': 6})).called(1);
  });

  test('events: tg_paired, tg_status, tg_message', () async {
    final paired = repo.paired().first;
    final status = repo.statusChanges().first;
    final unread = repo.unreadChanges().first;
    stream
      ..add(const DeviceEvent('tg_paired', {'chat_id': 42, 'title': 'Our Family', 'type': 'group'}))
      ..add(const DeviceEvent('tg_status', {'state': 'conflict'}))
      ..add(const DeviceEvent('tg_message', {'unread': 3}));
    expect(await paired, const PairedChat(chatId: 42, title: 'Our Family', type: 'group'));
    expect(await status, TelegramState.conflict);
    expect(await unread, 3);
  });

  group('getMe', () {
    final url = 'https://api.telegram.org/bot$token/getMe';
    RequestOptions req() => RequestOptions(path: url);

    test('valid token: bot name', () async {
      when(() => dio.get<Map<String, dynamic>>(url)).thenAnswer((_) async => Response(
            requestOptions: req(),
            statusCode: 200,
            data: {
              'ok': true,
              'result': {'id': 7712345678, 'is_bot': true, 'username': 'jarvis_home_bot'},
            },
          ));
      expect(await repo.checkToken(token), const Right('jarvis_home_bot'));
    });

    test('Telegram rejects (401): null', () async {
      when(() => dio.get<Map<String, dynamic>>(url)).thenThrow(DioException(
        requestOptions: req(),
        response: Response(requestOptions: req(), statusCode: 401),
        type: DioExceptionType.badResponse,
      ));
      expect(await repo.checkToken(token), const Right(null));
    });

    test('malformed token is not sent, null', () async {
      expect(await repo.checkToken('abc/../x'), const Right(null));
      verifyNever(() => dio.get<Map<String, dynamic>>(any()));
    });

    test('cannot reach Telegram: NetworkFailure, raw text (URL, token) is not kept', () async {
      when(() => dio.get<Map<String, dynamic>>(url))
          .thenThrow(DioException(requestOptions: req(), type: DioExceptionType.connectionError, message: url));
      final f = (await repo.checkToken(token)).swap().getOrElse(() => throw 'fail');
      expect(f, isA<NetworkFailure>());
      expect(f.message, isNot(contains(token)));
    });
  });
}
