import 'package:aispeaker/core/ai/ai_choice.dart';
import 'package:aispeaker/core/ble/ble_link.dart';
import 'package:aispeaker/core/ble/ble_secret_writer.dart';
import 'package:aispeaker/core/ble/wifi_scan.dart';
import 'package:aispeaker/core/constants/ble_protocol.dart';
import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/storage/key_vault.dart';
import 'package:aispeaker/features/devices/domain/entities/device.dart';
import 'package:aispeaker/features/provisioning/domain/entities/provisioning_input.dart';
import 'package:aispeaker/features/provisioning/domain/repositories/provisioning_repository.dart';
import 'package:aispeaker/features/provisioning/presentation/bloc/provisioning_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements ProvisioningRepository {}

class MockVault extends Mock implements KeyVault {}

const mac = 'A1B2C3EB1650';
final speaker = DiscoveredSpeaker(device: BluetoothDevice.fromId('00:11:22:33:44:55'), name: 'JARVIS_EB1650', rssi: -50);

/// Firmware that supports every combination (stage 3)
const allAi = AiStatus(
  provider: AiProvider.openai,
  mode: AiMode.saver,
  available: {'openai.live', 'openai.saver', 'gemini.saver', 'gemini.live'},
);

/// Stage 1 firmware: OpenAI only
const stage1 = AiStatus(provider: AiProvider.openai, mode: AiMode.saver, available: {'openai.live', 'openai.saver'});

DeviceInfo info({
  bool provisioned = false,
  bool wifi = false,
  bool key = false,
  bool gemini = false,
  AiStatus ai = allAi,
}) =>
    DeviceInfo(
      protocolVersion: 1,
      firmware: '0.5.0',
      mac: mac,
      provisioned: provisioned,
      wifiConnected: wifi,
      secrets: {'openai_key': key, 'gemini_key': gemini},
      ai: ai,
    );

const geminiKey = 'AIzaSyA1234567890abcdefghijklmnopqrstu';

const input = ProvisioningInput(openAiKey: 'sk-proj-abcdefghijklmnopqrstuvwx', phoneName: '엄마 폰');
const found = Device(id: mac, name: 'JARVIS_EB1650', host: '192.168.0.156');

void main() {
  late MockRepo repo;
  late MockVault vault;

  setUpAll(() {
    registerFallbackValue(const Device(id: 'x', name: 'x'));
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    repo = MockRepo();
    vault = MockVault();
    when(() => vault.openAiKey()).thenAnswer((_) async => null);
    when(() => vault.geminiKey()).thenAnswer((_) async => null);
    when(() => vault.telegramToken()).thenAnswer((_) async => null);
    when(() => vault.saveOpenAiKey(any())).thenAnswer((_) async {});
    when(() => vault.saveGeminiKey(any())).thenAnswer((_) async {});
    when(() => vault.saveTelegramToken(any())).thenAnswer((_) async {});
    when(() => repo.defaultPhoneName()).thenAnswer((_) async => 'Galaxy');
    when(() => repo.ensureReady()).thenAnswer((_) async => const Right(unit));
    when(() => repo.scan()).thenAnswer((_) => Stream.value([speaker]));
    when(() => repo.setSecret(any(), any())).thenAnswer((_) async => const Right(unit));
    when(() => repo.pair(any(), evict: any(named: 'evict')))
        .thenAnswer((_) async => const Right(PairResult(token: 'tok', phoneId: 'p1')));
    when(() => repo.setSettings(any(), any())).thenAnswer((_) async => const Right(unit));
    when(() => repo.finish()).thenAnswer((_) async => const Right(unit));
    when(() => repo.disconnect()).thenAnswer((_) async {});
    when(() => repo.discover(any(), any(), timeout: any(named: 'timeout'))).thenAnswer((_) async => found);
    when(() => repo.save(any(), any())).thenAnswer((_) async => const Right(unit));
  });

  test('init: 기억해 둔 키와 기본 휴대폰 이름을 채운다', () async {
    when(() => vault.openAiKey()).thenAnswer((_) async => 'sk-saved');
    when(() => vault.telegramToken()).thenAnswer((_) async => '1:tg');
    final c = ProvisioningCubit(repo, vault);
    await c.init();
    expect(c.state.input, const ProvisioningInput(openAiKey: 'sk-saved', telegramToken: '1:tg', phoneName: 'Galaxy'));
  });

  test('새 스피커: 키 → 찾기 → Wi-Fi → 등록 → 완료, 키는 휴대폰에 기억', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info()));
    when(() => repo.scanWifi()).thenAnswer((_) async =>
        const Right([WifiNetwork(ssid: 'HomeWiFi', rssi: -50, security: WifiSecurity.wpa2)]));
    when(() => repo.provisionWifi('HomeWiFi', 'pw')).thenAnswer((_) async => const Right(WifiProvStatus.success));
    final c = ProvisioningCubit(repo, vault);

    await c.submitKeys(input, remember: true);
    await Future<void>.delayed(Duration.zero);
    expect(c.state.speakers, [speaker]);
    verify(() => vault.saveOpenAiKey(input.openAiKey)).called(1);

    await c.selectSpeaker(speaker);
    expect(c.state.step, ProvStep.wifiList);

    await c.connectWifi('HomeWiFi', 'pw');
    expect(c.state.step, ProvStep.done);
    expect(c.state.device, found);
    expect(c.state.wifiChanged, isTrue);
    verify(() => repo.setSecret(SecretKey.openai, input.openAiKey)).called(1);
    verify(() => repo.setSettings('assistant', {'ai_provider': 'openai', 'mode_openai': 'saver'})).called(1);
    verify(() => repo.save(found, 'tok')).called(1);
    await c.close();
  });

  test('이미 Wi-Fi·키가 있는 스피커(휴대폰 추가): Wi-Fi 유지, 키 비우면 보내지 않음', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(provisioned: true, wifi: true, key: true)));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(const ProvisioningInput(existingKey: true, phoneName: '아빠 폰'), remember: true);
    await c.selectSpeaker(speaker);
    expect(c.state.step, ProvStep.wifiChoice);
    await c.keepWifi();
    expect(c.state.step, ProvStep.done);
    expect(c.state.wifiChanged, isFalse);
    verifyNever(() => repo.setSecret(any(), any()));
    verify(() => repo.pair('아빠 폰')).called(1);
    await c.close();
  });

  test('고른 AI 키도 "이미 있음"도 없으면 스피커를 찾지 않는다', () async {
    final c = ProvisioningCubit(repo, vault);
    expect(const ProvisioningInput(phoneName: 'p').canSearch, isFalse);
    expect(await c.submitKeys(const ProvisioningInput(phoneName: 'p'), remember: true), isFalse);
    expect(c.state.step, ProvStep.keys);
    verifyNever(() => repo.scan());
    // If OpenAI is chosen, a key for another AI (Gemini) alone is not enough to proceed
    expect(const ProvisioningInput(geminiKey: geminiKey, phoneName: 'p').canSearch, isFalse);
    expect(
        const ProvisioningInput(provider: AiProvider.gemini, geminiKey: geminiKey, phoneName: 'p').canSearch, isTrue);
    await c.close();
  });

  test('"이미 있음"인데 스피커에 그 AI 키가 없으면 연결을 끊고 1단계로 (안내와 함께)', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(gemini: true)));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(const ProvisioningInput(existingKey: true, phoneName: 'p'), remember: false);
    await c.selectSpeaker(speaker);
    expect(c.state.step, ProvStep.keys);
    expect(c.state.missingKey, AiProvider.openai);
    expect(c.state.input.existingKey, isFalse); // pick again
    verify(() => repo.disconnect()).called(1);
    verify(() => vault.saveOpenAiKey(null)).called(1);
    verify(() => vault.saveGeminiKey(null)).called(1);
    verifyNever(() => repo.scanWifi());
    // Moving on again clears the notice
    await c.submitKeys(input, remember: false);
    expect(c.state.missingKey, isNull);
    await c.close();
  });

  test('"이미 있음" + 스피커에 그 AI 키가 있으면 키를 보내지 않고 진행, 고른 AI·방식은 보낸다', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(provisioned: true, wifi: true, gemini: true)));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(
        const ProvisioningInput(provider: AiProvider.gemini, mode: AiMode.live, existingKey: true, phoneName: 'p'),
        remember: true);
    await c.selectSpeaker(speaker);
    expect(c.state.step, ProvStep.wifiChoice);
    await c.keepWifi();
    expect(c.state.step, ProvStep.done);
    verifyNever(() => repo.setSecret(any(), any()));
    verify(() => repo.setSettings('assistant', {'ai_provider': 'gemini', 'mode_gemini': 'live'})).called(1);
    await c.close();
  });

  test('Gemini 키를 넣으면 gemini_key로 보내고, 두 키 모두 기억한다', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(provisioned: true, wifi: true)));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(
        ProvisioningInput(
            provider: AiProvider.gemini, openAiKey: input.openAiKey, geminiKey: geminiKey, phoneName: 'p'),
        remember: true);
    verify(() => vault.saveGeminiKey(geminiKey)).called(1);
    verify(() => vault.saveOpenAiKey(input.openAiKey)).called(1);
    await c.selectSpeaker(speaker);
    await c.keepWifi();
    expect(c.state.step, ProvStep.done);
    verify(() => repo.setSecret(SecretKey.openai, input.openAiKey)).called(1);
    verify(() => repo.setSecret(SecretKey.gemini, geminiKey)).called(1);
    verify(() => repo.setSettings('assistant', {'ai_provider': 'gemini', 'mode_gemini': 'saver'})).called(1);
    await c.close();
  });

  test('settings.set이 NO_API_KEY면 1단계로 (완료 단계로 가지 않음)', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(provisioned: true, wifi: true, key: true)));
    when(() => repo.setSettings(any(), any())).thenAnswer((_) async => const Left(
        BleFailure(errorKey: ErrorKeys.deviceNoApiKey, code: BleCmdError.noApiKey)));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(input, remember: true);
    await c.selectSpeaker(speaker);
    await c.keepWifi();
    expect(c.state.step, ProvStep.keys);
    expect(c.state.missingKey, AiProvider.openai);
    verifyNever(() => repo.finish());
    await c.close();
  });

  test('이 스피커가 아직 못 하는 AI(1단계 펌웨어의 Gemini)면 연결을 끊고 1단계로 (준비 중 안내)', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(gemini: true, ai: stage1)));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(
        const ProvisioningInput(provider: AiProvider.gemini, geminiKey: geminiKey, phoneName: 'p'),
        remember: false);
    await c.selectSpeaker(speaker);
    expect(c.state.step, ProvStep.keys);
    expect(c.state.notReady, AiProvider.gemini);
    expect(c.state.missingKey, isNull);
    verify(() => repo.disconnect()).called(1);
    verifyNever(() => repo.scanWifi());
    verifyNever(() => repo.setSecret(any(), any()));
    // Moving on again clears the notice
    await c.submitKeys(input, remember: false);
    expect(c.state.notReady, isNull);
    await c.close();
  });

  test('옛 펌웨어(device.info에 ai 없음): openai.live만 → 절약을 골랐어도 실시간으로 보낸다', () async {
    final j = {
      'protocol_version': 1,
      'mac': mac,
      'provisioned': true,
      'wifi_connected': true,
      'secrets': {'openai_key': true},
    };
    final old = DeviceInfo.fromJson(j);
    expect(old.ai, AiStatus.legacy);
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(old));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(const ProvisioningInput(existingKey: true, phoneName: 'p'), remember: true);
    await c.selectSpeaker(speaker);
    expect(c.state.step, ProvStep.wifiChoice);
    expect(c.state.input.mode, AiMode.live);
    await c.keepWifi();
    verify(() => repo.setSettings('assistant', {'ai_provider': 'openai', 'mode_openai': 'live'})).called(1);
    await c.close();
  });

  test('device.info.ai 해석', () {
    final i = DeviceInfo.fromJson({
      'ai': {
        'provider': 'openai',
        'mode': 'saver',
        'available': ['openai.live', 'openai.saver'],
      },
    });
    expect(i.ai, stage1);
  });

  test('init: Gemini 키만 기억해 뒀으면 Gemini를 먼저 고른다', () async {
    when(() => vault.geminiKey()).thenAnswer((_) async => geminiKey);
    final c = ProvisioningCubit(repo, vault);
    await c.init();
    expect(c.state.input.provider, AiProvider.gemini);
    expect(c.state.input.geminiKey, geminiKey);
    expect(c.state.input.mode, AiMode.saver);
    await c.close();
  });

  test('키 형식', () {
    expect(ProvisioningInput.geminiKeyPattern.hasMatch(geminiKey), isTrue);
    expect(ProvisioningInput.geminiKeyPattern.hasMatch('AIza-short'), isFalse);
    expect(ProvisioningInput.geminiKeyPattern.hasMatch(input.openAiKey), isFalse);
    expect(ProvisioningInput.keyPattern(AiProvider.openai).hasMatch(input.openAiKey), isTrue);
  });

  test('비밀번호가 틀리면 Wi-Fi 목록으로 돌아와 이유를 보인다', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info()));
    when(() => repo.scanWifi()).thenAnswer((_) async => const Right(<WifiNetwork>[]));
    when(() => repo.provisionWifi('HomeWiFi', 'bad')).thenAnswer((_) async => const Right(WifiProvStatus.authFailed));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(input, remember: true);
    await c.selectSpeaker(speaker);
    await c.connectWifi('HomeWiFi', 'bad');
    expect(c.state.step, ProvStep.wifiList);
    expect(c.state.wifiErrorKey, ErrorKeys.wifiAuth);
    expect(c.state.lastSsid, 'HomeWiFi');
    await c.close();
  });

  test('휴대폰 칸이 가득 차면 고른 휴대폰을 지우고 등록 (키는 다시 보내지 않음)', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(provisioned: true, wifi: true, key: true)));
    when(() => repo.pair(any())).thenAnswer((_) async => const Left(BleFailure(
          errorKey: ErrorKeys.blePhonesFull,
          code: BleCmdError.phonesFull,
          data: {
            'phones': [
              {'phone_id': 'old-1', 'name': '옛 폰'},
            ],
          },
        )));
    when(() => repo.pair(any(), evict: 'old-1')).thenAnswer((_) async => const Right(PairResult(token: 't2', phoneId: 'p1')));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(input, remember: true);
    await c.selectSpeaker(speaker);
    await c.keepWifi();
    expect(c.state.step, ProvStep.phonesFull);
    expect(c.state.phones, const [RegisteredPhone(phoneId: 'old-1', name: '옛 폰')]);
    await c.evictAndPair('old-1');
    expect(c.state.step, ProvStep.done);
    verify(() => repo.setSecret(SecretKey.openai, any())).called(1);
    verify(() => repo.save(found, 't2')).called(1);
    await c.close();
  });

  test('연결 실패 → failed, 다시 시도하면 같은 스피커로', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => const Left(BleFailure(errorKey: ErrorKeys.bleConnect)));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(input, remember: true);
    await c.selectSpeaker(speaker);
    expect(c.state.step, ProvStep.failed);
    expect(c.state.failure?.errorKey, ErrorKeys.bleConnect);
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(provisioned: true, wifi: true, key: true)));
    await c.retry();
    expect(c.state.step, ProvStep.wifiChoice);
    await c.close();
  });
}
