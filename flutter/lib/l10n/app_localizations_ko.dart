// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get aiModeTitle => 'AI · 대화 방식';

  @override
  String get aiModeSaver => '절약 모드';

  @override
  String get aiModeLive => '실시간';

  @override
  String aiLabel(String provider, String mode) {
    return '$provider · $mode';
  }

  @override
  String aiKeyLabel(String provider) {
    return '$provider API 키';
  }

  @override
  String get aiKeyInvalidGemini =>
      'Gemini 키는 AIza로 시작하고 영문·숫자·-·_만 들어가요 (끝에 :wq 같은 글자가 붙지 않았는지 확인해 주세요)';

  @override
  String get aiPriceShortOpenAiSaver => '월 약 1.5만 원';

  @override
  String get aiPriceShortOpenAiLive => '월 약 12.6만 원';

  @override
  String get aiPriceShortGeminiSaver => '월 약 1만 원';

  @override
  String get aiPriceShortGeminiLive => '월 약 4만 원';

  @override
  String get aiShortSaverNote => '대답 1~2초 늦음';

  @override
  String get aiShortLiveNote => '끼어들기 됨';

  @override
  String get aiPriceOpenAiSaver => '월 약 15,000원';

  @override
  String get aiPriceOpenAiLive => '월 약 126,000원';

  @override
  String get aiPriceGeminiSaver => '월 약 10,000원';

  @override
  String get aiPriceGeminiLive => '월 약 40,000원';

  @override
  String get aiDescOpenAiSaver => '사람이 말한 만큼만 요금이 나가요. 대답이 1~2초 늦어요.';

  @override
  String get aiDescOpenAiLive =>
      '가장 자연스럽고 빨라요. 대화가 연결된 시간만큼 요금이 나가요(분당 약 70원).';

  @override
  String get aiDescGeminiSaver => '가장 저렴해요. 대답이 1~2초 늦어요.';

  @override
  String get aiDescGeminiLive =>
      'Google Gemini 실시간 대화. OpenAI 실시간의 약 1/3 요금이에요.';

  @override
  String get aiTagInstant => '대답 바로';

  @override
  String get aiTagBargeIn => '말하는 중 끼어들기 됨';

  @override
  String get aiTagNoBargeIn => '끼어들기 안 됨 · 가운데 버튼으로 멈춤';

  @override
  String get aiTagOneEighth => '약 1/8 요금';

  @override
  String get aiTagCheapest => '가장 저렴';

  @override
  String get aiPickProvider => '① AI 고르기';

  @override
  String aiPickMode(String provider) {
    return '② $provider 대화 방식';
  }

  @override
  String get aiKeyPresent => '키 있음';

  @override
  String get aiKeyMissing => '키 없음 · 쓸 수 없어요';

  @override
  String get aiNotReady => '준비 중';

  @override
  String get aiNotReadyHint => '이 스피커에서는 아직 쓸 수 없어요. 스피커를 업데이트하면 열려요.';

  @override
  String aiAddKey(String provider) {
    return '$provider 키 넣기 (가운데 버튼 3초 → 블루투스로 보내요)';
  }

  @override
  String get aiInfoTitle => '알아 두세요';

  @override
  String get aiInfoBody =>
      '한국어 수업은 발음을 실시간으로 들어야 해서 늘 실시간 API(OpenAI)로 해요. 요금은 하루 1시간 쓸 때 한 달 예상이에요. 바꾸면 다음 대화부터 적용돼요.';

  @override
  String aiNoKeyError(String provider) {
    return '이 스피커에는 $provider 키가 없어요. 먼저 키를 넣어 주세요.';
  }

  @override
  String get aiChanged => '바꿨어요. 다음 대화부터 적용돼요';

  @override
  String aiKeySent(String provider) {
    return '$provider 키를 스피커에 넣었어요';
  }

  @override
  String get asstTitle => '비서';

  @override
  String get asstName => '이름';

  @override
  String get asstNameHint => '호출어는 바뀌지 않아요';

  @override
  String get asstLanguage => '말하는 언어';

  @override
  String get asstLanguageKo => '한국어';

  @override
  String get asstLanguageEn => 'English';

  @override
  String get asstLanguageHint => '스피커가 대화할 때 쓰는 언어예요. 앱 언어는 시스템 화면에서 바꿔요.';

  @override
  String get asstVoice => '목소리';

  @override
  String get asstVoiceNextTime => '다음 대화부터 바뀌어요';

  @override
  String get asstPurpose => '하는 일';

  @override
  String get asstPurposeHint => '비서의 역할이나 말투를 적어요';

  @override
  String get asstUnits => '단위';

  @override
  String get asstUnitsMetric => '미터법 (°C·km)';

  @override
  String get asstUnitsImperial => '야드파운드법 (°F·mi)';

  @override
  String get asstPlace => '사는 곳';

  @override
  String get asstPlaceBody => '날씨·근처 검색에 써요. 스피커에는 동네 이름만 저장하고 좌표는 보내지 않아요.';

  @override
  String get asstPlaceField => '동네';

  @override
  String get asstPlaceExample => '예: 서울 강남구 역삼동';

  @override
  String get asstUseCurrentLocation => '현재 위치로';

  @override
  String get asstTimezone => '시간대';

  @override
  String get asstLocationFilled => '동네와 시간대를 넣었어요. 저장을 눌러 주세요';

  @override
  String get asstLocationFilledOnlyPlace => '동네를 넣었어요. 시간대를 골라 주세요';

  @override
  String asstTimezoneUnsupported(String tz) {
    return '휴대폰 시간대($tz)는 스피커가 몰라요. 가까운 시간대를 골라 주세요.';
  }

  @override
  String get asstTimezoneUnknown => '휴대폰 시간대를 읽지 못했어요. 가까운 시간대를 골라 주세요.';

  @override
  String get asstTimezoneMore => '다른 시간대';

  @override
  String get asstLocationServiceOff => '휴대폰 위치 기능이 꺼져 있어요';

  @override
  String get asstLocationDenied => '위치 권한이 없어요. 동네를 직접 적어 주세요';

  @override
  String get asstLocationDeniedForever => '위치 권한이 꺼져 있어요. 설정에서 켜거나 직접 적어 주세요';

  @override
  String get asstOpenSettings => '설정 열기';

  @override
  String get asstLocationUnavailable => '위치를 찾지 못했어요. 직접 적어 주세요';

  @override
  String get asstWebSearch => '웹 검색 (날씨·뉴스)';

  @override
  String get asstDeviceControls => '기기 조작 (볼륨·라디오·기억)';

  @override
  String get asstAutoMemory => '대화 중 알게 된 것 자동 기억';

  @override
  String get asstMemories => '기억 목록';

  @override
  String asstMemoryCount(int count) {
    return '$count개';
  }

  @override
  String get asstSave => '저장';

  @override
  String get asstSaved => '저장했어요';

  @override
  String get asstDiscardTitle => '저장하지 않고 나갈까요?';

  @override
  String get asstDiscardBody => '고친 내용은 사라져요.';

  @override
  String get asstDiscard => '나가기';

  @override
  String get asstNameEmpty => '이름을 적어 주세요';

  @override
  String asstTooLong(int max) {
    return '너무 길어요 (최대 $max바이트)';
  }

  @override
  String asstBytes(int used, int max) {
    return '$used/$max바이트';
  }

  @override
  String get asstMemoriesNotice => '비서가 기억한 내용이에요. 지우면 다음 대화부터 잊어요.';

  @override
  String get asstMemoriesEmpty => '기억한 것이 없어요';

  @override
  String get asstForget => '지우기';

  @override
  String get asstForgetTitle => '이 기억을 지울까요?';

  @override
  String get asstForgotten => '지웠어요';

  @override
  String get audioTitle => '오디오·호출어';

  @override
  String get audioWakeEnabled => '호출어로 부르기';

  @override
  String get audioWakeEnabledHint => '끄면 가운데 버튼으로만 대화해요 (TV 볼 때)';

  @override
  String get audioPhrase => '호출어';

  @override
  String get audioPhraseComputer => '컴퓨터';

  @override
  String get audioPhraseAlexa => '알렉사';

  @override
  String get audioSensitivity => '감도';

  @override
  String get audioSensitivityLow => '오인식 적음';

  @override
  String get audioSensitivityHigh => '잘 알아들음';

  @override
  String get audioAdvanced => '고급';

  @override
  String get audioWakeGain => '호출어 입력 키우기';

  @override
  String get audioWakeGainHint => '멀리서 잘 못 알아들을 때만 올려요';

  @override
  String audioWakeGainValue(int db) {
    return '+$db dB';
  }

  @override
  String get audioWakeTest => '감지 테스트 (60초)';

  @override
  String audioWakeTestRunning(int seconds) {
    return '테스트 중 · $seconds초 남음';
  }

  @override
  String audioWakeTestHint(String phrase) {
    return '‘$phrase’라고 몇 번 불러 보세요';
  }

  @override
  String audioWakeTestCount(int count) {
    return '$count번 감지했어요';
  }

  @override
  String audioWakeTestDone(int count) {
    return '60초 동안 $count번 감지했어요';
  }

  @override
  String get audioVolume => '볼륨';

  @override
  String audioVolumeValue(int value, int max) {
    return '$value / $max';
  }

  @override
  String get audioDuck => '대화할 때 음악 줄이기';

  @override
  String audioDb(int db) {
    return '$db dB';
  }

  @override
  String get audioMicGain => '마이크 감도';

  @override
  String get audioMicGainHint => '높을수록 작은 소리도 들어요';

  @override
  String get audioAutoGain => '마이크 자동 조절';

  @override
  String get audioAutoGainHint => '말소리 크기에 맞춰 조금씩 조절해요';

  @override
  String get audioTestTone => '스피커 테스트음';

  @override
  String get audioLed => 'LED 밝기';

  @override
  String audioPercent(int value) {
    return '$value%';
  }

  @override
  String get appTitle => 'AI-PA';

  @override
  String get splashLoading => '스피커 정보를 불러오는 중…';

  @override
  String get settingsTheme => '화면 모드';

  @override
  String get settingsThemeSystem => '시스템 설정';

  @override
  String get settingsThemeLight => '밝게';

  @override
  String get settingsThemeDark => '어둡게';

  @override
  String get settingsLanguage => '언어';

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonCancel => '취소';

  @override
  String get commonOk => '확인';

  @override
  String get bleKey2Hint => '스피커 가운데 버튼(Key2)을 3초 누르세요';

  @override
  String get errorUnknown => '알 수 없는 오류가 났어요';

  @override
  String get errorNetwork => '네트워크에 연결할 수 없어요';

  @override
  String get errorCache => '휴대폰에 저장된 정보를 읽지 못했어요';

  @override
  String get errorDeviceUnreachable =>
      '스피커에 연결할 수 없어요. 휴대폰과 스피커가 같은 Wi-Fi인지 확인하세요';

  @override
  String get errorDeviceUnauthorized => '이 휴대폰의 등록이 해지됐어요. 다시 등록하세요';

  @override
  String get errorDeviceRateLimited => '잠시 뒤에 다시 시도하세요';

  @override
  String get errorDeviceTimeout => '스피커가 응답하지 않아요';

  @override
  String get errorDeviceInvalidArg => '스피커가 값을 받아들이지 않았어요';

  @override
  String get errorDeviceBusy => '스피커가 다른 작업 중이에요';

  @override
  String get errorDeviceStorage => '스피커에 저장하지 못했어요';

  @override
  String get errorDeviceNoApiKey => 'OpenAI 키가 아직 없어요';

  @override
  String get errorDeviceNoWifi => '스피커가 Wi-Fi에 연결돼 있지 않아요';

  @override
  String get errorDeviceVoiceActive => '대화 중에는 할 수 없어요';

  @override
  String get errorDeviceNotFound => '찾는 항목이 없어요';

  @override
  String get errorDeviceOtaTooLarge => '펌웨어 파일이 너무 커요';

  @override
  String get errorDeviceOtaSignature => '서명이 맞지 않는 펌웨어예요';

  @override
  String get errorBleAdapterOff => 'Bluetooth를 켜 주세요';

  @override
  String get errorBlePermission => 'Bluetooth 권한이 필요해요';

  @override
  String get errorBleNotFound => '스피커를 찾지 못했어요. Key2를 3초 눌렀는지 확인하세요';

  @override
  String get errorBleConnect => '스피커에 Bluetooth로 연결하지 못했어요';

  @override
  String get errorBleDisconnected => 'Bluetooth 연결이 끊겼어요';

  @override
  String get errorBleBondFailed =>
      '연결 보안 오류예요. 휴대폰 설정 > Bluetooth에서 JARVIS 기기를 지운 뒤 다시 시도하세요';

  @override
  String get errorBleProtocol => '스피커와 통신하는 중 오류가 났어요';

  @override
  String get errorBleTimeout => '스피커가 Bluetooth로 응답하지 않아요';

  @override
  String get errorBleWindowClosed => '설정 시간이 끝났어요. Key2를 3초 눌러 다시 여세요';

  @override
  String get errorBlePhonesFull => '등록할 수 있는 휴대폰 수가 가득 찼어요';

  @override
  String get errorBleUnsupportedVersion => '앱을 최신 버전으로 업데이트하세요';

  @override
  String get errorWifiAuth => 'Wi-Fi 비밀번호가 틀렸어요';

  @override
  String get errorWifiNotFound => '이 Wi-Fi를 찾지 못했어요';

  @override
  String get errorWifiTimeout => 'Wi-Fi 연결 시간이 초과됐어요';

  @override
  String get errorDeviceNotPlaying => '재생 중인 것이 없어요';

  @override
  String get errorDeviceNoTelegramToken => '스피커에 텔레그램 봇 토큰이 아직 없어요';

  @override
  String get errorDeviceNotesFull =>
      '스피커에 메모·일정이 가득 찼어요(1,000개). 지난 일정이나 필요 없는 메모를 지워 주세요';

  @override
  String get errorDeviceConflict => '스피커에서 방금 바뀌었어요. 바뀐 내용을 보고 다시 고쳐 주세요';

  @override
  String get engTitle => '한국어 선생님';

  @override
  String get engHomeSubtitle => '발음 · 기초 · 생활 · 비즈니스 · 고급';

  @override
  String get engIntro =>
      '코스를 고르고 시작하면 바로 스피커와 한국어로 프리토킹해요. 틀린 표현과 발음은 선생님이 대화하면서 고쳐 줘요.';

  @override
  String get engCoursePron => '발음 교정';

  @override
  String get engCoursePronDesc => '편하게 이야기하면서 틀린 발음을 그때그때 짚어 줘요';

  @override
  String get engCourseBasic => '기초 한국어 회화';

  @override
  String get engCourseBasicDesc => '쉬운 일상 이야기를 천천히. 막히면 영어로 도와줘요';

  @override
  String get engCourseDaily => '생활 한국어 회화';

  @override
  String get engCourseDailyDesc => '여행·식당·병원 같은 상황으로 자연스럽게 대화';

  @override
  String get engCourseBiz => '비즈니스 한국어 회화';

  @override
  String get engCourseBizDesc => '회의·전화·협상 이야기를 존댓말로 정중하게';

  @override
  String get engCourseAdv => '고급 한국어 회화';

  @override
  String get engCourseAdvDesc => '시사·의견 토론을 한국어로만. 더 자연스럽게 다듬어 줘요';

  @override
  String get engLevelAll => '모든 수준';

  @override
  String get engLevelBeginner => '입문';

  @override
  String get engLevelEasy => '초·중급';

  @override
  String get engLevelMid => '중급';

  @override
  String get engLevelAdvanced => '고급';

  @override
  String get engExplain => '설명 말';

  @override
  String get engExplainKorean => '한국어만';

  @override
  String get engExplainEnglish => '영어 섞기';

  @override
  String get engSpeed => '말 빠르기';

  @override
  String get engSpeedSlow => '천천히';

  @override
  String get engSpeedNormal => '보통';

  @override
  String get engLength => '수업 시간';

  @override
  String engMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String engStart(String course) {
    return '$course 프리토킹 시작';
  }

  @override
  String get engVoiceHint => '말로도 시작해요: “알렉사, 한국어 공부하자”';

  @override
  String get engCostNote => '수업은 최대 5분이에요. 수업 시간만큼 OpenAI 음성 대화 요금이 나와요.';

  @override
  String get engLessonTitle => '프리토킹';

  @override
  String engFreeTalk(String course) {
    return '$course · 프리토킹';
  }

  @override
  String engRemaining(String time) {
    return '$time 남음';
  }

  @override
  String get engStarting => '수업을 여는 중…';

  @override
  String get engListening => '듣고 있어요';

  @override
  String get engListeningBody =>
      '스피커에 대고 편하게 한국어로 말하세요. 틀려도 괜찮아요, 선생님이 대화하면서 고쳐 줘요.';

  @override
  String get engTopic => '지금 이야기';

  @override
  String get engTopicUnknown => '선생님이 주제를 정하는 중';

  @override
  String get engChangeTopic => '주제 바꾸기';

  @override
  String get engCorrections => '선생님이 고쳐 준 표현';

  @override
  String get engCorrectionsEmpty => '고친 표현이 생기면 여기에 나와요 (약 45초마다)';

  @override
  String get engPronunciationBadge => '발음';

  @override
  String get engEnd => '수업 끝내기';

  @override
  String get engSummarizing => '오늘 수업을 정리하는 중…';

  @override
  String get engDoneTitle => '수업을 마쳤어요';

  @override
  String engDoneMeta(String course, int minutes) {
    return '$course 프리토킹 · $minutes분';
  }

  @override
  String get engTodayCorrections => '오늘 고친 표현';

  @override
  String get engNoCorrections => '오늘은 고친 표현이 없어요. 잘했어요!';

  @override
  String get engPractice => '발음 더 연습할 단어';

  @override
  String get engNextTopic => '다음에 이야기해 볼 주제';

  @override
  String get engAgain => '다시 프리토킹';

  @override
  String get engHome => '홈으로';

  @override
  String get engLastLesson => '지난 수업 정리 보기';

  @override
  String get engRealtimeNote => '한국어 수업은 실시간 API(OpenAI)로 해요 · 분당 약 70원';

  @override
  String get engNeedOpenAiKey =>
      '한국어 수업은 OpenAI 키가 필요해요. 비서 > AI · 대화 방식에서 OpenAI 키를 넣어 주세요.';

  @override
  String get homeTitle => '스피커';

  @override
  String get homeAddSpeaker => '스피커 추가';

  @override
  String get homeSelectSpeaker => '스피커 선택';

  @override
  String get homeConnected => '연결됨';

  @override
  String get homeWifiGood => 'Wi-Fi 신호 좋음';

  @override
  String get homeWifiFair => 'Wi-Fi 신호 보통';

  @override
  String get homeWifiWeak => 'Wi-Fi 신호 약함';

  @override
  String get homeIdleTitle => '듣고 있어요';

  @override
  String get homeIdleBody => '“알렉사”라고 부르거나 아래 버튼을 누르세요';

  @override
  String get homeTalkingTitle => '대화 중';

  @override
  String get homeTalkingBody => '말이 끝나면 60초 뒤 자동으로 끝나요';

  @override
  String get homeConnectingTitle => '연결 중…';

  @override
  String get homeStartTalk => '대화 시작';

  @override
  String get homeStopTalk => '대화 끝내기';

  @override
  String get homeNothingPlaying => '재생 중인 것이 없어요';

  @override
  String get homeOpenRadio => '라디오 열기';

  @override
  String get homeRadioPlaying => '라디오 · 재생 중';

  @override
  String get homeRadioPaused => '라디오 · 일시정지';

  @override
  String get homeRadioBuffering => '라디오 · 연결 중';

  @override
  String get homeVolume => '볼륨';

  @override
  String get homePrevious => '이전 방송';

  @override
  String get homeNext => '다음 방송';

  @override
  String get homePause => '일시정지';

  @override
  String get homeResume => '재생';

  @override
  String get homeStop => '정지';

  @override
  String get homeTelegram => '텔레그램';

  @override
  String homeTelegramUnread(int count) {
    return '새 메시지 $count';
  }

  @override
  String get homeTelegramSetup => '연결하기';

  @override
  String get homeMenuRadio => '라디오';

  @override
  String get homeMenuAssistant => '비서';

  @override
  String get homeMenuAudio => '오디오·호출';

  @override
  String get homeMenuSystem => '시스템';

  @override
  String get homeUnreachableTitle => '스피커에 연결할 수 없어요';

  @override
  String get homeUnreachableBody => '휴대폰과 스피커가 같은 Wi-Fi에 있는지 확인하세요.';

  @override
  String get homeFindAgain => '다시 찾기';

  @override
  String get homeUnauthorizedTitle => '이 휴대폰의 등록이 해지됐어요';

  @override
  String get homeUnauthorizedBody => '스피커 가운데 버튼을 3초 누른 뒤 다시 등록하세요.';

  @override
  String get homeRegisterAgain => '다시 등록';

  @override
  String get homeEmptyTitle => '등록된 스피커가 없어요';

  @override
  String get homeEmptyBody => '휴대폰과 스피커를 가까이 두고 시작하세요. 처음 켠 스피커는 바로 보여요.';

  @override
  String get homeComingSoon => '이 화면은 준비 중이에요';

  @override
  String get homeRemoveFromPhone => '이 휴대폰에서 지우기';

  @override
  String get notesTitle => '메모·일정';

  @override
  String notesHomeToday(int count, String next) {
    return '오늘 $count개 · $next';
  }

  @override
  String notesHomeTodayCount(int count) {
    return '오늘 일정 $count개';
  }

  @override
  String get notesHomeEmpty => '메모·일정 보기';

  @override
  String notesClockHour(int hour) {
    return '$hour시';
  }

  @override
  String notesClockHourMinute(int hour, String minute) {
    return '$hour시 $minute분';
  }

  @override
  String get notesSearchHint => '메모·일정 찾기';

  @override
  String get notesTabEvents => '일정';

  @override
  String get notesTabMemos => '메모';

  @override
  String get notesTabTrash => '휴지통';

  @override
  String notesGroupToday(String date) {
    return '오늘 · $date';
  }

  @override
  String notesGroupTomorrow(String date) {
    return '내일 · $date';
  }

  @override
  String get notesGroupThisWeek => '이번 주';

  @override
  String get notesGroupLater => '나중';

  @override
  String get notesGroupPast => '지난 일정';

  @override
  String get notesAllDay => '하루 종일';

  @override
  String get notesBadgeScheduled => '알림 예정';

  @override
  String get notesBadgeSent => '보냄';

  @override
  String get notesBadgeAcked => '확인됨';

  @override
  String get notesBadgeNoAnswer => '대답 없음';

  @override
  String get notesBadgeMissed => '놓침';

  @override
  String get notesRemindLabel => '알림';

  @override
  String get notesRemindNone => '알림 없음';

  @override
  String get notesRemindOnTime => '정각';

  @override
  String notesRemindSameDay(String time) {
    return '당일 $time';
  }

  @override
  String notesRemindMinutes(int n) {
    return '$n분 전';
  }

  @override
  String notesRemindHours(int n) {
    return '$n시간 전';
  }

  @override
  String notesRemindHoursMinutes(int h, int m) {
    return '$h시간 $m분 전';
  }

  @override
  String get notesRemindDayBefore => '하루 전';

  @override
  String notesRemindDays(int n) {
    return '$n일 전';
  }

  @override
  String get notesRemindCustom => '직접 입력';

  @override
  String get notesRemindHintMany => '여러 개 고를 수 있어요';

  @override
  String get notesRemindHintMax => '최대 3개';

  @override
  String notesRemindSummary(String when) {
    return '스피커가 $when에 말로 알려 줘요';
  }

  @override
  String get notesRemindOff => '알림 설정에서 일정 알림이 꺼져 있어요';

  @override
  String get notesCustomTitle => '몇 분 전에 알릴까요?';

  @override
  String get notesCustomHelp => '1분부터 7일(10080분)까지';

  @override
  String get notesCustomUnit => '분 전';

  @override
  String get notesCustomAdd => '넣기';

  @override
  String get notesMemoToday => '오늘';

  @override
  String get notesMemoYesterday => '어제';

  @override
  String get notesTrashInfo => '말로 지운 메모·일정은 30일 동안 여기 있어요.';

  @override
  String notesTrashLeft(int days) {
    return '$days일 뒤 완전히 지워져요';
  }

  @override
  String get notesRestore => '되살리기';

  @override
  String get notesDeleteForever => '영구 삭제';

  @override
  String get notesVoiceHint =>
      '말로도 돼요: “알렉사, 내일 3시 병원 일정 넣고 1시간 전에 알려 줘” · “알렉사, 우유 사라고 메모해 줘” · “알렉사, 내일 일정 알려 줘”';

  @override
  String get notesPrivacy =>
      '말로 찾거나 알려 줄 때는 메모 내용이 OpenAI 대화로 전해져요. 저장은 스피커와 휴대폰에만 해요.';

  @override
  String get notesNew => '새로 만들기';

  @override
  String get notesOffline => '집 Wi-Fi에서 고칠 수 있어요';

  @override
  String get notesOfflineBody => '지금은 휴대폰에 저장된 내용만 보여요.';

  @override
  String get notesEmptyEvents => '일정이 없어요';

  @override
  String get notesEmptyMemos => '메모가 없어요';

  @override
  String get notesEmptyTrash => '휴지통이 비어 있어요';

  @override
  String get notesNoMatch => '찾는 내용이 없어요';

  @override
  String get notesEditEvent => '일정 편집';

  @override
  String get notesEditMemo => '메모 편집';

  @override
  String get notesNewEvent => '새 일정';

  @override
  String get notesNewMemo => '새 메모';

  @override
  String get notesFieldTitle => '제목';

  @override
  String get notesFieldBody => '내용';

  @override
  String get notesTitleRequired => '제목을 적어 주세요';

  @override
  String get notesEditHint => '말로 넣은 일정도 여기서 고칠 수 있어요. 고치면 스피커에 바로 반영돼요.';

  @override
  String get notesSave => '저장';

  @override
  String get notesDelete => '삭제';

  @override
  String notesDeleteTitle(String title) {
    return '“$title” 지울까요?';
  }

  @override
  String get notesDeleteBody => '스피커에서도 지워지고 되살릴 수 없어요. 다른 가족 휴대폰에서도 사라져요.';

  @override
  String get notesDeleteAction => '지우기';

  @override
  String get notesSaved => '저장했어요';

  @override
  String get notesDeleted => '지웠어요';

  @override
  String get notesRestored => '되살렸어요';

  @override
  String get notesSettingsTitle => '일정 알림';

  @override
  String get notesSettingsEnabled => '스피커가 일정 알려 주기';

  @override
  String get notesSettingsEnabledSub => '밤·새벽에도 정한 시각에 알려요';

  @override
  String get notesSettingsDefaults => '기본 알림 · 따로 정하지 않은 일정에 써요';

  @override
  String get notesSettingsTimed => '시각이 있는 일정';

  @override
  String get notesSettingsAllDay => '하루 종일 일정';

  @override
  String get notesSettingsSameMorning => '당일 아침';

  @override
  String get notesSettingsDayBeforeMorning => '하루 전 아침';

  @override
  String get notesSettingsAllDayTime => '알림 시각';

  @override
  String get notesSettingsInfoTitle => '알아 두세요';

  @override
  String get notesSettingsInfo =>
      '알림은 스피커가 짧게 대화를 열어 말로 알려 줘요. 알림 한 번마다 OpenAI 요금이 조금 들어요. 인터넷이 끊겼을 때는 알림음과 주황 불로 알려요.';

  @override
  String get provTitle => '스피커 설정';

  @override
  String get provKeysTitle => '어떤 AI를 쓸까요?';

  @override
  String get provKeysBody => '스피커에 연결하기 전에 정해요. 키를 복사하러 다른 앱에 다녀와도 괜찮아요.';

  @override
  String get provOpenAiKey => 'OpenAI API 키';

  @override
  String get provOpenAiKeyInvalid => 'sk- 로 시작하는 키를 넣어 주세요';

  @override
  String get provTelegramToken => '텔레그램 봇 토큰';

  @override
  String get provOptional => '(선택)';

  @override
  String get provTelegramTokenHint => '나중에 텔레그램 화면에서 넣어도 돼요.';

  @override
  String get provTelegramTokenInvalid => '123456789:ABC… 형식의 토큰이 아니에요';

  @override
  String get provPhoneName => '이 휴대폰 이름';

  @override
  String get provRemember => '이 휴대폰에 키 기억하기';

  @override
  String get provRememberHint => '다음 설정 때 자동으로 채워요. 휴대폰의 보안 저장소에 암호화해 둬요.';

  @override
  String get provPaste => '붙여넣기';

  @override
  String get provFindSpeaker => '스피커 찾기';

  @override
  String get provScanTitle => '근처 스피커를 찾고 있어요';

  @override
  String get provScanHint =>
      '새 스피커는 켜면 바로 보여요. 이미 설정한 스피커는 가운데 버튼(Key2)을 3초 누르세요.';

  @override
  String provScanFound(int count) {
    return '찾은 스피커 $count대';
  }

  @override
  String get provScanNone => '아직 찾은 스피커가 없어요';

  @override
  String get provScanAgain => '다시 찾기';

  @override
  String get provSignalNear => '아주 가까움';

  @override
  String get provSignalFar => '멀리 있음';

  @override
  String get provConnecting => '스피커에 연결하는 중…';

  @override
  String get provWifiChoiceTitle => '이 스피커는 이미 Wi-Fi에 연결돼 있어요';

  @override
  String get provWifiChoiceBody => '그대로 두면 다시 시작하지 않고 바로 등록해요.';

  @override
  String get provWifiKeep => '지금 Wi-Fi 그대로';

  @override
  String get provWifiChange => 'Wi-Fi 바꾸기';

  @override
  String get provWifiTitle => '스피커가 쓸 Wi-Fi를 고르세요';

  @override
  String get provWifiScanning => '스피커가 주변 Wi-Fi를 찾는 중…';

  @override
  String get provWifiNote =>
      '스피커는 2.4GHz Wi-Fi만 연결할 수 있어요. 목록은 스피커가 직접 찾은 것이에요.';

  @override
  String get provWifiOpen => '개방';

  @override
  String get provWifiManual => '목록에 없는 Wi-Fi 직접 입력';

  @override
  String get provWifiName => 'Wi-Fi 이름';

  @override
  String get provWifiPassword => '비밀번호';

  @override
  String provWifiPasswordTitle(String ssid) {
    return '$ssid 비밀번호';
  }

  @override
  String get provWifiShowPassword => '비밀번호 보기';

  @override
  String get provWifiConnect => '연결';

  @override
  String provWifiConnecting(String ssid) {
    return '$ssid에 연결하는 중… (최대 20초)';
  }

  @override
  String get provWifiRescan => '다시 찾기';

  @override
  String get provSending => '키를 저장하고 이 휴대폰을 등록하는 중…';

  @override
  String get provPhonesFullTitle => '등록할 수 있는 휴대폰이 가득 찼어요';

  @override
  String get provPhonesFullBody => '지울 휴대폰을 하나 고르면 그 자리에 이 휴대폰을 등록해요.';

  @override
  String get provPhonesFullAction => '지우고 이 휴대폰 등록';

  @override
  String get provDiscovering => '스피커가 다시 시작하는 중이에요. 같은 Wi-Fi에서 찾고 있어요…';

  @override
  String get provDoneTitle => '설정이 끝났어요';

  @override
  String get provDoneBody => '“AI 스피커가 준비되었습니다” 안내가 나오면 “알렉사”라고 불러 보세요.';

  @override
  String get provDoneWifi => 'Wi-Fi 연결';

  @override
  String get provDoneKey => '키 저장';

  @override
  String get provDonePair => '이 휴대폰 등록';

  @override
  String provDoneFound(String host) {
    return '같은 Wi-Fi에서 스피커 찾음 ($host)';
  }

  @override
  String get provDoneNotFound => '아직 같은 Wi-Fi에서 찾지 못했어요. 홈에서 다시 찾을 수 있어요.';

  @override
  String get provGoHome => '홈으로';

  @override
  String get provFailedTitle => '설정을 마치지 못했어요';

  @override
  String get provCancel => '그만두기';

  @override
  String get provAiSection => '① AI';

  @override
  String get provRequired => '(필수)';

  @override
  String get provKeyTyped => '키가 들어갔어요. 스피커에는 블루투스로만 보내요.';

  @override
  String get provKeyExistingHint =>
      '연결한 뒤 스피커에 이 키가 있는지 확인해요. 없으면 이 AI는 고를 수 없어요.';

  @override
  String get provKeyRequiredHint => '이 AI를 쓰려면 키가 꼭 있어야 해요.';

  @override
  String get provExistingKey => '이미 이 AI 키가 저장된 스피커예요 (휴대폰 추가 등록)';

  @override
  String get provModeSection => '② 대화 방식';

  @override
  String get provModeLater => '(나중에 비서 설정에서 바꿀 수 있어요)';

  @override
  String provMore(String other) {
    return '더 넣기 (선택): $other 키 · 텔레그램 토큰';
  }

  @override
  String provMoreOtherHint(String other) {
    return '$other 키를 함께 넣으면 나중에 AI를 바로 바꿀 수 있어요.';
  }

  @override
  String provKeyBlocked(String key) {
    return '$key를 넣어야 다음으로 갈 수 있어요';
  }

  @override
  String provMissingKey(String provider) {
    return '이 스피커에는 $provider 키가 없어요. 키를 넣거나 다른 AI를 고르세요.';
  }

  @override
  String get provMaybeNotReady => '(스피커에 따라 준비 중일 수 있어요)';

  @override
  String provNotReady(String provider) {
    return '이 스피커는 아직 $provider를 쓸 수 없어요(준비 중). 다른 AI를 고르거나 스피커를 업데이트한 뒤 다시 해 주세요.';
  }

  @override
  String get radioTitle => '라디오';

  @override
  String get radioSearch => '방송 찾기';

  @override
  String get radioEdit => '편집';

  @override
  String get radioPlaying => '재생 중';

  @override
  String get radioPaused => '일시정지';

  @override
  String get radioBuffering => '연결 중';

  @override
  String get radioNothingPlaying => '재생 중인 것이 없어요';

  @override
  String get radioPickStation => '아래에서 방송을 골라 주세요';

  @override
  String get radioPlay => '재생';

  @override
  String get radioPause => '일시정지';

  @override
  String get radioResume => '다시 재생';

  @override
  String get radioStop => '정지';

  @override
  String get radioPrevious => '이전 방송';

  @override
  String get radioNext => '다음 방송';

  @override
  String get radioGroupMusic => '음악';

  @override
  String get radioGroupKorean => '한국 음악';

  @override
  String get radioGroupNews => '뉴스·경제';

  @override
  String get radioGroupTalk => '토크';

  @override
  String get radioGroupOther => '기타';

  @override
  String get radioEmpty => '저장된 방송이 없어요. 방송 찾기로 추가해 보세요';

  @override
  String get radioNotPlaying => '지금 재생 중인 방송이 없어요';

  @override
  String get radioEditTitle => '방송 편집';

  @override
  String get radioEditHint => '끌어서 순서를 바꿔요. 저장해야 스피커에 반영돼요';

  @override
  String radioCount(int count, int max) {
    return '$count / $max개';
  }

  @override
  String get radioSave => '저장';

  @override
  String get radioSaved => '저장했어요';

  @override
  String get radioAddCustom => '주소로 직접 추가';

  @override
  String get radioRename => '이름 바꾸기';

  @override
  String get radioDelete => '삭제';

  @override
  String radioDeleteTitle(String name) {
    return '$name 방송을 지울까요?';
  }

  @override
  String get radioDiscardTitle => '바꾼 내용을 버릴까요?';

  @override
  String get radioDiscard => '버리기';

  @override
  String get radioFormName => '이름';

  @override
  String get radioFormUrl => '방송 주소';

  @override
  String get radioFormUrlHint => 'http:// 또는 https://로 시작하는 MP3·AAC 스트림';

  @override
  String get radioFormGenre => '장르 태그';

  @override
  String get radioFormGenreHint => '쉼표로 구분해요 (예: kpop,korean)';

  @override
  String get radioFormAdd => '추가';

  @override
  String radioErrTooMany(int max) {
    return '방송은 $max개까지 저장할 수 있어요';
  }

  @override
  String get radioErrNameEmpty => '이름을 입력해 주세요';

  @override
  String get radioErrNameTooLong => '이름이 너무 길어요 (한글 16자, 영문 48자까지)';

  @override
  String get radioErrUrlInvalid => 'http:// 또는 https://로 시작하는 주소만 쓸 수 있어요';

  @override
  String get radioErrUrlTooLong => '주소가 너무 길어요 (256자까지)';

  @override
  String get radioErrGenreTooLong => '장르 태그가 너무 길어요 (64자까지)';

  @override
  String get radioErrTooLarge => '목록이 너무 커요. 이름이나 주소를 줄여 주세요';

  @override
  String get radioErrDuplicate => '이미 저장된 방송이에요';

  @override
  String get radioSearchTitle => '방송 찾기';

  @override
  String get radioSearchByName => '이름';

  @override
  String get radioSearchByTag => '장르';

  @override
  String get radioSearchNameHint => '방송 이름 (예: BBC, jazz)';

  @override
  String get radioSearchTagHint => '장르 태그 (예: jazz, kpop, news)';

  @override
  String get radioSearchHlsNote =>
      'KBS·MBC·SBS 같은 한국 방송사는 HLS 방식이라 스피커가 틀 수 없어 목록에 나오지 않아요';

  @override
  String get radioSearchIdle => '이름이나 장르로 찾아 보세요. 스피커가 틀 수 있는 방송만 보여요';

  @override
  String get radioSearchNoResults => '스피커가 틀 수 있는 방송을 찾지 못했어요';

  @override
  String get radioSearchFailed => '방송 목록을 받지 못했어요. 인터넷 연결을 확인해 주세요';

  @override
  String get radioSearchAdd => '추가';

  @override
  String get radioSearchAdded => '추가됨';

  @override
  String get radioSearchPlayNow => '지금 틀기';

  @override
  String radioAdded(String name) {
    return '$name 방송을 추가했어요';
  }

  @override
  String radioKbps(int kbps) {
    return '${kbps}kbps';
  }

  @override
  String get sysTitle => '시스템';

  @override
  String get sysFirmware => '펌웨어';

  @override
  String get sysUptime => '켜진 시간';

  @override
  String get sysWifi => 'Wi-Fi 신호';

  @override
  String sysWifiGood(int dbm) {
    return '좋음 ($dbm dBm)';
  }

  @override
  String sysWifiFair(int dbm) {
    return '보통 ($dbm dBm)';
  }

  @override
  String sysWifiWeak(int dbm) {
    return '약함 ($dbm dBm)';
  }

  @override
  String get sysWifiNone => '연결 안 됨';

  @override
  String get sysIp => 'IP 주소';

  @override
  String sysUptimeDays(int days, int hours) {
    return '$days일 $hours시간';
  }

  @override
  String sysUptimeHours(int hours, int minutes) {
    return '$hours시간 $minutes분';
  }

  @override
  String sysUptimeMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String sysPhonesTitle(int count, int max) {
    return '등록된 휴대폰 ($count / $max)';
  }

  @override
  String get sysPhoneSelf => '이 휴대폰';

  @override
  String sysPhoneCreated(String date) {
    return '$date 등록';
  }

  @override
  String get sysPhoneRevoke => '등록 해지';

  @override
  String sysPhoneRevokeTitle(String name) {
    return '$name의 등록을 해지할까요?';
  }

  @override
  String get sysPhoneRevokeBody =>
      '그 휴대폰은 더 이상 스피커를 조작할 수 없어요. 다시 쓰려면 새로 등록해야 해요.';

  @override
  String get sysPhoneRevoked => '등록을 해지했어요';

  @override
  String get sysPhonesFailed => '휴대폰 목록을 불러오지 못했어요';

  @override
  String get sysMenuKeys => '키 관리';

  @override
  String get sysMenuKeysHint => 'OpenAI 키, 텔레그램 봇 토큰';

  @override
  String get sysMenuApp => '앱 설정';

  @override
  String get sysMenuAppHint => '화면 모드, 언어';

  @override
  String get sysDiagnostics => '진단';

  @override
  String get sysBuildDate => '빌드';

  @override
  String get sysResetReason => '마지막 시작 이유';

  @override
  String get sysResetPowerOn => '전원 켜짐';

  @override
  String get sysResetSoftware => '다시 시작';

  @override
  String get sysResetCrash => '오류로 다시 시작';

  @override
  String get sysResetWatchdog => '응답 없음으로 다시 시작';

  @override
  String get sysResetBrownout => '전원 부족';

  @override
  String sysResetOther(int code) {
    return '기타 ($code)';
  }

  @override
  String get sysHeapFree => '내부 메모리 여유';

  @override
  String get sysHeapMin => '내부 메모리 최저';

  @override
  String get sysPsramFree => 'PSRAM 여유';

  @override
  String sysKb(int value) {
    return '$value KB';
  }

  @override
  String get sysFailures => '최근 실패';

  @override
  String get sysNoFailures => '없음';

  @override
  String get sysReboot => '스피커 다시 시작';

  @override
  String get sysRebootTitle => '스피커를 다시 시작할까요?';

  @override
  String get sysRebootBody => '재생 중인 것은 멈추고, 30초쯤 뒤에 다시 연결돼요.';

  @override
  String get sysRebootAction => '다시 시작';

  @override
  String get sysRebooting => '다시 시작하고 있어요';

  @override
  String get sysFactoryResetTitle => '공장 초기화';

  @override
  String get sysFactoryResetBody =>
      '는 스피커에서 직접 해요. 가운데 버튼을 10초 누르면 모든 설정과 등록이 지워져요.';

  @override
  String get sysForget => '이 휴대폰에서 스피커 지우기';

  @override
  String get sysForgetTitle => '이 휴대폰에서 스피커를 지울까요?';

  @override
  String get sysForgetBody =>
      '스피커에 연결되면 이 휴대폰의 등록도 해지해요. 연결이 안 되면 스피커에 등록이 남으니 다른 휴대폰에서 해지하세요.';

  @override
  String get sysForgetAction => '지우기';

  @override
  String get sysKeysTitle => '키 관리';

  @override
  String get sysKeysPhoneSection => '이 휴대폰에 기억한 키';

  @override
  String get sysKeysPhoneHint => '스피커를 설정할 때 자동으로 채워요. 휴대폰 보안 저장소에 암호화돼 있어요.';

  @override
  String get sysKeysSpeakerSection => '스피커에 저장된 키';

  @override
  String get sysKeysSpeakerHint => '키는 Bluetooth로만 보내요. 스피커 가까이에서 바꾸세요.';

  @override
  String get sysKeyOpenAi => 'OpenAI API 키';

  @override
  String get sysKeyTelegram => '텔레그램 봇 토큰';

  @override
  String get sysKeySaved => '저장됨';

  @override
  String get sysKeyNotSaved => '없음';

  @override
  String get sysKeyUnknown => '확인할 수 없어요';

  @override
  String get sysKeyForget => '지우기';

  @override
  String get sysKeyForgetTitle => '휴대폰에서 이 키를 지울까요?';

  @override
  String get sysKeyForgetBody => '스피커에 저장된 키는 그대로예요.';

  @override
  String get sysKeyReplace => '바꾸기';

  @override
  String get sysKeyAdd => '넣기';

  @override
  String get sysKeyDelete => '지우기';

  @override
  String get sysKeyDeleteTitle => '스피커에서 이 키를 지울까요?';

  @override
  String get sysKeyDeleteBodyOpenAi =>
      'OpenAI를 쓰고 있으면 대화할 수 없어요. 한국어 수업도 할 수 없어요.';

  @override
  String get sysKeyDeleteBodyTelegram => '텔레그램 메시지를 더 이상 받지 않아요.';

  @override
  String get sysKeyDeleted => '스피커에서 지웠어요';

  @override
  String get sysKeySend => '스피커로 보내기';

  @override
  String get sysKeySending => '스피커를 찾아 보내는 중…';

  @override
  String get sysKeySent => '스피커에 저장했어요';

  @override
  String get sysKeyInvalidOpenAi => 'sk-로 시작하는 키를 넣으세요';

  @override
  String get sysKeyInvalidTelegram => '123456789:ABC… 형식의 토큰이 아니에요';

  @override
  String get sysPaste => '붙여넣기';

  @override
  String get sysAppTitle => '앱 설정';

  @override
  String get sysAppHint => '이 휴대폰에만 적용돼요.';

  @override
  String get sysLanguageSystem => '휴대폰 언어 따르기';

  @override
  String get sysLanguageKo => '한국어';

  @override
  String get sysLanguageEn => 'English';

  @override
  String get sysKeyGemini => 'Gemini API 키';

  @override
  String get sysKeyDeleteBodyGemini => 'Gemini를 쓰고 있으면 대화할 수 없어요.';

  @override
  String get sysKeyInvalidGemini =>
      'Gemini 키는 AIza로 시작하고 영문·숫자·-·_만 들어가요 (끝에 :wq 같은 글자가 붙지 않았는지 확인해 주세요)';

  @override
  String get tgTitle => '텔레그램';

  @override
  String get tgConnectTitle => '텔레그램 연결';

  @override
  String get tgStep1Title => '봇 만들고 토큰 받기';

  @override
  String get tgStep1Body =>
      'BotFather에게 /newbot을 보내 이 스피커 전용 봇을 만들고, 받은 토큰을 복사하세요.';

  @override
  String get tgOpenBotFather => 'BotFather 열기';

  @override
  String get tgStep2Title => '토큰 확인 후 스피커에 저장';

  @override
  String get tgTokenLabel => '봇 토큰';

  @override
  String get tgTokenShow => '토큰 보기';

  @override
  String get tgTokenHide => '토큰 숨기기';

  @override
  String get tgCheckToken => '토큰 확인';

  @override
  String get tgTokenChecking => '확인하는 중…';

  @override
  String tgTokenValid(String bot) {
    return '@$bot 확인됨';
  }

  @override
  String tgTokenSaved(String bot) {
    return '@$bot 확인됨 · 스피커에 저장됨';
  }

  @override
  String get tgTokenInvalid => '토큰이 맞지 않아요. BotFather에서 받은 토큰을 그대로 붙여 넣으세요';

  @override
  String get tgTokenNetwork => '텔레그램에 연결할 수 없어요. 인터넷 연결을 확인하세요';

  @override
  String get tgKey2Body => '토큰은 Wi-Fi가 아니라 Bluetooth로만 스피커에 보내요.';

  @override
  String get tgSaveToSpeaker => '스피커에 저장';

  @override
  String get tgSaving => '스피커를 찾아 저장하는 중…';

  @override
  String get tgStep3Title => '가족 대화방 등록';

  @override
  String get tgPairBody => '등록할 대화방(개인 또는 가족 그룹)에서 봇에게 아래처럼 보내세요.';

  @override
  String tgPairGroupHint(String bot, String code) {
    return '그룹에서는 /pair@$bot $code';
  }

  @override
  String tgPairRemaining(int min, int sec) {
    return '$min분 $sec초 남음 · 한 번만 쓸 수 있어요';
  }

  @override
  String get tgCopy => '복사';

  @override
  String get tgCopied => '복사했어요';

  @override
  String get tgOpenTelegram => '텔레그램 열기';

  @override
  String get tgOpenFailed => '텔레그램을 열 수 없어요';

  @override
  String get tgPairWaiting => '등록을 기다리는 중…';

  @override
  String get tgPairExpired => '코드 시간이 지났어요. 새 코드를 받으세요';

  @override
  String get tgPairNewCode => '새 코드 받기';

  @override
  String get tgPairGetCode => '등록 코드 받기';

  @override
  String get tgPairLocked => '토큰을 스피커에 저장하면 코드를 받을 수 있어요';

  @override
  String get tgPairNoToken => '스피커에 봇 토큰이 아직 없어요. 토큰을 먼저 저장하세요';

  @override
  String tgPaired(String name) {
    return '‘$name’ 대화방을 등록했어요';
  }

  @override
  String get tgDone => '완료';

  @override
  String get tgAddAnother => '다른 대화방 등록';

  @override
  String get tgAddChatTitle => '대화방 추가';

  @override
  String get tgReplaceToken => '토큰 바꾸기';

  @override
  String get tgStateOk => '연결됨';

  @override
  String get tgStateConnecting => '연결하는 중';

  @override
  String get tgStateOff => '연결 안 됨';

  @override
  String get tgStateConflict => '다른 곳에서 같은 봇을 쓰고 있어요';

  @override
  String get tgStateConflictBody =>
      '다른 프로그램이 같은 봇을 쓰면 스피커가 메시지를 받지 못해요. 이 스피커 전용 봇을 만들어 토큰을 바꾸세요.';

  @override
  String get tgStateTokenInvalid => '토큰이 맞지 않아요';

  @override
  String get tgStateTokenInvalidBody => '봇 토큰이 바뀌었거나 지워졌어요. 새 토큰으로 바꾸세요.';

  @override
  String tgUnread(int count) {
    return '읽지 않은 메시지 $count';
  }

  @override
  String get tgChatsTitle => '등록된 대화방';

  @override
  String get tgAddChat => '+ 추가';

  @override
  String get tgChatsEmpty => '아직 등록한 대화방이 없어요. ‘+ 추가’를 눌러 가족 대화방을 등록하세요.';

  @override
  String get tgChatsHint => '“엄마한테 늦는다고 보내 줘”처럼 별칭으로 불러요.';

  @override
  String get tgChatPrivate => '개인 대화';

  @override
  String get tgChatGroup => '그룹';

  @override
  String get tgChatChannel => '채널';

  @override
  String tgRenameLabel(String alias) {
    return '$alias 별칭 바꾸기';
  }

  @override
  String tgDeleteLabel(String alias) {
    return '$alias 삭제';
  }

  @override
  String get tgRenameTitle => '별칭 바꾸기';

  @override
  String get tgAliasHelp => '음성으로 부를 이름이에요';

  @override
  String get tgAliasEmpty => '별칭을 입력하세요';

  @override
  String get tgAliasTooLong => '너무 길어요 (한글 10자, 영문 32자까지)';

  @override
  String get tgSave => '저장';

  @override
  String tgDeleteTitle(String alias) {
    return '‘$alias’ 대화방을 지울까요?';
  }

  @override
  String get tgDeleteBody => '이 대화방의 메시지를 더 이상 받지 않아요. 다시 등록하려면 새 코드가 필요해요.';

  @override
  String get tgDeleteAction => '삭제';

  @override
  String get tgNotifyTitle => '메시지 알림';

  @override
  String get tgAutoRead => '새 메시지 바로 읽어 주기';

  @override
  String get tgAutoReadBody => '꺼 두면 알림음만 나고 “메시지 읽어 줘”로 들어요';

  @override
  String get tgQuietHours => '조용한 시간';

  @override
  String get tgQuietStart => '시작';

  @override
  String get tgQuietEnd => '끝';
}
