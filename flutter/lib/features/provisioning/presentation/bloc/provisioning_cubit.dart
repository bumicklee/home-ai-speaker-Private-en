import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/ai/ai_choice.dart';
import '../../../../core/ble/ble_link.dart';
import '../../../../core/ble/ble_secret_writer.dart';
import '../../../../core/ble/wifi_scan.dart';
import '../../../../core/constants/api_paths.dart';
import '../../../../core/constants/ble_protocol.dart';
import '../../../../core/errors/error_keys.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/storage/key_vault.dart';
import '../../../devices/domain/entities/device.dart';
import '../../domain/entities/provisioning_input.dart';
import '../../domain/repositories/provisioning_repository.dart';

enum ProvStep {
  keys, // 1. AI, key, mode (if the speaker can't use the chosen AI, we come back here carrying missingKey or notReady)
  scanning, // 2. Find the speaker
  connecting,
  wifiChoice, // Speaker already has Wi-Fi: keep / change
  wifiScanning, // 3. Wi-Fi
  wifiList,
  wifiConnecting,
  sending, // Save the key, register the phone
  phonesFull, // Registration slots are full: choose a phone to remove
  discovering, // Find it on the LAN after the reboot
  done, // 4. Done
  failed,
}

class RegisteredPhone extends Equatable {
  const RegisteredPhone({required this.phoneId, required this.name});
  final String phoneId;
  final String name;
  @override
  List<Object?> get props => [phoneId, name];
}

class ProvisioningState extends Equatable {
  const ProvisioningState({
    this.step = ProvStep.keys,
    this.input = const ProvisioningInput(phoneName: ''),
    this.remember = true,
    this.speakers = const [],
    this.speaker,
    this.info,
    this.networks = const [],
    this.wifiErrorKey,
    this.lastSsid,
    this.phones = const [],
    this.failure,
    this.device,
    this.wifiChanged = false,
    this.done = const {},
    this.searching = false,
    this.missingKey,
    this.notReady,
  });

  final ProvStep step;
  final ProvisioningInput input;

  /// Remember keys on the phone (user request 2026-10-03)
  final bool remember;
  final List<DiscoveredSpeaker> speakers;
  final DiscoveredSpeaker? speaker;
  final DeviceInfo? info;
  final List<WifiNetwork> networks;

  /// Wi-Fi failure reason (ErrorKeys.wifi*)
  final String? wifiErrorKey;
  final String? lastSsid;
  final List<RegisteredPhone> phones;
  final Failure? failure;

  /// Device saved after completion (host null = not found on the LAN yet)
  final Device? device;
  final bool wifiChanged;

  /// Checklist on the done screen: wifi, key, pair, found
  final Set<String> done;

  /// Searching for the speaker (false when the 30-second scan ends)
  final bool searching;

  /// After connecting, the speaker had no key for the chosen AI, so we went back to step 1 (the screen explains)
  final AiProvider? missingKey;

  /// After connecting, this speaker (firmware) can't do the chosen AI yet (`device.info.ai.available`)
  final AiProvider? notReady;

  /// Step bar (1–4)
  int get stepNumber => switch (step) {
        ProvStep.keys => 1,
        ProvStep.scanning || ProvStep.connecting => 2,
        ProvStep.wifiChoice || ProvStep.wifiScanning || ProvStep.wifiList || ProvStep.wifiConnecting => 3,
        _ => 4,
      };

  ProvisioningState copyWith({
    ProvStep? step,
    ProvisioningInput? input,
    bool? remember,
    List<DiscoveredSpeaker>? speakers,
    DiscoveredSpeaker? Function()? speaker,
    DeviceInfo? Function()? info,
    List<WifiNetwork>? networks,
    String? Function()? wifiErrorKey,
    String? Function()? lastSsid,
    List<RegisteredPhone>? phones,
    Failure? Function()? failure,
    Device? Function()? device,
    bool? wifiChanged,
    Set<String>? done,
    bool? searching,
    AiProvider? Function()? missingKey,
    AiProvider? Function()? notReady,
  }) =>
      ProvisioningState(
        step: step ?? this.step,
        input: input ?? this.input,
        remember: remember ?? this.remember,
        speakers: speakers ?? this.speakers,
        speaker: speaker != null ? speaker() : this.speaker,
        info: info != null ? info() : this.info,
        networks: networks ?? this.networks,
        wifiErrorKey: wifiErrorKey != null ? wifiErrorKey() : this.wifiErrorKey,
        lastSsid: lastSsid != null ? lastSsid() : this.lastSsid,
        phones: phones ?? this.phones,
        failure: failure != null ? failure() : this.failure,
        device: device != null ? device() : this.device,
        wifiChanged: wifiChanged ?? this.wifiChanged,
        done: done ?? this.done,
        searching: searching ?? this.searching,
        missingKey: missingKey != null ? missingKey() : this.missingKey,
        notReady: notReady != null ? notReady() : this.notReady,
      );

  @override
  List<Object?> get props => [
        step,
        input,
        remember,
        speakers,
        speaker,
        info,
        networks,
        wifiErrorKey,
        lastSsid,
        phones,
        failure,
        device,
        wifiChanged,
        done,
        searching,
        missingKey,
        notReady,
      ];
}

/// First-time setup, adding a phone, re-registration (design document, Section 3.4)
class ProvisioningCubit extends Cubit<ProvisioningState> {
  ProvisioningCubit(this._repo, this._vault) : super(const ProvisioningState());

  final ProvisioningRepository _repo;
  final KeyVault _vault;
  StreamSubscription<List<DiscoveredSpeaker>>? _scan;

  /// Fill in the remembered keys and the default phone name
  Future<void> init() async {
    final openAi = await _vault.openAiKey() ?? '';
    final gemini = await _vault.geminiKey() ?? '';
    final tg = await _vault.telegramToken() ?? '';
    final phone = await _repo.defaultPhoneName();
    if (isClosed) return;
    emit(state.copyWith(
      input: ProvisioningInput(
        // If there is no OpenAI key but a Gemini key is remembered, pick Gemini first
        provider: openAi.isEmpty && gemini.isNotEmpty ? AiProvider.gemini : AiProvider.openai,
        openAiKey: openAi,
        geminiKey: gemini,
        telegramToken: tg,
        phoneName: phone,
      ),
    ));
  }

  /// End of step 1 → find speaker. Won't proceed (false) if there is no key for the chosen AI and "already has it" isn't set
  Future<bool> submitKeys(ProvisioningInput input, {required bool remember}) async {
    if (!input.canSearch) return false;
    if (remember) {
      if (input.openAiKey.isNotEmpty) await _vault.saveOpenAiKey(input.openAiKey);
      if (input.geminiKey.isNotEmpty) await _vault.saveGeminiKey(input.geminiKey);
      if (input.telegramToken.isNotEmpty) await _vault.saveTelegramToken(input.telegramToken);
    } else {
      await _vault.saveOpenAiKey(null);
      await _vault.saveGeminiKey(null);
      await _vault.saveTelegramToken(null);
    }
    emit(state.copyWith(input: input, remember: remember, missingKey: () => null, notReady: () => null));
    await scan();
    return true;
  }

  /// Find the speaker (30 seconds). If already searching, leave it alone — restarting hits Android's scan count limit
  Future<void> scan() async {
    if (_scan != null && state.step == ProvStep.scanning && state.searching) return;
    await _scan?.cancel();
    _scan = null;
    emit(state.copyWith(step: ProvStep.scanning, speakers: const [], searching: true, failure: () => null));
    final ready = await _repo.ensureReady();
    if (isClosed) return; // the screen closed while waiting
    if (_rightOrFail(ready) == null) return;
    _scan = _repo.scan().listen(
      (list) {
        if (!isClosed) emit(state.copyWith(speakers: list));
      },
      onError: (Object e) {
        if (!isClosed) _fail(const BleFailure(errorKey: ErrorKeys.bleProtocol));
      },
      onDone: () {
        _scan = null;
        if (!isClosed && state.step == ProvStep.scanning) emit(state.copyWith(searching: false));
      },
    );
  }

  Future<void> selectSpeaker(DiscoveredSpeaker speaker) async {
    await _scan?.cancel();
    _scan = null;
    emit(state.copyWith(step: ProvStep.connecting, speaker: () => speaker, failure: () => null));
    final info = _rightOrFail(await _repo.connect(speaker));
    if (info == null) return;
    emit(state.copyWith(info: () => info));
    final provider = state.input.provider;
    if (!info.ai.providerAvailable(provider)) {
      await _backToKeys(provider, notReady: true); // e.g., Gemini on stage-1 firmware
      return;
    }
    if (!info.ai.isAvailable(provider, state.input.mode)) {
      // If this speaker can't do the chosen mode yet, use one it can (it can be changed later in the assistant settings)
      final mode = AiMode.values.firstWhere((m) => info.ai.isAvailable(provider, m));
      emit(state.copyWith(input: state.input.copyWith(mode: mode)));
    }
    final onSpeaker = info.secrets[provider.secretKey] ?? false;
    if (!state.input.hasChosenKey && !onSpeaker) {
      await _backToKeys(provider); // back to step 1 to enter a key or pick another AI
    } else {
      await _decideWifi();
    }
  }

  /// The speaker has no key for the chosen AI, or ([notReady]) it can't do that AI yet: disconnect and go back to step 1 (design 11.3)
  Future<void> _backToKeys(AiProvider provider, {bool notReady = false}) async {
    await _repo.disconnect();
    emit(state.copyWith(
      step: ProvStep.keys,
      missingKey: () => notReady ? null : provider,
      notReady: () => notReady ? provider : null,
      input: state.input.copyWith(existingKey: false),
      speaker: () => null,
      info: () => null,
      done: const {},
    ));
  }

  Future<void> _decideWifi() async {
    final info = state.info;
    if (info != null && info.provisioned && info.wifiConnected) {
      emit(state.copyWith(step: ProvStep.wifiChoice));
    } else {
      await loadWifi();
    }
  }

  Future<void> keepWifi() => _complete();

  Future<void> loadWifi() async {
    emit(state.copyWith(step: ProvStep.wifiScanning, wifiErrorKey: () => null));
    final list = _rightOrFail(await _repo.scanWifi());
    if (list != null) emit(state.copyWith(step: ProvStep.wifiList, networks: list));
  }

  Future<void> connectWifi(String ssid, String password) async {
    emit(state.copyWith(step: ProvStep.wifiConnecting, lastSsid: () => ssid, wifiErrorKey: () => null));
    final status = _rightOrFail(await _repo.provisionWifi(ssid, password));
    if (status == null) return;
    if (status == WifiProvStatus.success) {
      emit(state.copyWith(wifiChanged: true, done: {...state.done, 'wifi'}));
      await _complete();
    } else {
      emit(state.copyWith(step: ProvStep.wifiList, wifiErrorKey: () => ErrorKeys.fromWifiStatus(status)));
    }
  }

  /// Save keys → register the phone → 0xFF88 → find it again on the LAN → save on the phone
  Future<void> _complete({String? evict}) async {
    emit(state.copyWith(step: ProvStep.sending));
    final input = state.input;
    if (evict == null) {
      if (input.openAiKey.isNotEmpty) {
        if (_rightOrFail(await _repo.setSecret(SecretKey.openai, input.openAiKey)) == null) return;
      }
      if (input.geminiKey.isNotEmpty) {
        if (_rightOrFail(await _repo.setSecret(SecretKey.gemini, input.geminiKey)) == null) return;
      }
      if (input.telegramToken.isNotEmpty) {
        if (_rightOrFail(await _repo.setSecret(SecretKey.telegramBot, input.telegramToken)) == null) return;
      }
      emit(state.copyWith(done: {...state.done, 'key'}));
    }
    final paired = await _repo.pair(input.phoneName, evict: evict);
    final pair = paired.fold<PairResult?>((f) {
      if (f is BleFailure && f.code == BleCmdError.phonesFull) {
        final phones = [
          for (final p in (f.data?['phones'] as List<dynamic>? ?? const []))
            RegisteredPhone(phoneId: p['phone_id'] as String, name: p['name'] as String? ?? ''),
        ];
        emit(state.copyWith(step: ProvStep.phonesFull, phones: phones));
      } else {
        _fail(f);
      }
      return null;
    }, (p) => p);
    if (pair == null) return;
    emit(state.copyWith(done: {...state.done, 'pair'}));

    // The chosen AI and mode (the speaker checks the key once more)
    final ai = await _repo.setSettings(SettingsGroup.assistant, {
      'ai_provider': input.provider.id,
      input.provider.modeSettingKey: input.mode.id,
    });
    final aiFailure = ai.fold<Failure?>((f) => f, (_) => null);
    if (aiFailure != null) {
      if (aiFailure.code == BleCmdError.noApiKey) {
        await _backToKeys(input.provider);
      } else {
        _fail(aiFailure);
      }
      return;
    }

    if (_rightOrFail(await _repo.finish()) == null) return;
    final mac = await _macOrFail();
    if (mac == null) return;
    await _repo.disconnect();

    emit(state.copyWith(step: ProvStep.discovering));
    final name = state.speaker?.name ?? '${BleProtocol.namePrefix}${mac.substring(mac.length - 6)}';
    // After the reboot (when Wi-Fi changed), joining Wi-Fi takes a few seconds. If it didn't change, search right away
    final device = await _repo.discover(mac, name);
    if (_rightOrFail(await _repo.save(device, pair.token)) == null) return;
    emit(state.copyWith(
      step: ProvStep.done,
      device: () => device,
      done: {...state.done, if (device.host != null) 'found'},
    ));
  }

  /// When the registration slots are full, pick a phone to remove
  Future<void> evictAndPair(String phoneId) => _complete(evict: phoneId);

  /// Retry from where it failed: before connecting, search again; after connecting, reconnect to the same speaker
  Future<void> retry() async {
    final speaker = state.speaker;
    if (speaker == null) return scan();
    await selectSpeaker(speaker);
  }

  Future<String?> _macOrFail() async {
    final info = state.info;
    if (info == null || info.mac.isEmpty) {
      _fail(const BleFailure(errorKey: ErrorKeys.bleProtocol));
      return null;
    }
    return info.mac.toUpperCase();
  }

  /// The success value; on failure, go to the failure screen and return null
  T? _rightOrFail<T>(Either<Failure, T> r) => r.fold((f) {
        _fail(f);
        return null;
      }, (v) => v);

  @override
  void emit(ProvisioningState state) {
    if (!isClosed) super.emit(state); // ignore BLE or network responses that arrive late after the screen has closed
  }

  void _fail(Failure f) {
    if (isClosed) return;
    emit(state.copyWith(step: ProvStep.failed, failure: () => f));
  }

  @override
  Future<void> close() async {
    await _scan?.cancel();
    await _repo.disconnect();
    return super.close();
  }
}
