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

const input = ProvisioningInput(openAiKey: 'sk-proj-abcdefghijklmnopqrstuvwx', phoneName: "Mom's phone");
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

  test('init: fills in the remembered key and the default phone name', () async {
    when(() => vault.openAiKey()).thenAnswer((_) async => 'sk-saved');
    when(() => vault.telegramToken()).thenAnswer((_) async => '1:tg');
    final c = ProvisioningCubit(repo, vault);
    await c.init();
    expect(c.state.input, const ProvisioningInput(openAiKey: 'sk-saved', telegramToken: '1:tg', phoneName: 'Galaxy'));
  });

  test('new speaker: key → find → Wi-Fi → register → done, key remembered on the phone', () async {
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

  test('speaker already has Wi-Fi and key (adding a phone): keeps Wi-Fi, empty key is not sent', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(provisioned: true, wifi: true, key: true)));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(const ProvisioningInput(existingKey: true, phoneName: "Dad's phone"), remember: true);
    await c.selectSpeaker(speaker);
    expect(c.state.step, ProvStep.wifiChoice);
    await c.keepWifi();
    expect(c.state.step, ProvStep.done);
    expect(c.state.wifiChanged, isFalse);
    verifyNever(() => repo.setSecret(any(), any()));
    verify(() => repo.pair("Dad's phone")).called(1);
    await c.close();
  });

  test('does not look for a speaker without a key for the chosen AI or "already set"', () async {
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

  test('"already set" but the speaker lacks that AI key: disconnects and returns to step 1 (with a notice)', () async {
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

  test('"already set" and the speaker has that AI key: skips sending the key, still sends the chosen AI and mode', () async {
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

  test('a Gemini key is sent as gemini_key and both keys are remembered', () async {
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

  test('settings.set NO_API_KEY returns to step 1 (does not reach the done step)', () async {
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

  test('AI this speaker cannot run yet (Gemini on step-1 firmware): disconnects and returns to step 1 (not-ready notice)', () async {
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

  test('old firmware (no ai in device.info): openai.live only → sends real-time even if saver was chosen', () async {
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

  test('parsing device.info.ai', () {
    final i = DeviceInfo.fromJson({
      'ai': {
        'provider': 'openai',
        'mode': 'saver',
        'available': ['openai.live', 'openai.saver'],
      },
    });
    expect(i.ai, stage1);
  });

  test('init: picks Gemini first if only a Gemini key is remembered', () async {
    when(() => vault.geminiKey()).thenAnswer((_) async => geminiKey);
    final c = ProvisioningCubit(repo, vault);
    await c.init();
    expect(c.state.input.provider, AiProvider.gemini);
    expect(c.state.input.geminiKey, geminiKey);
    expect(c.state.input.mode, AiMode.saver);
    await c.close();
  });

  test('key format', () {
    expect(ProvisioningInput.geminiKeyPattern.hasMatch(geminiKey), isTrue);
    expect(ProvisioningInput.geminiKeyPattern.hasMatch('AIza-short'), isFalse);
    expect(ProvisioningInput.geminiKeyPattern.hasMatch(input.openAiKey), isFalse);
    expect(ProvisioningInput.keyPattern(AiProvider.openai).hasMatch(input.openAiKey), isTrue);
  });

  test('wrong password returns to the Wi-Fi list and shows the reason', () async {
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

  test('phone slots full: removes the chosen phone, then registers (key is not resent)', () async {
    when(() => repo.connect(speaker)).thenAnswer((_) async => Right(info(provisioned: true, wifi: true, key: true)));
    when(() => repo.pair(any())).thenAnswer((_) async => const Left(BleFailure(
          errorKey: ErrorKeys.blePhonesFull,
          code: BleCmdError.phonesFull,
          data: {
            'phones': [
              {'phone_id': 'old-1', 'name': 'Old phone'},
            ],
          },
        )));
    when(() => repo.pair(any(), evict: 'old-1')).thenAnswer((_) async => const Right(PairResult(token: 't2', phoneId: 'p1')));
    final c = ProvisioningCubit(repo, vault);
    await c.submitKeys(input, remember: true);
    await c.selectSpeaker(speaker);
    await c.keepWifi();
    expect(c.state.step, ProvStep.phonesFull);
    expect(c.state.phones, const [RegisteredPhone(phoneId: 'old-1', name: 'Old phone')]);
    await c.evictAndPair('old-1');
    expect(c.state.step, ProvStep.done);
    verify(() => repo.setSecret(SecretKey.openai, any())).called(1);
    verify(() => repo.save(found, 't2')).called(1);
    await c.close();
  });

  test('connection failure → failed, retry uses the same speaker', () async {
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
