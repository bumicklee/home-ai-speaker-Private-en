import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @aiModeTitle.
  ///
  /// In ko, this message translates to:
  /// **'AI · 대화 방식'**
  String get aiModeTitle;

  /// No description provided for @aiModeSaver.
  ///
  /// In ko, this message translates to:
  /// **'절약 모드'**
  String get aiModeSaver;

  /// No description provided for @aiModeLive.
  ///
  /// In ko, this message translates to:
  /// **'실시간'**
  String get aiModeLive;

  /// No description provided for @aiLabel.
  ///
  /// In ko, this message translates to:
  /// **'{provider} · {mode}'**
  String aiLabel(String provider, String mode);

  /// No description provided for @aiKeyLabel.
  ///
  /// In ko, this message translates to:
  /// **'{provider} API 키'**
  String aiKeyLabel(String provider);

  /// No description provided for @aiKeyInvalidGemini.
  ///
  /// In ko, this message translates to:
  /// **'Gemini 키는 AIza로 시작하고 영문·숫자·-·_만 들어가요 (끝에 :wq 같은 글자가 붙지 않았는지 확인해 주세요)'**
  String get aiKeyInvalidGemini;

  /// No description provided for @aiPriceShortOpenAiSaver.
  ///
  /// In ko, this message translates to:
  /// **'월 약 1.5만 원'**
  String get aiPriceShortOpenAiSaver;

  /// No description provided for @aiPriceShortOpenAiLive.
  ///
  /// In ko, this message translates to:
  /// **'월 약 12.6만 원'**
  String get aiPriceShortOpenAiLive;

  /// No description provided for @aiPriceShortGeminiSaver.
  ///
  /// In ko, this message translates to:
  /// **'월 약 1만 원'**
  String get aiPriceShortGeminiSaver;

  /// No description provided for @aiPriceShortGeminiLive.
  ///
  /// In ko, this message translates to:
  /// **'월 약 4만 원'**
  String get aiPriceShortGeminiLive;

  /// No description provided for @aiShortSaverNote.
  ///
  /// In ko, this message translates to:
  /// **'대답 1~2초 늦음'**
  String get aiShortSaverNote;

  /// No description provided for @aiShortLiveNote.
  ///
  /// In ko, this message translates to:
  /// **'끼어들기 됨'**
  String get aiShortLiveNote;

  /// No description provided for @aiPriceOpenAiSaver.
  ///
  /// In ko, this message translates to:
  /// **'월 약 15,000원'**
  String get aiPriceOpenAiSaver;

  /// No description provided for @aiPriceOpenAiLive.
  ///
  /// In ko, this message translates to:
  /// **'월 약 126,000원'**
  String get aiPriceOpenAiLive;

  /// No description provided for @aiPriceGeminiSaver.
  ///
  /// In ko, this message translates to:
  /// **'월 약 10,000원'**
  String get aiPriceGeminiSaver;

  /// No description provided for @aiPriceGeminiLive.
  ///
  /// In ko, this message translates to:
  /// **'월 약 40,000원'**
  String get aiPriceGeminiLive;

  /// No description provided for @aiDescOpenAiSaver.
  ///
  /// In ko, this message translates to:
  /// **'사람이 말한 만큼만 요금이 나가요. 대답이 1~2초 늦어요.'**
  String get aiDescOpenAiSaver;

  /// No description provided for @aiDescOpenAiLive.
  ///
  /// In ko, this message translates to:
  /// **'가장 자연스럽고 빨라요. 대화가 연결된 시간만큼 요금이 나가요(분당 약 70원).'**
  String get aiDescOpenAiLive;

  /// No description provided for @aiDescGeminiSaver.
  ///
  /// In ko, this message translates to:
  /// **'가장 저렴해요. 대답이 1~2초 늦어요.'**
  String get aiDescGeminiSaver;

  /// No description provided for @aiDescGeminiLive.
  ///
  /// In ko, this message translates to:
  /// **'Google Gemini 실시간 대화. OpenAI 실시간의 약 1/3 요금이에요.'**
  String get aiDescGeminiLive;

  /// No description provided for @aiTagInstant.
  ///
  /// In ko, this message translates to:
  /// **'대답 바로'**
  String get aiTagInstant;

  /// No description provided for @aiTagBargeIn.
  ///
  /// In ko, this message translates to:
  /// **'말하는 중 끼어들기 됨'**
  String get aiTagBargeIn;

  /// No description provided for @aiTagNoBargeIn.
  ///
  /// In ko, this message translates to:
  /// **'끼어들기 안 됨 · 가운데 버튼으로 멈춤'**
  String get aiTagNoBargeIn;

  /// No description provided for @aiTagOneEighth.
  ///
  /// In ko, this message translates to:
  /// **'약 1/8 요금'**
  String get aiTagOneEighth;

  /// No description provided for @aiTagCheapest.
  ///
  /// In ko, this message translates to:
  /// **'가장 저렴'**
  String get aiTagCheapest;

  /// No description provided for @aiPickProvider.
  ///
  /// In ko, this message translates to:
  /// **'① AI 고르기'**
  String get aiPickProvider;

  /// No description provided for @aiPickMode.
  ///
  /// In ko, this message translates to:
  /// **'② {provider} 대화 방식'**
  String aiPickMode(String provider);

  /// No description provided for @aiKeyPresent.
  ///
  /// In ko, this message translates to:
  /// **'키 있음'**
  String get aiKeyPresent;

  /// No description provided for @aiKeyMissing.
  ///
  /// In ko, this message translates to:
  /// **'키 없음 · 쓸 수 없어요'**
  String get aiKeyMissing;

  /// No description provided for @aiNotReady.
  ///
  /// In ko, this message translates to:
  /// **'준비 중'**
  String get aiNotReady;

  /// No description provided for @aiNotReadyHint.
  ///
  /// In ko, this message translates to:
  /// **'이 스피커에서는 아직 쓸 수 없어요. 스피커를 업데이트하면 열려요.'**
  String get aiNotReadyHint;

  /// No description provided for @aiAddKey.
  ///
  /// In ko, this message translates to:
  /// **'{provider} 키 넣기 (가운데 버튼 3초 → 블루투스로 보내요)'**
  String aiAddKey(String provider);

  /// No description provided for @aiInfoTitle.
  ///
  /// In ko, this message translates to:
  /// **'알아 두세요'**
  String get aiInfoTitle;

  /// No description provided for @aiInfoBody.
  ///
  /// In ko, this message translates to:
  /// **'한국어 수업은 발음을 실시간으로 들어야 해서 늘 실시간 API(OpenAI)로 해요. 요금은 하루 1시간 쓸 때 한 달 예상이에요. 바꾸면 다음 대화부터 적용돼요.'**
  String get aiInfoBody;

  /// No description provided for @aiNoKeyError.
  ///
  /// In ko, this message translates to:
  /// **'이 스피커에는 {provider} 키가 없어요. 먼저 키를 넣어 주세요.'**
  String aiNoKeyError(String provider);

  /// No description provided for @aiChanged.
  ///
  /// In ko, this message translates to:
  /// **'바꿨어요. 다음 대화부터 적용돼요'**
  String get aiChanged;

  /// No description provided for @aiKeySent.
  ///
  /// In ko, this message translates to:
  /// **'{provider} 키를 스피커에 넣었어요'**
  String aiKeySent(String provider);

  /// No description provided for @asstTitle.
  ///
  /// In ko, this message translates to:
  /// **'비서'**
  String get asstTitle;

  /// No description provided for @asstName.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get asstName;

  /// No description provided for @asstNameHint.
  ///
  /// In ko, this message translates to:
  /// **'호출어는 바뀌지 않아요'**
  String get asstNameHint;

  /// No description provided for @asstLanguage.
  ///
  /// In ko, this message translates to:
  /// **'말하는 언어'**
  String get asstLanguage;

  /// No description provided for @asstLanguageKo.
  ///
  /// In ko, this message translates to:
  /// **'한국어'**
  String get asstLanguageKo;

  /// No description provided for @asstLanguageEn.
  ///
  /// In ko, this message translates to:
  /// **'English'**
  String get asstLanguageEn;

  /// No description provided for @asstLanguageHint.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 대화할 때 쓰는 언어예요. 앱 언어는 시스템 화면에서 바꿔요.'**
  String get asstLanguageHint;

  /// No description provided for @asstVoice.
  ///
  /// In ko, this message translates to:
  /// **'목소리'**
  String get asstVoice;

  /// No description provided for @asstVoiceNextTime.
  ///
  /// In ko, this message translates to:
  /// **'다음 대화부터 바뀌어요'**
  String get asstVoiceNextTime;

  /// No description provided for @asstPurpose.
  ///
  /// In ko, this message translates to:
  /// **'하는 일'**
  String get asstPurpose;

  /// No description provided for @asstPurposeHint.
  ///
  /// In ko, this message translates to:
  /// **'비서의 역할이나 말투를 적어요'**
  String get asstPurposeHint;

  /// No description provided for @asstUnits.
  ///
  /// In ko, this message translates to:
  /// **'단위'**
  String get asstUnits;

  /// No description provided for @asstUnitsMetric.
  ///
  /// In ko, this message translates to:
  /// **'미터법 (°C·km)'**
  String get asstUnitsMetric;

  /// No description provided for @asstUnitsImperial.
  ///
  /// In ko, this message translates to:
  /// **'야드파운드법 (°F·mi)'**
  String get asstUnitsImperial;

  /// No description provided for @asstPlace.
  ///
  /// In ko, this message translates to:
  /// **'사는 곳'**
  String get asstPlace;

  /// No description provided for @asstPlaceBody.
  ///
  /// In ko, this message translates to:
  /// **'날씨·근처 검색에 써요. 스피커에는 동네 이름만 저장하고 좌표는 보내지 않아요.'**
  String get asstPlaceBody;

  /// No description provided for @asstPlaceField.
  ///
  /// In ko, this message translates to:
  /// **'동네'**
  String get asstPlaceField;

  /// No description provided for @asstPlaceExample.
  ///
  /// In ko, this message translates to:
  /// **'예: 서울 강남구 역삼동'**
  String get asstPlaceExample;

  /// No description provided for @asstUseCurrentLocation.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치로'**
  String get asstUseCurrentLocation;

  /// No description provided for @asstTimezone.
  ///
  /// In ko, this message translates to:
  /// **'시간대'**
  String get asstTimezone;

  /// No description provided for @asstLocationFilled.
  ///
  /// In ko, this message translates to:
  /// **'동네와 시간대를 넣었어요. 저장을 눌러 주세요'**
  String get asstLocationFilled;

  /// No description provided for @asstLocationFilledOnlyPlace.
  ///
  /// In ko, this message translates to:
  /// **'동네를 넣었어요. 시간대를 골라 주세요'**
  String get asstLocationFilledOnlyPlace;

  /// No description provided for @asstTimezoneUnsupported.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 시간대({tz})는 스피커가 몰라요. 가까운 시간대를 골라 주세요.'**
  String asstTimezoneUnsupported(String tz);

  /// No description provided for @asstTimezoneUnknown.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 시간대를 읽지 못했어요. 가까운 시간대를 골라 주세요.'**
  String get asstTimezoneUnknown;

  /// No description provided for @asstTimezoneMore.
  ///
  /// In ko, this message translates to:
  /// **'다른 시간대'**
  String get asstTimezoneMore;

  /// No description provided for @asstLocationServiceOff.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 위치 기능이 꺼져 있어요'**
  String get asstLocationServiceOff;

  /// No description provided for @asstLocationDenied.
  ///
  /// In ko, this message translates to:
  /// **'위치 권한이 없어요. 동네를 직접 적어 주세요'**
  String get asstLocationDenied;

  /// No description provided for @asstLocationDeniedForever.
  ///
  /// In ko, this message translates to:
  /// **'위치 권한이 꺼져 있어요. 설정에서 켜거나 직접 적어 주세요'**
  String get asstLocationDeniedForever;

  /// No description provided for @asstOpenSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정 열기'**
  String get asstOpenSettings;

  /// No description provided for @asstLocationUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'위치를 찾지 못했어요. 직접 적어 주세요'**
  String get asstLocationUnavailable;

  /// No description provided for @asstWebSearch.
  ///
  /// In ko, this message translates to:
  /// **'웹 검색 (날씨·뉴스)'**
  String get asstWebSearch;

  /// No description provided for @asstDeviceControls.
  ///
  /// In ko, this message translates to:
  /// **'기기 조작 (볼륨·라디오·기억)'**
  String get asstDeviceControls;

  /// No description provided for @asstAutoMemory.
  ///
  /// In ko, this message translates to:
  /// **'대화 중 알게 된 것 자동 기억'**
  String get asstAutoMemory;

  /// No description provided for @asstMemories.
  ///
  /// In ko, this message translates to:
  /// **'기억 목록'**
  String get asstMemories;

  /// No description provided for @asstMemoryCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}개'**
  String asstMemoryCount(int count);

  /// No description provided for @asstSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get asstSave;

  /// No description provided for @asstSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장했어요'**
  String get asstSaved;

  /// No description provided for @asstDiscardTitle.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 않고 나갈까요?'**
  String get asstDiscardTitle;

  /// No description provided for @asstDiscardBody.
  ///
  /// In ko, this message translates to:
  /// **'고친 내용은 사라져요.'**
  String get asstDiscardBody;

  /// No description provided for @asstDiscard.
  ///
  /// In ko, this message translates to:
  /// **'나가기'**
  String get asstDiscard;

  /// No description provided for @asstNameEmpty.
  ///
  /// In ko, this message translates to:
  /// **'이름을 적어 주세요'**
  String get asstNameEmpty;

  /// No description provided for @asstTooLong.
  ///
  /// In ko, this message translates to:
  /// **'너무 길어요 (최대 {max}바이트)'**
  String asstTooLong(int max);

  /// No description provided for @asstBytes.
  ///
  /// In ko, this message translates to:
  /// **'{used}/{max}바이트'**
  String asstBytes(int used, int max);

  /// No description provided for @asstMemoriesNotice.
  ///
  /// In ko, this message translates to:
  /// **'비서가 기억한 내용이에요. 지우면 다음 대화부터 잊어요.'**
  String get asstMemoriesNotice;

  /// No description provided for @asstMemoriesEmpty.
  ///
  /// In ko, this message translates to:
  /// **'기억한 것이 없어요'**
  String get asstMemoriesEmpty;

  /// No description provided for @asstForget.
  ///
  /// In ko, this message translates to:
  /// **'지우기'**
  String get asstForget;

  /// No description provided for @asstForgetTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 기억을 지울까요?'**
  String get asstForgetTitle;

  /// No description provided for @asstForgotten.
  ///
  /// In ko, this message translates to:
  /// **'지웠어요'**
  String get asstForgotten;

  /// No description provided for @audioTitle.
  ///
  /// In ko, this message translates to:
  /// **'오디오·호출어'**
  String get audioTitle;

  /// No description provided for @audioWakeEnabled.
  ///
  /// In ko, this message translates to:
  /// **'호출어로 부르기'**
  String get audioWakeEnabled;

  /// No description provided for @audioWakeEnabledHint.
  ///
  /// In ko, this message translates to:
  /// **'끄면 가운데 버튼으로만 대화해요 (TV 볼 때)'**
  String get audioWakeEnabledHint;

  /// No description provided for @audioPhrase.
  ///
  /// In ko, this message translates to:
  /// **'호출어'**
  String get audioPhrase;

  /// No description provided for @audioPhraseComputer.
  ///
  /// In ko, this message translates to:
  /// **'컴퓨터'**
  String get audioPhraseComputer;

  /// No description provided for @audioPhraseAlexa.
  ///
  /// In ko, this message translates to:
  /// **'알렉사'**
  String get audioPhraseAlexa;

  /// No description provided for @audioSensitivity.
  ///
  /// In ko, this message translates to:
  /// **'감도'**
  String get audioSensitivity;

  /// No description provided for @audioSensitivityLow.
  ///
  /// In ko, this message translates to:
  /// **'오인식 적음'**
  String get audioSensitivityLow;

  /// No description provided for @audioSensitivityHigh.
  ///
  /// In ko, this message translates to:
  /// **'잘 알아들음'**
  String get audioSensitivityHigh;

  /// No description provided for @audioAdvanced.
  ///
  /// In ko, this message translates to:
  /// **'고급'**
  String get audioAdvanced;

  /// No description provided for @audioWakeGain.
  ///
  /// In ko, this message translates to:
  /// **'호출어 입력 키우기'**
  String get audioWakeGain;

  /// No description provided for @audioWakeGainHint.
  ///
  /// In ko, this message translates to:
  /// **'멀리서 잘 못 알아들을 때만 올려요'**
  String get audioWakeGainHint;

  /// No description provided for @audioWakeGainValue.
  ///
  /// In ko, this message translates to:
  /// **'+{db} dB'**
  String audioWakeGainValue(int db);

  /// No description provided for @audioWakeTest.
  ///
  /// In ko, this message translates to:
  /// **'감지 테스트 (60초)'**
  String get audioWakeTest;

  /// No description provided for @audioWakeTestRunning.
  ///
  /// In ko, this message translates to:
  /// **'테스트 중 · {seconds}초 남음'**
  String audioWakeTestRunning(int seconds);

  /// No description provided for @audioWakeTestHint.
  ///
  /// In ko, this message translates to:
  /// **'‘{phrase}’라고 몇 번 불러 보세요'**
  String audioWakeTestHint(String phrase);

  /// No description provided for @audioWakeTestCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}번 감지했어요'**
  String audioWakeTestCount(int count);

  /// No description provided for @audioWakeTestDone.
  ///
  /// In ko, this message translates to:
  /// **'60초 동안 {count}번 감지했어요'**
  String audioWakeTestDone(int count);

  /// No description provided for @audioVolume.
  ///
  /// In ko, this message translates to:
  /// **'볼륨'**
  String get audioVolume;

  /// No description provided for @audioVolumeValue.
  ///
  /// In ko, this message translates to:
  /// **'{value} / {max}'**
  String audioVolumeValue(int value, int max);

  /// No description provided for @audioDuck.
  ///
  /// In ko, this message translates to:
  /// **'대화할 때 음악 줄이기'**
  String get audioDuck;

  /// No description provided for @audioDb.
  ///
  /// In ko, this message translates to:
  /// **'{db} dB'**
  String audioDb(int db);

  /// No description provided for @audioMicGain.
  ///
  /// In ko, this message translates to:
  /// **'마이크 감도'**
  String get audioMicGain;

  /// No description provided for @audioMicGainHint.
  ///
  /// In ko, this message translates to:
  /// **'높을수록 작은 소리도 들어요'**
  String get audioMicGainHint;

  /// No description provided for @audioAutoGain.
  ///
  /// In ko, this message translates to:
  /// **'마이크 자동 조절'**
  String get audioAutoGain;

  /// No description provided for @audioAutoGainHint.
  ///
  /// In ko, this message translates to:
  /// **'말소리 크기에 맞춰 조금씩 조절해요'**
  String get audioAutoGainHint;

  /// No description provided for @audioTestTone.
  ///
  /// In ko, this message translates to:
  /// **'스피커 테스트음'**
  String get audioTestTone;

  /// No description provided for @audioLed.
  ///
  /// In ko, this message translates to:
  /// **'LED 밝기'**
  String get audioLed;

  /// No description provided for @audioPercent.
  ///
  /// In ko, this message translates to:
  /// **'{value}%'**
  String audioPercent(int value);

  /// No description provided for @appTitle.
  ///
  /// In ko, this message translates to:
  /// **'AI-PA'**
  String get appTitle;

  /// No description provided for @splashLoading.
  ///
  /// In ko, this message translates to:
  /// **'스피커 정보를 불러오는 중…'**
  String get splashLoading;

  /// No description provided for @settingsTheme.
  ///
  /// In ko, this message translates to:
  /// **'화면 모드'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In ko, this message translates to:
  /// **'밝게'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In ko, this message translates to:
  /// **'어둡게'**
  String get settingsThemeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In ko, this message translates to:
  /// **'언어'**
  String get settingsLanguage;

  /// No description provided for @commonRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get commonCancel;

  /// No description provided for @commonOk.
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get commonOk;

  /// No description provided for @bleKey2Hint.
  ///
  /// In ko, this message translates to:
  /// **'스피커 가운데 버튼(Key2)을 3초 누르세요'**
  String get bleKey2Hint;

  /// No description provided for @errorUnknown.
  ///
  /// In ko, this message translates to:
  /// **'알 수 없는 오류가 났어요'**
  String get errorUnknown;

  /// No description provided for @errorNetwork.
  ///
  /// In ko, this message translates to:
  /// **'네트워크에 연결할 수 없어요'**
  String get errorNetwork;

  /// No description provided for @errorCache.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰에 저장된 정보를 읽지 못했어요'**
  String get errorCache;

  /// No description provided for @errorDeviceUnreachable.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 연결할 수 없어요. 휴대폰과 스피커가 같은 Wi-Fi인지 확인하세요'**
  String get errorDeviceUnreachable;

  /// No description provided for @errorDeviceUnauthorized.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰의 등록이 해지됐어요. 다시 등록하세요'**
  String get errorDeviceUnauthorized;

  /// No description provided for @errorDeviceRateLimited.
  ///
  /// In ko, this message translates to:
  /// **'잠시 뒤에 다시 시도하세요'**
  String get errorDeviceRateLimited;

  /// No description provided for @errorDeviceTimeout.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 응답하지 않아요'**
  String get errorDeviceTimeout;

  /// No description provided for @errorDeviceInvalidArg.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 값을 받아들이지 않았어요'**
  String get errorDeviceInvalidArg;

  /// No description provided for @errorDeviceBusy.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 다른 작업 중이에요'**
  String get errorDeviceBusy;

  /// No description provided for @errorDeviceStorage.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 저장하지 못했어요'**
  String get errorDeviceStorage;

  /// No description provided for @errorDeviceNoApiKey.
  ///
  /// In ko, this message translates to:
  /// **'OpenAI 키가 아직 없어요'**
  String get errorDeviceNoApiKey;

  /// No description provided for @errorDeviceNoWifi.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 Wi-Fi에 연결돼 있지 않아요'**
  String get errorDeviceNoWifi;

  /// No description provided for @errorDeviceVoiceActive.
  ///
  /// In ko, this message translates to:
  /// **'대화 중에는 할 수 없어요'**
  String get errorDeviceVoiceActive;

  /// No description provided for @errorDeviceNotFound.
  ///
  /// In ko, this message translates to:
  /// **'찾는 항목이 없어요'**
  String get errorDeviceNotFound;

  /// No description provided for @errorDeviceOtaTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'펌웨어 파일이 너무 커요'**
  String get errorDeviceOtaTooLarge;

  /// No description provided for @errorDeviceOtaSignature.
  ///
  /// In ko, this message translates to:
  /// **'서명이 맞지 않는 펌웨어예요'**
  String get errorDeviceOtaSignature;

  /// No description provided for @errorBleAdapterOff.
  ///
  /// In ko, this message translates to:
  /// **'Bluetooth를 켜 주세요'**
  String get errorBleAdapterOff;

  /// No description provided for @errorBlePermission.
  ///
  /// In ko, this message translates to:
  /// **'Bluetooth 권한이 필요해요'**
  String get errorBlePermission;

  /// No description provided for @errorBleNotFound.
  ///
  /// In ko, this message translates to:
  /// **'스피커를 찾지 못했어요. Key2를 3초 눌렀는지 확인하세요'**
  String get errorBleNotFound;

  /// No description provided for @errorBleConnect.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 Bluetooth로 연결하지 못했어요'**
  String get errorBleConnect;

  /// No description provided for @errorBleDisconnected.
  ///
  /// In ko, this message translates to:
  /// **'Bluetooth 연결이 끊겼어요'**
  String get errorBleDisconnected;

  /// No description provided for @errorBleBondFailed.
  ///
  /// In ko, this message translates to:
  /// **'연결 보안 오류예요. 휴대폰 설정 > Bluetooth에서 JARVIS 기기를 지운 뒤 다시 시도하세요'**
  String get errorBleBondFailed;

  /// No description provided for @errorBleProtocol.
  ///
  /// In ko, this message translates to:
  /// **'스피커와 통신하는 중 오류가 났어요'**
  String get errorBleProtocol;

  /// No description provided for @errorBleTimeout.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 Bluetooth로 응답하지 않아요'**
  String get errorBleTimeout;

  /// No description provided for @errorBleWindowClosed.
  ///
  /// In ko, this message translates to:
  /// **'설정 시간이 끝났어요. Key2를 3초 눌러 다시 여세요'**
  String get errorBleWindowClosed;

  /// No description provided for @errorBlePhonesFull.
  ///
  /// In ko, this message translates to:
  /// **'등록할 수 있는 휴대폰 수가 가득 찼어요'**
  String get errorBlePhonesFull;

  /// No description provided for @errorBleUnsupportedVersion.
  ///
  /// In ko, this message translates to:
  /// **'앱을 최신 버전으로 업데이트하세요'**
  String get errorBleUnsupportedVersion;

  /// No description provided for @errorWifiAuth.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 비밀번호가 틀렸어요'**
  String get errorWifiAuth;

  /// No description provided for @errorWifiNotFound.
  ///
  /// In ko, this message translates to:
  /// **'이 Wi-Fi를 찾지 못했어요'**
  String get errorWifiNotFound;

  /// No description provided for @errorWifiTimeout.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 연결 시간이 초과됐어요'**
  String get errorWifiTimeout;

  /// No description provided for @errorDeviceNotPlaying.
  ///
  /// In ko, this message translates to:
  /// **'재생 중인 것이 없어요'**
  String get errorDeviceNotPlaying;

  /// No description provided for @errorDeviceNoTelegramToken.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 텔레그램 봇 토큰이 아직 없어요'**
  String get errorDeviceNoTelegramToken;

  /// No description provided for @errorDeviceNotesFull.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 메모·일정이 가득 찼어요(1,000개). 지난 일정이나 필요 없는 메모를 지워 주세요'**
  String get errorDeviceNotesFull;

  /// No description provided for @errorDeviceConflict.
  ///
  /// In ko, this message translates to:
  /// **'스피커에서 방금 바뀌었어요. 바뀐 내용을 보고 다시 고쳐 주세요'**
  String get errorDeviceConflict;

  /// No description provided for @engTitle.
  ///
  /// In ko, this message translates to:
  /// **'한국어 선생님'**
  String get engTitle;

  /// No description provided for @engHomeSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'발음 · 기초 · 생활 · 비즈니스 · 고급'**
  String get engHomeSubtitle;

  /// No description provided for @engIntro.
  ///
  /// In ko, this message translates to:
  /// **'코스를 고르고 시작하면 바로 스피커와 한국어로 프리토킹해요. 틀린 표현과 발음은 선생님이 대화하면서 고쳐 줘요.'**
  String get engIntro;

  /// No description provided for @engCoursePron.
  ///
  /// In ko, this message translates to:
  /// **'발음 교정'**
  String get engCoursePron;

  /// No description provided for @engCoursePronDesc.
  ///
  /// In ko, this message translates to:
  /// **'편하게 이야기하면서 틀린 발음을 그때그때 짚어 줘요'**
  String get engCoursePronDesc;

  /// No description provided for @engCourseBasic.
  ///
  /// In ko, this message translates to:
  /// **'기초 한국어 회화'**
  String get engCourseBasic;

  /// No description provided for @engCourseBasicDesc.
  ///
  /// In ko, this message translates to:
  /// **'쉬운 일상 이야기를 천천히. 막히면 영어로 도와줘요'**
  String get engCourseBasicDesc;

  /// No description provided for @engCourseDaily.
  ///
  /// In ko, this message translates to:
  /// **'생활 한국어 회화'**
  String get engCourseDaily;

  /// No description provided for @engCourseDailyDesc.
  ///
  /// In ko, this message translates to:
  /// **'여행·식당·병원 같은 상황으로 자연스럽게 대화'**
  String get engCourseDailyDesc;

  /// No description provided for @engCourseBiz.
  ///
  /// In ko, this message translates to:
  /// **'비즈니스 한국어 회화'**
  String get engCourseBiz;

  /// No description provided for @engCourseBizDesc.
  ///
  /// In ko, this message translates to:
  /// **'회의·전화·협상 이야기를 존댓말로 정중하게'**
  String get engCourseBizDesc;

  /// No description provided for @engCourseAdv.
  ///
  /// In ko, this message translates to:
  /// **'고급 한국어 회화'**
  String get engCourseAdv;

  /// No description provided for @engCourseAdvDesc.
  ///
  /// In ko, this message translates to:
  /// **'시사·의견 토론을 한국어로만. 더 자연스럽게 다듬어 줘요'**
  String get engCourseAdvDesc;

  /// No description provided for @engLevelAll.
  ///
  /// In ko, this message translates to:
  /// **'모든 수준'**
  String get engLevelAll;

  /// No description provided for @engLevelBeginner.
  ///
  /// In ko, this message translates to:
  /// **'입문'**
  String get engLevelBeginner;

  /// No description provided for @engLevelEasy.
  ///
  /// In ko, this message translates to:
  /// **'초·중급'**
  String get engLevelEasy;

  /// No description provided for @engLevelMid.
  ///
  /// In ko, this message translates to:
  /// **'중급'**
  String get engLevelMid;

  /// No description provided for @engLevelAdvanced.
  ///
  /// In ko, this message translates to:
  /// **'고급'**
  String get engLevelAdvanced;

  /// No description provided for @engExplain.
  ///
  /// In ko, this message translates to:
  /// **'설명 말'**
  String get engExplain;

  /// No description provided for @engExplainKorean.
  ///
  /// In ko, this message translates to:
  /// **'한국어만'**
  String get engExplainKorean;

  /// No description provided for @engExplainEnglish.
  ///
  /// In ko, this message translates to:
  /// **'영어 섞기'**
  String get engExplainEnglish;

  /// No description provided for @engSpeed.
  ///
  /// In ko, this message translates to:
  /// **'말 빠르기'**
  String get engSpeed;

  /// No description provided for @engSpeedSlow.
  ///
  /// In ko, this message translates to:
  /// **'천천히'**
  String get engSpeedSlow;

  /// No description provided for @engSpeedNormal.
  ///
  /// In ko, this message translates to:
  /// **'보통'**
  String get engSpeedNormal;

  /// No description provided for @engLength.
  ///
  /// In ko, this message translates to:
  /// **'수업 시간'**
  String get engLength;

  /// No description provided for @engMinutes.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분'**
  String engMinutes(int minutes);

  /// No description provided for @engStart.
  ///
  /// In ko, this message translates to:
  /// **'{course} 프리토킹 시작'**
  String engStart(String course);

  /// No description provided for @engVoiceHint.
  ///
  /// In ko, this message translates to:
  /// **'말로도 시작해요: “알렉사, 한국어 공부하자”'**
  String get engVoiceHint;

  /// No description provided for @engCostNote.
  ///
  /// In ko, this message translates to:
  /// **'수업은 최대 5분이에요. 수업 시간만큼 OpenAI 음성 대화 요금이 나와요.'**
  String get engCostNote;

  /// No description provided for @engLessonTitle.
  ///
  /// In ko, this message translates to:
  /// **'프리토킹'**
  String get engLessonTitle;

  /// No description provided for @engFreeTalk.
  ///
  /// In ko, this message translates to:
  /// **'{course} · 프리토킹'**
  String engFreeTalk(String course);

  /// No description provided for @engRemaining.
  ///
  /// In ko, this message translates to:
  /// **'{time} 남음'**
  String engRemaining(String time);

  /// No description provided for @engStarting.
  ///
  /// In ko, this message translates to:
  /// **'수업을 여는 중…'**
  String get engStarting;

  /// No description provided for @engListening.
  ///
  /// In ko, this message translates to:
  /// **'듣고 있어요'**
  String get engListening;

  /// No description provided for @engListeningBody.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 대고 편하게 한국어로 말하세요. 틀려도 괜찮아요, 선생님이 대화하면서 고쳐 줘요.'**
  String get engListeningBody;

  /// No description provided for @engTopic.
  ///
  /// In ko, this message translates to:
  /// **'지금 이야기'**
  String get engTopic;

  /// No description provided for @engTopicUnknown.
  ///
  /// In ko, this message translates to:
  /// **'선생님이 주제를 정하는 중'**
  String get engTopicUnknown;

  /// No description provided for @engChangeTopic.
  ///
  /// In ko, this message translates to:
  /// **'주제 바꾸기'**
  String get engChangeTopic;

  /// No description provided for @engCorrections.
  ///
  /// In ko, this message translates to:
  /// **'선생님이 고쳐 준 표현'**
  String get engCorrections;

  /// No description provided for @engCorrectionsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'고친 표현이 생기면 여기에 나와요 (약 45초마다)'**
  String get engCorrectionsEmpty;

  /// No description provided for @engPronunciationBadge.
  ///
  /// In ko, this message translates to:
  /// **'발음'**
  String get engPronunciationBadge;

  /// No description provided for @engEnd.
  ///
  /// In ko, this message translates to:
  /// **'수업 끝내기'**
  String get engEnd;

  /// No description provided for @engSummarizing.
  ///
  /// In ko, this message translates to:
  /// **'오늘 수업을 정리하는 중…'**
  String get engSummarizing;

  /// No description provided for @engDoneTitle.
  ///
  /// In ko, this message translates to:
  /// **'수업을 마쳤어요'**
  String get engDoneTitle;

  /// No description provided for @engDoneMeta.
  ///
  /// In ko, this message translates to:
  /// **'{course} 프리토킹 · {minutes}분'**
  String engDoneMeta(String course, int minutes);

  /// No description provided for @engTodayCorrections.
  ///
  /// In ko, this message translates to:
  /// **'오늘 고친 표현'**
  String get engTodayCorrections;

  /// No description provided for @engNoCorrections.
  ///
  /// In ko, this message translates to:
  /// **'오늘은 고친 표현이 없어요. 잘했어요!'**
  String get engNoCorrections;

  /// No description provided for @engPractice.
  ///
  /// In ko, this message translates to:
  /// **'발음 더 연습할 단어'**
  String get engPractice;

  /// No description provided for @engNextTopic.
  ///
  /// In ko, this message translates to:
  /// **'다음에 이야기해 볼 주제'**
  String get engNextTopic;

  /// No description provided for @engAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 프리토킹'**
  String get engAgain;

  /// No description provided for @engHome.
  ///
  /// In ko, this message translates to:
  /// **'홈으로'**
  String get engHome;

  /// No description provided for @engLastLesson.
  ///
  /// In ko, this message translates to:
  /// **'지난 수업 정리 보기'**
  String get engLastLesson;

  /// No description provided for @engRealtimeNote.
  ///
  /// In ko, this message translates to:
  /// **'한국어 수업은 실시간 API(OpenAI)로 해요 · 분당 약 70원'**
  String get engRealtimeNote;

  /// No description provided for @engNeedOpenAiKey.
  ///
  /// In ko, this message translates to:
  /// **'한국어 수업은 OpenAI 키가 필요해요. 비서 > AI · 대화 방식에서 OpenAI 키를 넣어 주세요.'**
  String get engNeedOpenAiKey;

  /// No description provided for @homeTitle.
  ///
  /// In ko, this message translates to:
  /// **'스피커'**
  String get homeTitle;

  /// No description provided for @homeAddSpeaker.
  ///
  /// In ko, this message translates to:
  /// **'스피커 추가'**
  String get homeAddSpeaker;

  /// No description provided for @homeSelectSpeaker.
  ///
  /// In ko, this message translates to:
  /// **'스피커 선택'**
  String get homeSelectSpeaker;

  /// No description provided for @homeConnected.
  ///
  /// In ko, this message translates to:
  /// **'연결됨'**
  String get homeConnected;

  /// No description provided for @homeWifiGood.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 신호 좋음'**
  String get homeWifiGood;

  /// No description provided for @homeWifiFair.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 신호 보통'**
  String get homeWifiFair;

  /// No description provided for @homeWifiWeak.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 신호 약함'**
  String get homeWifiWeak;

  /// No description provided for @homeIdleTitle.
  ///
  /// In ko, this message translates to:
  /// **'듣고 있어요'**
  String get homeIdleTitle;

  /// No description provided for @homeIdleBody.
  ///
  /// In ko, this message translates to:
  /// **'“알렉사”라고 부르거나 아래 버튼을 누르세요'**
  String get homeIdleBody;

  /// No description provided for @homeTalkingTitle.
  ///
  /// In ko, this message translates to:
  /// **'대화 중'**
  String get homeTalkingTitle;

  /// No description provided for @homeTalkingBody.
  ///
  /// In ko, this message translates to:
  /// **'말이 끝나면 60초 뒤 자동으로 끝나요'**
  String get homeTalkingBody;

  /// No description provided for @homeConnectingTitle.
  ///
  /// In ko, this message translates to:
  /// **'연결 중…'**
  String get homeConnectingTitle;

  /// No description provided for @homeStartTalk.
  ///
  /// In ko, this message translates to:
  /// **'대화 시작'**
  String get homeStartTalk;

  /// No description provided for @homeStopTalk.
  ///
  /// In ko, this message translates to:
  /// **'대화 끝내기'**
  String get homeStopTalk;

  /// No description provided for @homeNothingPlaying.
  ///
  /// In ko, this message translates to:
  /// **'재생 중인 것이 없어요'**
  String get homeNothingPlaying;

  /// No description provided for @homeOpenRadio.
  ///
  /// In ko, this message translates to:
  /// **'라디오 열기'**
  String get homeOpenRadio;

  /// No description provided for @homeRadioPlaying.
  ///
  /// In ko, this message translates to:
  /// **'라디오 · 재생 중'**
  String get homeRadioPlaying;

  /// No description provided for @homeRadioPaused.
  ///
  /// In ko, this message translates to:
  /// **'라디오 · 일시정지'**
  String get homeRadioPaused;

  /// No description provided for @homeRadioBuffering.
  ///
  /// In ko, this message translates to:
  /// **'라디오 · 연결 중'**
  String get homeRadioBuffering;

  /// No description provided for @homeVolume.
  ///
  /// In ko, this message translates to:
  /// **'볼륨'**
  String get homeVolume;

  /// No description provided for @homePrevious.
  ///
  /// In ko, this message translates to:
  /// **'이전 방송'**
  String get homePrevious;

  /// No description provided for @homeNext.
  ///
  /// In ko, this message translates to:
  /// **'다음 방송'**
  String get homeNext;

  /// No description provided for @homePause.
  ///
  /// In ko, this message translates to:
  /// **'일시정지'**
  String get homePause;

  /// No description provided for @homeResume.
  ///
  /// In ko, this message translates to:
  /// **'재생'**
  String get homeResume;

  /// No description provided for @homeStop.
  ///
  /// In ko, this message translates to:
  /// **'정지'**
  String get homeStop;

  /// No description provided for @homeTelegram.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램'**
  String get homeTelegram;

  /// No description provided for @homeTelegramUnread.
  ///
  /// In ko, this message translates to:
  /// **'새 메시지 {count}'**
  String homeTelegramUnread(int count);

  /// No description provided for @homeTelegramSetup.
  ///
  /// In ko, this message translates to:
  /// **'연결하기'**
  String get homeTelegramSetup;

  /// No description provided for @homeMenuRadio.
  ///
  /// In ko, this message translates to:
  /// **'라디오'**
  String get homeMenuRadio;

  /// No description provided for @homeMenuAssistant.
  ///
  /// In ko, this message translates to:
  /// **'비서'**
  String get homeMenuAssistant;

  /// No description provided for @homeMenuAudio.
  ///
  /// In ko, this message translates to:
  /// **'오디오·호출'**
  String get homeMenuAudio;

  /// No description provided for @homeMenuSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get homeMenuSystem;

  /// No description provided for @homeUnreachableTitle.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 연결할 수 없어요'**
  String get homeUnreachableTitle;

  /// No description provided for @homeUnreachableBody.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰과 스피커가 같은 Wi-Fi에 있는지 확인하세요.'**
  String get homeUnreachableBody;

  /// No description provided for @homeFindAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 찾기'**
  String get homeFindAgain;

  /// No description provided for @homeUnauthorizedTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰의 등록이 해지됐어요'**
  String get homeUnauthorizedTitle;

  /// No description provided for @homeUnauthorizedBody.
  ///
  /// In ko, this message translates to:
  /// **'스피커 가운데 버튼을 3초 누른 뒤 다시 등록하세요.'**
  String get homeUnauthorizedBody;

  /// No description provided for @homeRegisterAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 등록'**
  String get homeRegisterAgain;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'등록된 스피커가 없어요'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyBody.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰과 스피커를 가까이 두고 시작하세요. 처음 켠 스피커는 바로 보여요.'**
  String get homeEmptyBody;

  /// No description provided for @homeComingSoon.
  ///
  /// In ko, this message translates to:
  /// **'이 화면은 준비 중이에요'**
  String get homeComingSoon;

  /// No description provided for @homeRemoveFromPhone.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰에서 지우기'**
  String get homeRemoveFromPhone;

  /// No description provided for @notesTitle.
  ///
  /// In ko, this message translates to:
  /// **'메모·일정'**
  String get notesTitle;

  /// No description provided for @notesHomeToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘 {count}개 · {next}'**
  String notesHomeToday(int count, String next);

  /// No description provided for @notesHomeTodayCount.
  ///
  /// In ko, this message translates to:
  /// **'오늘 일정 {count}개'**
  String notesHomeTodayCount(int count);

  /// No description provided for @notesHomeEmpty.
  ///
  /// In ko, this message translates to:
  /// **'메모·일정 보기'**
  String get notesHomeEmpty;

  /// No description provided for @notesClockHour.
  ///
  /// In ko, this message translates to:
  /// **'{hour}시'**
  String notesClockHour(int hour);

  /// No description provided for @notesClockHourMinute.
  ///
  /// In ko, this message translates to:
  /// **'{hour}시 {minute}분'**
  String notesClockHourMinute(int hour, String minute);

  /// No description provided for @notesSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'메모·일정 찾기'**
  String get notesSearchHint;

  /// No description provided for @notesTabEvents.
  ///
  /// In ko, this message translates to:
  /// **'일정'**
  String get notesTabEvents;

  /// No description provided for @notesTabMemos.
  ///
  /// In ko, this message translates to:
  /// **'메모'**
  String get notesTabMemos;

  /// No description provided for @notesTabTrash.
  ///
  /// In ko, this message translates to:
  /// **'휴지통'**
  String get notesTabTrash;

  /// No description provided for @notesGroupToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘 · {date}'**
  String notesGroupToday(String date);

  /// No description provided for @notesGroupTomorrow.
  ///
  /// In ko, this message translates to:
  /// **'내일 · {date}'**
  String notesGroupTomorrow(String date);

  /// No description provided for @notesGroupThisWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get notesGroupThisWeek;

  /// No description provided for @notesGroupLater.
  ///
  /// In ko, this message translates to:
  /// **'나중'**
  String get notesGroupLater;

  /// No description provided for @notesGroupPast.
  ///
  /// In ko, this message translates to:
  /// **'지난 일정'**
  String get notesGroupPast;

  /// No description provided for @notesAllDay.
  ///
  /// In ko, this message translates to:
  /// **'하루 종일'**
  String get notesAllDay;

  /// No description provided for @notesBadgeScheduled.
  ///
  /// In ko, this message translates to:
  /// **'알림 예정'**
  String get notesBadgeScheduled;

  /// No description provided for @notesBadgeSent.
  ///
  /// In ko, this message translates to:
  /// **'보냄'**
  String get notesBadgeSent;

  /// No description provided for @notesBadgeAcked.
  ///
  /// In ko, this message translates to:
  /// **'확인됨'**
  String get notesBadgeAcked;

  /// No description provided for @notesBadgeNoAnswer.
  ///
  /// In ko, this message translates to:
  /// **'대답 없음'**
  String get notesBadgeNoAnswer;

  /// No description provided for @notesBadgeMissed.
  ///
  /// In ko, this message translates to:
  /// **'놓침'**
  String get notesBadgeMissed;

  /// No description provided for @notesRemindLabel.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get notesRemindLabel;

  /// No description provided for @notesRemindNone.
  ///
  /// In ko, this message translates to:
  /// **'알림 없음'**
  String get notesRemindNone;

  /// No description provided for @notesRemindOnTime.
  ///
  /// In ko, this message translates to:
  /// **'정각'**
  String get notesRemindOnTime;

  /// No description provided for @notesRemindSameDay.
  ///
  /// In ko, this message translates to:
  /// **'당일 {time}'**
  String notesRemindSameDay(String time);

  /// No description provided for @notesRemindMinutes.
  ///
  /// In ko, this message translates to:
  /// **'{n}분 전'**
  String notesRemindMinutes(int n);

  /// No description provided for @notesRemindHours.
  ///
  /// In ko, this message translates to:
  /// **'{n}시간 전'**
  String notesRemindHours(int n);

  /// No description provided for @notesRemindHoursMinutes.
  ///
  /// In ko, this message translates to:
  /// **'{h}시간 {m}분 전'**
  String notesRemindHoursMinutes(int h, int m);

  /// No description provided for @notesRemindDayBefore.
  ///
  /// In ko, this message translates to:
  /// **'하루 전'**
  String get notesRemindDayBefore;

  /// No description provided for @notesRemindDays.
  ///
  /// In ko, this message translates to:
  /// **'{n}일 전'**
  String notesRemindDays(int n);

  /// No description provided for @notesRemindCustom.
  ///
  /// In ko, this message translates to:
  /// **'직접 입력'**
  String get notesRemindCustom;

  /// No description provided for @notesRemindHintMany.
  ///
  /// In ko, this message translates to:
  /// **'여러 개 고를 수 있어요'**
  String get notesRemindHintMany;

  /// No description provided for @notesRemindHintMax.
  ///
  /// In ko, this message translates to:
  /// **'최대 3개'**
  String get notesRemindHintMax;

  /// No description provided for @notesRemindSummary.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 {when}에 말로 알려 줘요'**
  String notesRemindSummary(String when);

  /// No description provided for @notesRemindOff.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정에서 일정 알림이 꺼져 있어요'**
  String get notesRemindOff;

  /// No description provided for @notesCustomTitle.
  ///
  /// In ko, this message translates to:
  /// **'몇 분 전에 알릴까요?'**
  String get notesCustomTitle;

  /// No description provided for @notesCustomHelp.
  ///
  /// In ko, this message translates to:
  /// **'1분부터 7일(10080분)까지'**
  String get notesCustomHelp;

  /// No description provided for @notesCustomUnit.
  ///
  /// In ko, this message translates to:
  /// **'분 전'**
  String get notesCustomUnit;

  /// No description provided for @notesCustomAdd.
  ///
  /// In ko, this message translates to:
  /// **'넣기'**
  String get notesCustomAdd;

  /// No description provided for @notesMemoToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get notesMemoToday;

  /// No description provided for @notesMemoYesterday.
  ///
  /// In ko, this message translates to:
  /// **'어제'**
  String get notesMemoYesterday;

  /// No description provided for @notesTrashInfo.
  ///
  /// In ko, this message translates to:
  /// **'말로 지운 메모·일정은 30일 동안 여기 있어요.'**
  String get notesTrashInfo;

  /// No description provided for @notesTrashLeft.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 뒤 완전히 지워져요'**
  String notesTrashLeft(int days);

  /// No description provided for @notesRestore.
  ///
  /// In ko, this message translates to:
  /// **'되살리기'**
  String get notesRestore;

  /// No description provided for @notesDeleteForever.
  ///
  /// In ko, this message translates to:
  /// **'영구 삭제'**
  String get notesDeleteForever;

  /// No description provided for @notesVoiceHint.
  ///
  /// In ko, this message translates to:
  /// **'말로도 돼요: “알렉사, 내일 3시 병원 일정 넣고 1시간 전에 알려 줘” · “알렉사, 우유 사라고 메모해 줘” · “알렉사, 내일 일정 알려 줘”'**
  String get notesVoiceHint;

  /// No description provided for @notesPrivacy.
  ///
  /// In ko, this message translates to:
  /// **'말로 찾거나 알려 줄 때는 메모 내용이 OpenAI 대화로 전해져요. 저장은 스피커와 휴대폰에만 해요.'**
  String get notesPrivacy;

  /// No description provided for @notesNew.
  ///
  /// In ko, this message translates to:
  /// **'새로 만들기'**
  String get notesNew;

  /// No description provided for @notesOffline.
  ///
  /// In ko, this message translates to:
  /// **'집 Wi-Fi에서 고칠 수 있어요'**
  String get notesOffline;

  /// No description provided for @notesOfflineBody.
  ///
  /// In ko, this message translates to:
  /// **'지금은 휴대폰에 저장된 내용만 보여요.'**
  String get notesOfflineBody;

  /// No description provided for @notesEmptyEvents.
  ///
  /// In ko, this message translates to:
  /// **'일정이 없어요'**
  String get notesEmptyEvents;

  /// No description provided for @notesEmptyMemos.
  ///
  /// In ko, this message translates to:
  /// **'메모가 없어요'**
  String get notesEmptyMemos;

  /// No description provided for @notesEmptyTrash.
  ///
  /// In ko, this message translates to:
  /// **'휴지통이 비어 있어요'**
  String get notesEmptyTrash;

  /// No description provided for @notesNoMatch.
  ///
  /// In ko, this message translates to:
  /// **'찾는 내용이 없어요'**
  String get notesNoMatch;

  /// No description provided for @notesEditEvent.
  ///
  /// In ko, this message translates to:
  /// **'일정 편집'**
  String get notesEditEvent;

  /// No description provided for @notesEditMemo.
  ///
  /// In ko, this message translates to:
  /// **'메모 편집'**
  String get notesEditMemo;

  /// No description provided for @notesNewEvent.
  ///
  /// In ko, this message translates to:
  /// **'새 일정'**
  String get notesNewEvent;

  /// No description provided for @notesNewMemo.
  ///
  /// In ko, this message translates to:
  /// **'새 메모'**
  String get notesNewMemo;

  /// No description provided for @notesFieldTitle.
  ///
  /// In ko, this message translates to:
  /// **'제목'**
  String get notesFieldTitle;

  /// No description provided for @notesFieldBody.
  ///
  /// In ko, this message translates to:
  /// **'내용'**
  String get notesFieldBody;

  /// No description provided for @notesTitleRequired.
  ///
  /// In ko, this message translates to:
  /// **'제목을 적어 주세요'**
  String get notesTitleRequired;

  /// No description provided for @notesEditHint.
  ///
  /// In ko, this message translates to:
  /// **'말로 넣은 일정도 여기서 고칠 수 있어요. 고치면 스피커에 바로 반영돼요.'**
  String get notesEditHint;

  /// No description provided for @notesSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get notesSave;

  /// No description provided for @notesDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get notesDelete;

  /// No description provided for @notesDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'“{title}” 지울까요?'**
  String notesDeleteTitle(String title);

  /// No description provided for @notesDeleteBody.
  ///
  /// In ko, this message translates to:
  /// **'스피커에서도 지워지고 되살릴 수 없어요. 다른 가족 휴대폰에서도 사라져요.'**
  String get notesDeleteBody;

  /// No description provided for @notesDeleteAction.
  ///
  /// In ko, this message translates to:
  /// **'지우기'**
  String get notesDeleteAction;

  /// No description provided for @notesSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장했어요'**
  String get notesSaved;

  /// No description provided for @notesDeleted.
  ///
  /// In ko, this message translates to:
  /// **'지웠어요'**
  String get notesDeleted;

  /// No description provided for @notesRestored.
  ///
  /// In ko, this message translates to:
  /// **'되살렸어요'**
  String get notesRestored;

  /// No description provided for @notesSettingsTitle.
  ///
  /// In ko, this message translates to:
  /// **'일정 알림'**
  String get notesSettingsTitle;

  /// No description provided for @notesSettingsEnabled.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 일정 알려 주기'**
  String get notesSettingsEnabled;

  /// No description provided for @notesSettingsEnabledSub.
  ///
  /// In ko, this message translates to:
  /// **'밤·새벽에도 정한 시각에 알려요'**
  String get notesSettingsEnabledSub;

  /// No description provided for @notesSettingsDefaults.
  ///
  /// In ko, this message translates to:
  /// **'기본 알림 · 따로 정하지 않은 일정에 써요'**
  String get notesSettingsDefaults;

  /// No description provided for @notesSettingsTimed.
  ///
  /// In ko, this message translates to:
  /// **'시각이 있는 일정'**
  String get notesSettingsTimed;

  /// No description provided for @notesSettingsAllDay.
  ///
  /// In ko, this message translates to:
  /// **'하루 종일 일정'**
  String get notesSettingsAllDay;

  /// No description provided for @notesSettingsSameMorning.
  ///
  /// In ko, this message translates to:
  /// **'당일 아침'**
  String get notesSettingsSameMorning;

  /// No description provided for @notesSettingsDayBeforeMorning.
  ///
  /// In ko, this message translates to:
  /// **'하루 전 아침'**
  String get notesSettingsDayBeforeMorning;

  /// No description provided for @notesSettingsAllDayTime.
  ///
  /// In ko, this message translates to:
  /// **'알림 시각'**
  String get notesSettingsAllDayTime;

  /// No description provided for @notesSettingsInfoTitle.
  ///
  /// In ko, this message translates to:
  /// **'알아 두세요'**
  String get notesSettingsInfoTitle;

  /// No description provided for @notesSettingsInfo.
  ///
  /// In ko, this message translates to:
  /// **'알림은 스피커가 짧게 대화를 열어 말로 알려 줘요. 알림 한 번마다 OpenAI 요금이 조금 들어요. 인터넷이 끊겼을 때는 알림음과 주황 불로 알려요.'**
  String get notesSettingsInfo;

  /// No description provided for @provTitle.
  ///
  /// In ko, this message translates to:
  /// **'스피커 설정'**
  String get provTitle;

  /// No description provided for @provKeysTitle.
  ///
  /// In ko, this message translates to:
  /// **'어떤 AI를 쓸까요?'**
  String get provKeysTitle;

  /// No description provided for @provKeysBody.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 연결하기 전에 정해요. 키를 복사하러 다른 앱에 다녀와도 괜찮아요.'**
  String get provKeysBody;

  /// No description provided for @provOpenAiKey.
  ///
  /// In ko, this message translates to:
  /// **'OpenAI API 키'**
  String get provOpenAiKey;

  /// No description provided for @provOpenAiKeyInvalid.
  ///
  /// In ko, this message translates to:
  /// **'sk- 로 시작하는 키를 넣어 주세요'**
  String get provOpenAiKeyInvalid;

  /// No description provided for @provTelegramToken.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램 봇 토큰'**
  String get provTelegramToken;

  /// No description provided for @provOptional.
  ///
  /// In ko, this message translates to:
  /// **'(선택)'**
  String get provOptional;

  /// No description provided for @provTelegramTokenHint.
  ///
  /// In ko, this message translates to:
  /// **'나중에 텔레그램 화면에서 넣어도 돼요.'**
  String get provTelegramTokenHint;

  /// No description provided for @provTelegramTokenInvalid.
  ///
  /// In ko, this message translates to:
  /// **'123456789:ABC… 형식의 토큰이 아니에요'**
  String get provTelegramTokenInvalid;

  /// No description provided for @provPhoneName.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰 이름'**
  String get provPhoneName;

  /// No description provided for @provRemember.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰에 키 기억하기'**
  String get provRemember;

  /// No description provided for @provRememberHint.
  ///
  /// In ko, this message translates to:
  /// **'다음 설정 때 자동으로 채워요. 휴대폰의 보안 저장소에 암호화해 둬요.'**
  String get provRememberHint;

  /// No description provided for @provPaste.
  ///
  /// In ko, this message translates to:
  /// **'붙여넣기'**
  String get provPaste;

  /// No description provided for @provFindSpeaker.
  ///
  /// In ko, this message translates to:
  /// **'스피커 찾기'**
  String get provFindSpeaker;

  /// No description provided for @provScanTitle.
  ///
  /// In ko, this message translates to:
  /// **'근처 스피커를 찾고 있어요'**
  String get provScanTitle;

  /// No description provided for @provScanHint.
  ///
  /// In ko, this message translates to:
  /// **'새 스피커는 켜면 바로 보여요. 이미 설정한 스피커는 가운데 버튼(Key2)을 3초 누르세요.'**
  String get provScanHint;

  /// No description provided for @provScanFound.
  ///
  /// In ko, this message translates to:
  /// **'찾은 스피커 {count}대'**
  String provScanFound(int count);

  /// No description provided for @provScanNone.
  ///
  /// In ko, this message translates to:
  /// **'아직 찾은 스피커가 없어요'**
  String get provScanNone;

  /// No description provided for @provScanAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 찾기'**
  String get provScanAgain;

  /// No description provided for @provSignalNear.
  ///
  /// In ko, this message translates to:
  /// **'아주 가까움'**
  String get provSignalNear;

  /// No description provided for @provSignalFar.
  ///
  /// In ko, this message translates to:
  /// **'멀리 있음'**
  String get provSignalFar;

  /// No description provided for @provConnecting.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 연결하는 중…'**
  String get provConnecting;

  /// No description provided for @provWifiChoiceTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 스피커는 이미 Wi-Fi에 연결돼 있어요'**
  String get provWifiChoiceTitle;

  /// No description provided for @provWifiChoiceBody.
  ///
  /// In ko, this message translates to:
  /// **'그대로 두면 다시 시작하지 않고 바로 등록해요.'**
  String get provWifiChoiceBody;

  /// No description provided for @provWifiKeep.
  ///
  /// In ko, this message translates to:
  /// **'지금 Wi-Fi 그대로'**
  String get provWifiKeep;

  /// No description provided for @provWifiChange.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 바꾸기'**
  String get provWifiChange;

  /// No description provided for @provWifiTitle.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 쓸 Wi-Fi를 고르세요'**
  String get provWifiTitle;

  /// No description provided for @provWifiScanning.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 주변 Wi-Fi를 찾는 중…'**
  String get provWifiScanning;

  /// No description provided for @provWifiNote.
  ///
  /// In ko, this message translates to:
  /// **'스피커는 2.4GHz Wi-Fi만 연결할 수 있어요. 목록은 스피커가 직접 찾은 것이에요.'**
  String get provWifiNote;

  /// No description provided for @provWifiOpen.
  ///
  /// In ko, this message translates to:
  /// **'개방'**
  String get provWifiOpen;

  /// No description provided for @provWifiManual.
  ///
  /// In ko, this message translates to:
  /// **'목록에 없는 Wi-Fi 직접 입력'**
  String get provWifiManual;

  /// No description provided for @provWifiName.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 이름'**
  String get provWifiName;

  /// No description provided for @provWifiPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호'**
  String get provWifiPassword;

  /// No description provided for @provWifiPasswordTitle.
  ///
  /// In ko, this message translates to:
  /// **'{ssid} 비밀번호'**
  String provWifiPasswordTitle(String ssid);

  /// No description provided for @provWifiShowPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 보기'**
  String get provWifiShowPassword;

  /// No description provided for @provWifiConnect.
  ///
  /// In ko, this message translates to:
  /// **'연결'**
  String get provWifiConnect;

  /// No description provided for @provWifiConnecting.
  ///
  /// In ko, this message translates to:
  /// **'{ssid}에 연결하는 중… (최대 20초)'**
  String provWifiConnecting(String ssid);

  /// No description provided for @provWifiRescan.
  ///
  /// In ko, this message translates to:
  /// **'다시 찾기'**
  String get provWifiRescan;

  /// No description provided for @provSending.
  ///
  /// In ko, this message translates to:
  /// **'키를 저장하고 이 휴대폰을 등록하는 중…'**
  String get provSending;

  /// No description provided for @provPhonesFullTitle.
  ///
  /// In ko, this message translates to:
  /// **'등록할 수 있는 휴대폰이 가득 찼어요'**
  String get provPhonesFullTitle;

  /// No description provided for @provPhonesFullBody.
  ///
  /// In ko, this message translates to:
  /// **'지울 휴대폰을 하나 고르면 그 자리에 이 휴대폰을 등록해요.'**
  String get provPhonesFullBody;

  /// No description provided for @provPhonesFullAction.
  ///
  /// In ko, this message translates to:
  /// **'지우고 이 휴대폰 등록'**
  String get provPhonesFullAction;

  /// No description provided for @provDiscovering.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 다시 시작하는 중이에요. 같은 Wi-Fi에서 찾고 있어요…'**
  String get provDiscovering;

  /// No description provided for @provDoneTitle.
  ///
  /// In ko, this message translates to:
  /// **'설정이 끝났어요'**
  String get provDoneTitle;

  /// No description provided for @provDoneBody.
  ///
  /// In ko, this message translates to:
  /// **'“AI 스피커가 준비되었습니다” 안내가 나오면 “알렉사”라고 불러 보세요.'**
  String get provDoneBody;

  /// No description provided for @provDoneWifi.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 연결'**
  String get provDoneWifi;

  /// No description provided for @provDoneKey.
  ///
  /// In ko, this message translates to:
  /// **'키 저장'**
  String get provDoneKey;

  /// No description provided for @provDonePair.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰 등록'**
  String get provDonePair;

  /// No description provided for @provDoneFound.
  ///
  /// In ko, this message translates to:
  /// **'같은 Wi-Fi에서 스피커 찾음 ({host})'**
  String provDoneFound(String host);

  /// No description provided for @provDoneNotFound.
  ///
  /// In ko, this message translates to:
  /// **'아직 같은 Wi-Fi에서 찾지 못했어요. 홈에서 다시 찾을 수 있어요.'**
  String get provDoneNotFound;

  /// No description provided for @provGoHome.
  ///
  /// In ko, this message translates to:
  /// **'홈으로'**
  String get provGoHome;

  /// No description provided for @provFailedTitle.
  ///
  /// In ko, this message translates to:
  /// **'설정을 마치지 못했어요'**
  String get provFailedTitle;

  /// No description provided for @provCancel.
  ///
  /// In ko, this message translates to:
  /// **'그만두기'**
  String get provCancel;

  /// No description provided for @provAiSection.
  ///
  /// In ko, this message translates to:
  /// **'① AI'**
  String get provAiSection;

  /// No description provided for @provRequired.
  ///
  /// In ko, this message translates to:
  /// **'(필수)'**
  String get provRequired;

  /// No description provided for @provKeyTyped.
  ///
  /// In ko, this message translates to:
  /// **'키가 들어갔어요. 스피커에는 블루투스로만 보내요.'**
  String get provKeyTyped;

  /// No description provided for @provKeyExistingHint.
  ///
  /// In ko, this message translates to:
  /// **'연결한 뒤 스피커에 이 키가 있는지 확인해요. 없으면 이 AI는 고를 수 없어요.'**
  String get provKeyExistingHint;

  /// No description provided for @provKeyRequiredHint.
  ///
  /// In ko, this message translates to:
  /// **'이 AI를 쓰려면 키가 꼭 있어야 해요.'**
  String get provKeyRequiredHint;

  /// No description provided for @provExistingKey.
  ///
  /// In ko, this message translates to:
  /// **'이미 이 AI 키가 저장된 스피커예요 (휴대폰 추가 등록)'**
  String get provExistingKey;

  /// No description provided for @provModeSection.
  ///
  /// In ko, this message translates to:
  /// **'② 대화 방식'**
  String get provModeSection;

  /// No description provided for @provModeLater.
  ///
  /// In ko, this message translates to:
  /// **'(나중에 비서 설정에서 바꿀 수 있어요)'**
  String get provModeLater;

  /// No description provided for @provMore.
  ///
  /// In ko, this message translates to:
  /// **'더 넣기 (선택): {other} 키 · 텔레그램 토큰'**
  String provMore(String other);

  /// No description provided for @provMoreOtherHint.
  ///
  /// In ko, this message translates to:
  /// **'{other} 키를 함께 넣으면 나중에 AI를 바로 바꿀 수 있어요.'**
  String provMoreOtherHint(String other);

  /// No description provided for @provKeyBlocked.
  ///
  /// In ko, this message translates to:
  /// **'{key}를 넣어야 다음으로 갈 수 있어요'**
  String provKeyBlocked(String key);

  /// No description provided for @provMissingKey.
  ///
  /// In ko, this message translates to:
  /// **'이 스피커에는 {provider} 키가 없어요. 키를 넣거나 다른 AI를 고르세요.'**
  String provMissingKey(String provider);

  /// No description provided for @provMaybeNotReady.
  ///
  /// In ko, this message translates to:
  /// **'(스피커에 따라 준비 중일 수 있어요)'**
  String get provMaybeNotReady;

  /// No description provided for @provNotReady.
  ///
  /// In ko, this message translates to:
  /// **'이 스피커는 아직 {provider}를 쓸 수 없어요(준비 중). 다른 AI를 고르거나 스피커를 업데이트한 뒤 다시 해 주세요.'**
  String provNotReady(String provider);

  /// No description provided for @radioTitle.
  ///
  /// In ko, this message translates to:
  /// **'라디오'**
  String get radioTitle;

  /// No description provided for @radioSearch.
  ///
  /// In ko, this message translates to:
  /// **'방송 찾기'**
  String get radioSearch;

  /// No description provided for @radioEdit.
  ///
  /// In ko, this message translates to:
  /// **'편집'**
  String get radioEdit;

  /// No description provided for @radioPlaying.
  ///
  /// In ko, this message translates to:
  /// **'재생 중'**
  String get radioPlaying;

  /// No description provided for @radioPaused.
  ///
  /// In ko, this message translates to:
  /// **'일시정지'**
  String get radioPaused;

  /// No description provided for @radioBuffering.
  ///
  /// In ko, this message translates to:
  /// **'연결 중'**
  String get radioBuffering;

  /// No description provided for @radioNothingPlaying.
  ///
  /// In ko, this message translates to:
  /// **'재생 중인 것이 없어요'**
  String get radioNothingPlaying;

  /// No description provided for @radioPickStation.
  ///
  /// In ko, this message translates to:
  /// **'아래에서 방송을 골라 주세요'**
  String get radioPickStation;

  /// No description provided for @radioPlay.
  ///
  /// In ko, this message translates to:
  /// **'재생'**
  String get radioPlay;

  /// No description provided for @radioPause.
  ///
  /// In ko, this message translates to:
  /// **'일시정지'**
  String get radioPause;

  /// No description provided for @radioResume.
  ///
  /// In ko, this message translates to:
  /// **'다시 재생'**
  String get radioResume;

  /// No description provided for @radioStop.
  ///
  /// In ko, this message translates to:
  /// **'정지'**
  String get radioStop;

  /// No description provided for @radioPrevious.
  ///
  /// In ko, this message translates to:
  /// **'이전 방송'**
  String get radioPrevious;

  /// No description provided for @radioNext.
  ///
  /// In ko, this message translates to:
  /// **'다음 방송'**
  String get radioNext;

  /// No description provided for @radioGroupMusic.
  ///
  /// In ko, this message translates to:
  /// **'음악'**
  String get radioGroupMusic;

  /// No description provided for @radioGroupKorean.
  ///
  /// In ko, this message translates to:
  /// **'한국 음악'**
  String get radioGroupKorean;

  /// No description provided for @radioGroupNews.
  ///
  /// In ko, this message translates to:
  /// **'뉴스·경제'**
  String get radioGroupNews;

  /// No description provided for @radioGroupTalk.
  ///
  /// In ko, this message translates to:
  /// **'토크'**
  String get radioGroupTalk;

  /// No description provided for @radioGroupOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get radioGroupOther;

  /// No description provided for @radioEmpty.
  ///
  /// In ko, this message translates to:
  /// **'저장된 방송이 없어요. 방송 찾기로 추가해 보세요'**
  String get radioEmpty;

  /// No description provided for @radioNotPlaying.
  ///
  /// In ko, this message translates to:
  /// **'지금 재생 중인 방송이 없어요'**
  String get radioNotPlaying;

  /// No description provided for @radioEditTitle.
  ///
  /// In ko, this message translates to:
  /// **'방송 편집'**
  String get radioEditTitle;

  /// No description provided for @radioEditHint.
  ///
  /// In ko, this message translates to:
  /// **'끌어서 순서를 바꿔요. 저장해야 스피커에 반영돼요'**
  String get radioEditHint;

  /// No description provided for @radioCount.
  ///
  /// In ko, this message translates to:
  /// **'{count} / {max}개'**
  String radioCount(int count, int max);

  /// No description provided for @radioSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get radioSave;

  /// No description provided for @radioSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장했어요'**
  String get radioSaved;

  /// No description provided for @radioAddCustom.
  ///
  /// In ko, this message translates to:
  /// **'주소로 직접 추가'**
  String get radioAddCustom;

  /// No description provided for @radioRename.
  ///
  /// In ko, this message translates to:
  /// **'이름 바꾸기'**
  String get radioRename;

  /// No description provided for @radioDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get radioDelete;

  /// No description provided for @radioDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name} 방송을 지울까요?'**
  String radioDeleteTitle(String name);

  /// No description provided for @radioDiscardTitle.
  ///
  /// In ko, this message translates to:
  /// **'바꾼 내용을 버릴까요?'**
  String get radioDiscardTitle;

  /// No description provided for @radioDiscard.
  ///
  /// In ko, this message translates to:
  /// **'버리기'**
  String get radioDiscard;

  /// No description provided for @radioFormName.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get radioFormName;

  /// No description provided for @radioFormUrl.
  ///
  /// In ko, this message translates to:
  /// **'방송 주소'**
  String get radioFormUrl;

  /// No description provided for @radioFormUrlHint.
  ///
  /// In ko, this message translates to:
  /// **'http:// 또는 https://로 시작하는 MP3·AAC 스트림'**
  String get radioFormUrlHint;

  /// No description provided for @radioFormGenre.
  ///
  /// In ko, this message translates to:
  /// **'장르 태그'**
  String get radioFormGenre;

  /// No description provided for @radioFormGenreHint.
  ///
  /// In ko, this message translates to:
  /// **'쉼표로 구분해요 (예: kpop,korean)'**
  String get radioFormGenreHint;

  /// No description provided for @radioFormAdd.
  ///
  /// In ko, this message translates to:
  /// **'추가'**
  String get radioFormAdd;

  /// No description provided for @radioErrTooMany.
  ///
  /// In ko, this message translates to:
  /// **'방송은 {max}개까지 저장할 수 있어요'**
  String radioErrTooMany(int max);

  /// No description provided for @radioErrNameEmpty.
  ///
  /// In ko, this message translates to:
  /// **'이름을 입력해 주세요'**
  String get radioErrNameEmpty;

  /// No description provided for @radioErrNameTooLong.
  ///
  /// In ko, this message translates to:
  /// **'이름이 너무 길어요 (한글 16자, 영문 48자까지)'**
  String get radioErrNameTooLong;

  /// No description provided for @radioErrUrlInvalid.
  ///
  /// In ko, this message translates to:
  /// **'http:// 또는 https://로 시작하는 주소만 쓸 수 있어요'**
  String get radioErrUrlInvalid;

  /// No description provided for @radioErrUrlTooLong.
  ///
  /// In ko, this message translates to:
  /// **'주소가 너무 길어요 (256자까지)'**
  String get radioErrUrlTooLong;

  /// No description provided for @radioErrGenreTooLong.
  ///
  /// In ko, this message translates to:
  /// **'장르 태그가 너무 길어요 (64자까지)'**
  String get radioErrGenreTooLong;

  /// No description provided for @radioErrTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'목록이 너무 커요. 이름이나 주소를 줄여 주세요'**
  String get radioErrTooLarge;

  /// No description provided for @radioErrDuplicate.
  ///
  /// In ko, this message translates to:
  /// **'이미 저장된 방송이에요'**
  String get radioErrDuplicate;

  /// No description provided for @radioSearchTitle.
  ///
  /// In ko, this message translates to:
  /// **'방송 찾기'**
  String get radioSearchTitle;

  /// No description provided for @radioSearchByName.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get radioSearchByName;

  /// No description provided for @radioSearchByTag.
  ///
  /// In ko, this message translates to:
  /// **'장르'**
  String get radioSearchByTag;

  /// No description provided for @radioSearchNameHint.
  ///
  /// In ko, this message translates to:
  /// **'방송 이름 (예: BBC, jazz)'**
  String get radioSearchNameHint;

  /// No description provided for @radioSearchTagHint.
  ///
  /// In ko, this message translates to:
  /// **'장르 태그 (예: jazz, kpop, news)'**
  String get radioSearchTagHint;

  /// No description provided for @radioSearchHlsNote.
  ///
  /// In ko, this message translates to:
  /// **'KBS·MBC·SBS 같은 한국 방송사는 HLS 방식이라 스피커가 틀 수 없어 목록에 나오지 않아요'**
  String get radioSearchHlsNote;

  /// No description provided for @radioSearchIdle.
  ///
  /// In ko, this message translates to:
  /// **'이름이나 장르로 찾아 보세요. 스피커가 틀 수 있는 방송만 보여요'**
  String get radioSearchIdle;

  /// No description provided for @radioSearchNoResults.
  ///
  /// In ko, this message translates to:
  /// **'스피커가 틀 수 있는 방송을 찾지 못했어요'**
  String get radioSearchNoResults;

  /// No description provided for @radioSearchFailed.
  ///
  /// In ko, this message translates to:
  /// **'방송 목록을 받지 못했어요. 인터넷 연결을 확인해 주세요'**
  String get radioSearchFailed;

  /// No description provided for @radioSearchAdd.
  ///
  /// In ko, this message translates to:
  /// **'추가'**
  String get radioSearchAdd;

  /// No description provided for @radioSearchAdded.
  ///
  /// In ko, this message translates to:
  /// **'추가됨'**
  String get radioSearchAdded;

  /// No description provided for @radioSearchPlayNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 틀기'**
  String get radioSearchPlayNow;

  /// No description provided for @radioAdded.
  ///
  /// In ko, this message translates to:
  /// **'{name} 방송을 추가했어요'**
  String radioAdded(String name);

  /// No description provided for @radioKbps.
  ///
  /// In ko, this message translates to:
  /// **'{kbps}kbps'**
  String radioKbps(int kbps);

  /// No description provided for @sysTitle.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get sysTitle;

  /// No description provided for @sysFirmware.
  ///
  /// In ko, this message translates to:
  /// **'펌웨어'**
  String get sysFirmware;

  /// No description provided for @sysUptime.
  ///
  /// In ko, this message translates to:
  /// **'켜진 시간'**
  String get sysUptime;

  /// No description provided for @sysWifi.
  ///
  /// In ko, this message translates to:
  /// **'Wi-Fi 신호'**
  String get sysWifi;

  /// No description provided for @sysWifiGood.
  ///
  /// In ko, this message translates to:
  /// **'좋음 ({dbm} dBm)'**
  String sysWifiGood(int dbm);

  /// No description provided for @sysWifiFair.
  ///
  /// In ko, this message translates to:
  /// **'보통 ({dbm} dBm)'**
  String sysWifiFair(int dbm);

  /// No description provided for @sysWifiWeak.
  ///
  /// In ko, this message translates to:
  /// **'약함 ({dbm} dBm)'**
  String sysWifiWeak(int dbm);

  /// No description provided for @sysWifiNone.
  ///
  /// In ko, this message translates to:
  /// **'연결 안 됨'**
  String get sysWifiNone;

  /// No description provided for @sysIp.
  ///
  /// In ko, this message translates to:
  /// **'IP 주소'**
  String get sysIp;

  /// No description provided for @sysUptimeDays.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 {hours}시간'**
  String sysUptimeDays(int days, int hours);

  /// No description provided for @sysUptimeHours.
  ///
  /// In ko, this message translates to:
  /// **'{hours}시간 {minutes}분'**
  String sysUptimeHours(int hours, int minutes);

  /// No description provided for @sysUptimeMinutes.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분'**
  String sysUptimeMinutes(int minutes);

  /// No description provided for @sysPhonesTitle.
  ///
  /// In ko, this message translates to:
  /// **'등록된 휴대폰 ({count} / {max})'**
  String sysPhonesTitle(int count, int max);

  /// No description provided for @sysPhoneSelf.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰'**
  String get sysPhoneSelf;

  /// No description provided for @sysPhoneCreated.
  ///
  /// In ko, this message translates to:
  /// **'{date} 등록'**
  String sysPhoneCreated(String date);

  /// No description provided for @sysPhoneRevoke.
  ///
  /// In ko, this message translates to:
  /// **'등록 해지'**
  String get sysPhoneRevoke;

  /// No description provided for @sysPhoneRevokeTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name}의 등록을 해지할까요?'**
  String sysPhoneRevokeTitle(String name);

  /// No description provided for @sysPhoneRevokeBody.
  ///
  /// In ko, this message translates to:
  /// **'그 휴대폰은 더 이상 스피커를 조작할 수 없어요. 다시 쓰려면 새로 등록해야 해요.'**
  String get sysPhoneRevokeBody;

  /// No description provided for @sysPhoneRevoked.
  ///
  /// In ko, this message translates to:
  /// **'등록을 해지했어요'**
  String get sysPhoneRevoked;

  /// No description provided for @sysPhonesFailed.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 목록을 불러오지 못했어요'**
  String get sysPhonesFailed;

  /// No description provided for @sysMenuKeys.
  ///
  /// In ko, this message translates to:
  /// **'키 관리'**
  String get sysMenuKeys;

  /// No description provided for @sysMenuKeysHint.
  ///
  /// In ko, this message translates to:
  /// **'OpenAI 키, 텔레그램 봇 토큰'**
  String get sysMenuKeysHint;

  /// No description provided for @sysMenuApp.
  ///
  /// In ko, this message translates to:
  /// **'앱 설정'**
  String get sysMenuApp;

  /// No description provided for @sysMenuAppHint.
  ///
  /// In ko, this message translates to:
  /// **'화면 모드, 언어'**
  String get sysMenuAppHint;

  /// No description provided for @sysDiagnostics.
  ///
  /// In ko, this message translates to:
  /// **'진단'**
  String get sysDiagnostics;

  /// No description provided for @sysBuildDate.
  ///
  /// In ko, this message translates to:
  /// **'빌드'**
  String get sysBuildDate;

  /// No description provided for @sysResetReason.
  ///
  /// In ko, this message translates to:
  /// **'마지막 시작 이유'**
  String get sysResetReason;

  /// No description provided for @sysResetPowerOn.
  ///
  /// In ko, this message translates to:
  /// **'전원 켜짐'**
  String get sysResetPowerOn;

  /// No description provided for @sysResetSoftware.
  ///
  /// In ko, this message translates to:
  /// **'다시 시작'**
  String get sysResetSoftware;

  /// No description provided for @sysResetCrash.
  ///
  /// In ko, this message translates to:
  /// **'오류로 다시 시작'**
  String get sysResetCrash;

  /// No description provided for @sysResetWatchdog.
  ///
  /// In ko, this message translates to:
  /// **'응답 없음으로 다시 시작'**
  String get sysResetWatchdog;

  /// No description provided for @sysResetBrownout.
  ///
  /// In ko, this message translates to:
  /// **'전원 부족'**
  String get sysResetBrownout;

  /// No description provided for @sysResetOther.
  ///
  /// In ko, this message translates to:
  /// **'기타 ({code})'**
  String sysResetOther(int code);

  /// No description provided for @sysHeapFree.
  ///
  /// In ko, this message translates to:
  /// **'내부 메모리 여유'**
  String get sysHeapFree;

  /// No description provided for @sysHeapMin.
  ///
  /// In ko, this message translates to:
  /// **'내부 메모리 최저'**
  String get sysHeapMin;

  /// No description provided for @sysPsramFree.
  ///
  /// In ko, this message translates to:
  /// **'PSRAM 여유'**
  String get sysPsramFree;

  /// No description provided for @sysKb.
  ///
  /// In ko, this message translates to:
  /// **'{value} KB'**
  String sysKb(int value);

  /// No description provided for @sysFailures.
  ///
  /// In ko, this message translates to:
  /// **'최근 실패'**
  String get sysFailures;

  /// No description provided for @sysNoFailures.
  ///
  /// In ko, this message translates to:
  /// **'없음'**
  String get sysNoFailures;

  /// No description provided for @sysReboot.
  ///
  /// In ko, this message translates to:
  /// **'스피커 다시 시작'**
  String get sysReboot;

  /// No description provided for @sysRebootTitle.
  ///
  /// In ko, this message translates to:
  /// **'스피커를 다시 시작할까요?'**
  String get sysRebootTitle;

  /// No description provided for @sysRebootBody.
  ///
  /// In ko, this message translates to:
  /// **'재생 중인 것은 멈추고, 30초쯤 뒤에 다시 연결돼요.'**
  String get sysRebootBody;

  /// No description provided for @sysRebootAction.
  ///
  /// In ko, this message translates to:
  /// **'다시 시작'**
  String get sysRebootAction;

  /// No description provided for @sysRebooting.
  ///
  /// In ko, this message translates to:
  /// **'다시 시작하고 있어요'**
  String get sysRebooting;

  /// No description provided for @sysFactoryResetTitle.
  ///
  /// In ko, this message translates to:
  /// **'공장 초기화'**
  String get sysFactoryResetTitle;

  /// No description provided for @sysFactoryResetBody.
  ///
  /// In ko, this message translates to:
  /// **'는 스피커에서 직접 해요. 가운데 버튼을 10초 누르면 모든 설정과 등록이 지워져요.'**
  String get sysFactoryResetBody;

  /// No description provided for @sysForget.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰에서 스피커 지우기'**
  String get sysForget;

  /// No description provided for @sysForgetTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰에서 스피커를 지울까요?'**
  String get sysForgetTitle;

  /// No description provided for @sysForgetBody.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 연결되면 이 휴대폰의 등록도 해지해요. 연결이 안 되면 스피커에 등록이 남으니 다른 휴대폰에서 해지하세요.'**
  String get sysForgetBody;

  /// No description provided for @sysForgetAction.
  ///
  /// In ko, this message translates to:
  /// **'지우기'**
  String get sysForgetAction;

  /// No description provided for @sysKeysTitle.
  ///
  /// In ko, this message translates to:
  /// **'키 관리'**
  String get sysKeysTitle;

  /// No description provided for @sysKeysPhoneSection.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰에 기억한 키'**
  String get sysKeysPhoneSection;

  /// No description provided for @sysKeysPhoneHint.
  ///
  /// In ko, this message translates to:
  /// **'스피커를 설정할 때 자동으로 채워요. 휴대폰 보안 저장소에 암호화돼 있어요.'**
  String get sysKeysPhoneHint;

  /// No description provided for @sysKeysSpeakerSection.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 저장된 키'**
  String get sysKeysSpeakerSection;

  /// No description provided for @sysKeysSpeakerHint.
  ///
  /// In ko, this message translates to:
  /// **'키는 Bluetooth로만 보내요. 스피커 가까이에서 바꾸세요.'**
  String get sysKeysSpeakerHint;

  /// No description provided for @sysKeyOpenAi.
  ///
  /// In ko, this message translates to:
  /// **'OpenAI API 키'**
  String get sysKeyOpenAi;

  /// No description provided for @sysKeyTelegram.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램 봇 토큰'**
  String get sysKeyTelegram;

  /// No description provided for @sysKeySaved.
  ///
  /// In ko, this message translates to:
  /// **'저장됨'**
  String get sysKeySaved;

  /// No description provided for @sysKeyNotSaved.
  ///
  /// In ko, this message translates to:
  /// **'없음'**
  String get sysKeyNotSaved;

  /// No description provided for @sysKeyUnknown.
  ///
  /// In ko, this message translates to:
  /// **'확인할 수 없어요'**
  String get sysKeyUnknown;

  /// No description provided for @sysKeyForget.
  ///
  /// In ko, this message translates to:
  /// **'지우기'**
  String get sysKeyForget;

  /// No description provided for @sysKeyForgetTitle.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰에서 이 키를 지울까요?'**
  String get sysKeyForgetTitle;

  /// No description provided for @sysKeyForgetBody.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 저장된 키는 그대로예요.'**
  String get sysKeyForgetBody;

  /// No description provided for @sysKeyReplace.
  ///
  /// In ko, this message translates to:
  /// **'바꾸기'**
  String get sysKeyReplace;

  /// No description provided for @sysKeyAdd.
  ///
  /// In ko, this message translates to:
  /// **'넣기'**
  String get sysKeyAdd;

  /// No description provided for @sysKeyDelete.
  ///
  /// In ko, this message translates to:
  /// **'지우기'**
  String get sysKeyDelete;

  /// No description provided for @sysKeyDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'스피커에서 이 키를 지울까요?'**
  String get sysKeyDeleteTitle;

  /// No description provided for @sysKeyDeleteBodyOpenAi.
  ///
  /// In ko, this message translates to:
  /// **'OpenAI를 쓰고 있으면 대화할 수 없어요. 한국어 수업도 할 수 없어요.'**
  String get sysKeyDeleteBodyOpenAi;

  /// No description provided for @sysKeyDeleteBodyTelegram.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램 메시지를 더 이상 받지 않아요.'**
  String get sysKeyDeleteBodyTelegram;

  /// No description provided for @sysKeyDeleted.
  ///
  /// In ko, this message translates to:
  /// **'스피커에서 지웠어요'**
  String get sysKeyDeleted;

  /// No description provided for @sysKeySend.
  ///
  /// In ko, this message translates to:
  /// **'스피커로 보내기'**
  String get sysKeySend;

  /// No description provided for @sysKeySending.
  ///
  /// In ko, this message translates to:
  /// **'스피커를 찾아 보내는 중…'**
  String get sysKeySending;

  /// No description provided for @sysKeySent.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 저장했어요'**
  String get sysKeySent;

  /// No description provided for @sysKeyInvalidOpenAi.
  ///
  /// In ko, this message translates to:
  /// **'sk-로 시작하는 키를 넣으세요'**
  String get sysKeyInvalidOpenAi;

  /// No description provided for @sysKeyInvalidTelegram.
  ///
  /// In ko, this message translates to:
  /// **'123456789:ABC… 형식의 토큰이 아니에요'**
  String get sysKeyInvalidTelegram;

  /// No description provided for @sysPaste.
  ///
  /// In ko, this message translates to:
  /// **'붙여넣기'**
  String get sysPaste;

  /// No description provided for @sysAppTitle.
  ///
  /// In ko, this message translates to:
  /// **'앱 설정'**
  String get sysAppTitle;

  /// No description provided for @sysAppHint.
  ///
  /// In ko, this message translates to:
  /// **'이 휴대폰에만 적용돼요.'**
  String get sysAppHint;

  /// No description provided for @sysLanguageSystem.
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 언어 따르기'**
  String get sysLanguageSystem;

  /// No description provided for @sysLanguageKo.
  ///
  /// In ko, this message translates to:
  /// **'한국어'**
  String get sysLanguageKo;

  /// No description provided for @sysLanguageEn.
  ///
  /// In ko, this message translates to:
  /// **'English'**
  String get sysLanguageEn;

  /// No description provided for @sysKeyGemini.
  ///
  /// In ko, this message translates to:
  /// **'Gemini API 키'**
  String get sysKeyGemini;

  /// No description provided for @sysKeyDeleteBodyGemini.
  ///
  /// In ko, this message translates to:
  /// **'Gemini를 쓰고 있으면 대화할 수 없어요.'**
  String get sysKeyDeleteBodyGemini;

  /// No description provided for @sysKeyInvalidGemini.
  ///
  /// In ko, this message translates to:
  /// **'Gemini 키는 AIza로 시작하고 영문·숫자·-·_만 들어가요 (끝에 :wq 같은 글자가 붙지 않았는지 확인해 주세요)'**
  String get sysKeyInvalidGemini;

  /// No description provided for @tgTitle.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램'**
  String get tgTitle;

  /// No description provided for @tgConnectTitle.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램 연결'**
  String get tgConnectTitle;

  /// No description provided for @tgStep1Title.
  ///
  /// In ko, this message translates to:
  /// **'봇 만들고 토큰 받기'**
  String get tgStep1Title;

  /// No description provided for @tgStep1Body.
  ///
  /// In ko, this message translates to:
  /// **'BotFather에게 /newbot을 보내 이 스피커 전용 봇을 만들고, 받은 토큰을 복사하세요.'**
  String get tgStep1Body;

  /// No description provided for @tgOpenBotFather.
  ///
  /// In ko, this message translates to:
  /// **'BotFather 열기'**
  String get tgOpenBotFather;

  /// No description provided for @tgStep2Title.
  ///
  /// In ko, this message translates to:
  /// **'토큰 확인 후 스피커에 저장'**
  String get tgStep2Title;

  /// No description provided for @tgTokenLabel.
  ///
  /// In ko, this message translates to:
  /// **'봇 토큰'**
  String get tgTokenLabel;

  /// No description provided for @tgTokenShow.
  ///
  /// In ko, this message translates to:
  /// **'토큰 보기'**
  String get tgTokenShow;

  /// No description provided for @tgTokenHide.
  ///
  /// In ko, this message translates to:
  /// **'토큰 숨기기'**
  String get tgTokenHide;

  /// No description provided for @tgCheckToken.
  ///
  /// In ko, this message translates to:
  /// **'토큰 확인'**
  String get tgCheckToken;

  /// No description provided for @tgTokenChecking.
  ///
  /// In ko, this message translates to:
  /// **'확인하는 중…'**
  String get tgTokenChecking;

  /// No description provided for @tgTokenValid.
  ///
  /// In ko, this message translates to:
  /// **'@{bot} 확인됨'**
  String tgTokenValid(String bot);

  /// No description provided for @tgTokenSaved.
  ///
  /// In ko, this message translates to:
  /// **'@{bot} 확인됨 · 스피커에 저장됨'**
  String tgTokenSaved(String bot);

  /// No description provided for @tgTokenInvalid.
  ///
  /// In ko, this message translates to:
  /// **'토큰이 맞지 않아요. BotFather에서 받은 토큰을 그대로 붙여 넣으세요'**
  String get tgTokenInvalid;

  /// No description provided for @tgTokenNetwork.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램에 연결할 수 없어요. 인터넷 연결을 확인하세요'**
  String get tgTokenNetwork;

  /// No description provided for @tgKey2Body.
  ///
  /// In ko, this message translates to:
  /// **'토큰은 Wi-Fi가 아니라 Bluetooth로만 스피커에 보내요.'**
  String get tgKey2Body;

  /// No description provided for @tgSaveToSpeaker.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 저장'**
  String get tgSaveToSpeaker;

  /// No description provided for @tgSaving.
  ///
  /// In ko, this message translates to:
  /// **'스피커를 찾아 저장하는 중…'**
  String get tgSaving;

  /// No description provided for @tgStep3Title.
  ///
  /// In ko, this message translates to:
  /// **'가족 대화방 등록'**
  String get tgStep3Title;

  /// No description provided for @tgPairBody.
  ///
  /// In ko, this message translates to:
  /// **'등록할 대화방(개인 또는 가족 그룹)에서 봇에게 아래처럼 보내세요.'**
  String get tgPairBody;

  /// No description provided for @tgPairGroupHint.
  ///
  /// In ko, this message translates to:
  /// **'그룹에서는 /pair@{bot} {code}'**
  String tgPairGroupHint(String bot, String code);

  /// No description provided for @tgPairRemaining.
  ///
  /// In ko, this message translates to:
  /// **'{min}분 {sec}초 남음 · 한 번만 쓸 수 있어요'**
  String tgPairRemaining(int min, int sec);

  /// No description provided for @tgCopy.
  ///
  /// In ko, this message translates to:
  /// **'복사'**
  String get tgCopy;

  /// No description provided for @tgCopied.
  ///
  /// In ko, this message translates to:
  /// **'복사했어요'**
  String get tgCopied;

  /// No description provided for @tgOpenTelegram.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램 열기'**
  String get tgOpenTelegram;

  /// No description provided for @tgOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'텔레그램을 열 수 없어요'**
  String get tgOpenFailed;

  /// No description provided for @tgPairWaiting.
  ///
  /// In ko, this message translates to:
  /// **'등록을 기다리는 중…'**
  String get tgPairWaiting;

  /// No description provided for @tgPairExpired.
  ///
  /// In ko, this message translates to:
  /// **'코드 시간이 지났어요. 새 코드를 받으세요'**
  String get tgPairExpired;

  /// No description provided for @tgPairNewCode.
  ///
  /// In ko, this message translates to:
  /// **'새 코드 받기'**
  String get tgPairNewCode;

  /// No description provided for @tgPairGetCode.
  ///
  /// In ko, this message translates to:
  /// **'등록 코드 받기'**
  String get tgPairGetCode;

  /// No description provided for @tgPairLocked.
  ///
  /// In ko, this message translates to:
  /// **'토큰을 스피커에 저장하면 코드를 받을 수 있어요'**
  String get tgPairLocked;

  /// No description provided for @tgPairNoToken.
  ///
  /// In ko, this message translates to:
  /// **'스피커에 봇 토큰이 아직 없어요. 토큰을 먼저 저장하세요'**
  String get tgPairNoToken;

  /// No description provided for @tgPaired.
  ///
  /// In ko, this message translates to:
  /// **'‘{name}’ 대화방을 등록했어요'**
  String tgPaired(String name);

  /// No description provided for @tgDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get tgDone;

  /// No description provided for @tgAddAnother.
  ///
  /// In ko, this message translates to:
  /// **'다른 대화방 등록'**
  String get tgAddAnother;

  /// No description provided for @tgAddChatTitle.
  ///
  /// In ko, this message translates to:
  /// **'대화방 추가'**
  String get tgAddChatTitle;

  /// No description provided for @tgReplaceToken.
  ///
  /// In ko, this message translates to:
  /// **'토큰 바꾸기'**
  String get tgReplaceToken;

  /// No description provided for @tgStateOk.
  ///
  /// In ko, this message translates to:
  /// **'연결됨'**
  String get tgStateOk;

  /// No description provided for @tgStateConnecting.
  ///
  /// In ko, this message translates to:
  /// **'연결하는 중'**
  String get tgStateConnecting;

  /// No description provided for @tgStateOff.
  ///
  /// In ko, this message translates to:
  /// **'연결 안 됨'**
  String get tgStateOff;

  /// No description provided for @tgStateConflict.
  ///
  /// In ko, this message translates to:
  /// **'다른 곳에서 같은 봇을 쓰고 있어요'**
  String get tgStateConflict;

  /// No description provided for @tgStateConflictBody.
  ///
  /// In ko, this message translates to:
  /// **'다른 프로그램이 같은 봇을 쓰면 스피커가 메시지를 받지 못해요. 이 스피커 전용 봇을 만들어 토큰을 바꾸세요.'**
  String get tgStateConflictBody;

  /// No description provided for @tgStateTokenInvalid.
  ///
  /// In ko, this message translates to:
  /// **'토큰이 맞지 않아요'**
  String get tgStateTokenInvalid;

  /// No description provided for @tgStateTokenInvalidBody.
  ///
  /// In ko, this message translates to:
  /// **'봇 토큰이 바뀌었거나 지워졌어요. 새 토큰으로 바꾸세요.'**
  String get tgStateTokenInvalidBody;

  /// No description provided for @tgUnread.
  ///
  /// In ko, this message translates to:
  /// **'읽지 않은 메시지 {count}'**
  String tgUnread(int count);

  /// No description provided for @tgChatsTitle.
  ///
  /// In ko, this message translates to:
  /// **'등록된 대화방'**
  String get tgChatsTitle;

  /// No description provided for @tgAddChat.
  ///
  /// In ko, this message translates to:
  /// **'+ 추가'**
  String get tgAddChat;

  /// No description provided for @tgChatsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 등록한 대화방이 없어요. ‘+ 추가’를 눌러 가족 대화방을 등록하세요.'**
  String get tgChatsEmpty;

  /// No description provided for @tgChatsHint.
  ///
  /// In ko, this message translates to:
  /// **'“엄마한테 늦는다고 보내 줘”처럼 별칭으로 불러요.'**
  String get tgChatsHint;

  /// No description provided for @tgChatPrivate.
  ///
  /// In ko, this message translates to:
  /// **'개인 대화'**
  String get tgChatPrivate;

  /// No description provided for @tgChatGroup.
  ///
  /// In ko, this message translates to:
  /// **'그룹'**
  String get tgChatGroup;

  /// No description provided for @tgChatChannel.
  ///
  /// In ko, this message translates to:
  /// **'채널'**
  String get tgChatChannel;

  /// No description provided for @tgRenameLabel.
  ///
  /// In ko, this message translates to:
  /// **'{alias} 별칭 바꾸기'**
  String tgRenameLabel(String alias);

  /// No description provided for @tgDeleteLabel.
  ///
  /// In ko, this message translates to:
  /// **'{alias} 삭제'**
  String tgDeleteLabel(String alias);

  /// No description provided for @tgRenameTitle.
  ///
  /// In ko, this message translates to:
  /// **'별칭 바꾸기'**
  String get tgRenameTitle;

  /// No description provided for @tgAliasHelp.
  ///
  /// In ko, this message translates to:
  /// **'음성으로 부를 이름이에요'**
  String get tgAliasHelp;

  /// No description provided for @tgAliasEmpty.
  ///
  /// In ko, this message translates to:
  /// **'별칭을 입력하세요'**
  String get tgAliasEmpty;

  /// No description provided for @tgAliasTooLong.
  ///
  /// In ko, this message translates to:
  /// **'너무 길어요 (한글 10자, 영문 32자까지)'**
  String get tgAliasTooLong;

  /// No description provided for @tgSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get tgSave;

  /// No description provided for @tgDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'‘{alias}’ 대화방을 지울까요?'**
  String tgDeleteTitle(String alias);

  /// No description provided for @tgDeleteBody.
  ///
  /// In ko, this message translates to:
  /// **'이 대화방의 메시지를 더 이상 받지 않아요. 다시 등록하려면 새 코드가 필요해요.'**
  String get tgDeleteBody;

  /// No description provided for @tgDeleteAction.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get tgDeleteAction;

  /// No description provided for @tgNotifyTitle.
  ///
  /// In ko, this message translates to:
  /// **'메시지 알림'**
  String get tgNotifyTitle;

  /// No description provided for @tgAutoRead.
  ///
  /// In ko, this message translates to:
  /// **'새 메시지 바로 읽어 주기'**
  String get tgAutoRead;

  /// No description provided for @tgAutoReadBody.
  ///
  /// In ko, this message translates to:
  /// **'꺼 두면 알림음만 나고 “메시지 읽어 줘”로 들어요'**
  String get tgAutoReadBody;

  /// No description provided for @tgQuietHours.
  ///
  /// In ko, this message translates to:
  /// **'조용한 시간'**
  String get tgQuietHours;

  /// No description provided for @tgQuietStart.
  ///
  /// In ko, this message translates to:
  /// **'시작'**
  String get tgQuietStart;

  /// No description provided for @tgQuietEnd.
  ///
  /// In ko, this message translates to:
  /// **'끝'**
  String get tgQuietEnd;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
