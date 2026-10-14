// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aiModeTitle => 'AI · Conversation mode';

  @override
  String get aiModeSaver => 'Saver';

  @override
  String get aiModeLive => 'Real-time';

  @override
  String aiLabel(String provider, String mode) {
    return '$provider · $mode';
  }

  @override
  String aiKeyLabel(String provider) {
    return '$provider API key';
  }

  @override
  String get aiKeyInvalidGemini =>
      'A Gemini key starts with AIza and has only letters, digits, - and _ (check nothing like :wq got pasted at the end)';

  @override
  String get aiPriceShortOpenAiSaver => 'About ₩15k/month';

  @override
  String get aiPriceShortOpenAiLive => 'About ₩126k/month';

  @override
  String get aiPriceShortGeminiSaver => 'About ₩10k/month';

  @override
  String get aiPriceShortGeminiLive => 'About ₩40k/month';

  @override
  String get aiShortSaverNote => 'Replies 1–2 s later';

  @override
  String get aiShortLiveNote => 'You can interrupt';

  @override
  String get aiPriceOpenAiSaver => 'About ₩15,000/month';

  @override
  String get aiPriceOpenAiLive => 'About ₩126,000/month';

  @override
  String get aiPriceGeminiSaver => 'About ₩10,000/month';

  @override
  String get aiPriceGeminiLive => 'About ₩40,000/month';

  @override
  String get aiDescOpenAiSaver =>
      'You pay only for what people say. Replies come 1–2 seconds later.';

  @override
  String get aiDescOpenAiLive =>
      'The most natural and fastest. You pay for the whole connected time (about ₩70 a minute).';

  @override
  String get aiDescGeminiSaver =>
      'The cheapest. Replies come 1–2 seconds later.';

  @override
  String get aiDescGeminiLive =>
      'Google Gemini real-time talk. About 1/3 the price of OpenAI real-time.';

  @override
  String get aiTagInstant => 'Instant replies';

  @override
  String get aiTagBargeIn => 'Interrupt while it talks';

  @override
  String get aiTagNoBargeIn => 'No interrupting · stop with the middle button';

  @override
  String get aiTagOneEighth => 'About 1/8 the price';

  @override
  String get aiTagCheapest => 'Cheapest';

  @override
  String get aiPickProvider => '① Choose the AI';

  @override
  String aiPickMode(String provider) {
    return '② $provider conversation mode';
  }

  @override
  String get aiKeyPresent => 'Key saved';

  @override
  String get aiKeyMissing => 'No key · can\'t use';

  @override
  String get aiNotReady => 'Coming soon';

  @override
  String get aiNotReadyHint =>
      'Not available on this speaker yet. It opens after a speaker update.';

  @override
  String aiAddKey(String provider) {
    return 'Add $provider key (hold the middle button 3 s → sent over Bluetooth)';
  }

  @override
  String get aiInfoTitle => 'Good to know';

  @override
  String get aiInfoBody =>
      'Korean lessons always use the real-time API (OpenAI) because the teacher must hear pronunciation live. Prices are monthly estimates for 1 hour a day. Changes apply from the next conversation.';

  @override
  String aiNoKeyError(String provider) {
    return 'This speaker has no $provider key. Please add the key first.';
  }

  @override
  String get aiChanged => 'Changed. It applies from the next conversation';

  @override
  String aiKeySent(String provider) {
    return '$provider key saved on the speaker';
  }

  @override
  String get asstTitle => 'Assistant';

  @override
  String get asstName => 'Name';

  @override
  String get asstNameHint => 'The wake word stays the same';

  @override
  String get asstLanguage => 'Speaking language';

  @override
  String get asstLanguageKo => '한국어';

  @override
  String get asstLanguageEn => 'English';

  @override
  String get asstLanguageHint =>
      'The language the speaker talks in. Change the app language on the System screen.';

  @override
  String get asstVoice => 'Voice';

  @override
  String get asstVoiceNextTime => 'Changes from the next conversation';

  @override
  String get asstPurpose => 'Role';

  @override
  String get asstPurposeHint => 'Describe the assistant\'s role or tone';

  @override
  String get asstUnits => 'Units';

  @override
  String get asstUnitsMetric => 'Metric (°C, km)';

  @override
  String get asstUnitsImperial => 'Imperial (°F, mi)';

  @override
  String get asstPlace => 'Home area';

  @override
  String get asstPlaceBody =>
      'Used for weather and nearby searches. Only the area name is saved on the speaker, never coordinates.';

  @override
  String get asstPlaceField => 'Area';

  @override
  String get asstPlaceExample => 'e.g. Gangnam-gu, Seoul';

  @override
  String get asstUseCurrentLocation => 'Use current location';

  @override
  String get asstTimezone => 'Time zone';

  @override
  String get asstLocationFilled => 'Area and time zone filled in. Tap Save';

  @override
  String get asstLocationFilledOnlyPlace => 'Area filled in. Pick a time zone';

  @override
  String asstTimezoneUnsupported(String tz) {
    return 'The speaker doesn\'t know your phone\'s time zone ($tz). Pick the closest one.';
  }

  @override
  String get asstTimezoneUnknown =>
      'Couldn\'t read the phone\'s time zone. Pick the closest one.';

  @override
  String get asstTimezoneMore => 'Other time zones';

  @override
  String get asstLocationServiceOff => 'Location is turned off on this phone';

  @override
  String get asstLocationDenied =>
      'No location permission. Type the area instead';

  @override
  String get asstLocationDeniedForever =>
      'Location permission is off. Turn it on in Settings or type the area';

  @override
  String get asstOpenSettings => 'Settings';

  @override
  String get asstLocationUnavailable =>
      'Couldn\'t find your location. Type the area instead';

  @override
  String get asstWebSearch => 'Web search (weather, news)';

  @override
  String get asstDeviceControls => 'Device controls (volume, radio, memory)';

  @override
  String get asstAutoMemory => 'Remember things learned in conversation';

  @override
  String get asstMemories => 'Memories';

  @override
  String asstMemoryCount(int count) {
    return '$count';
  }

  @override
  String get asstSave => 'Save';

  @override
  String get asstSaved => 'Saved';

  @override
  String get asstDiscardTitle => 'Leave without saving?';

  @override
  String get asstDiscardBody => 'Your changes will be lost.';

  @override
  String get asstDiscard => 'Leave';

  @override
  String get asstNameEmpty => 'Enter a name';

  @override
  String asstTooLong(int max) {
    return 'Too long (max $max bytes)';
  }

  @override
  String asstBytes(int used, int max) {
    return '$used/$max bytes';
  }

  @override
  String get asstMemoriesNotice =>
      'What the assistant remembers. Deleted items are forgotten from the next conversation.';

  @override
  String get asstMemoriesEmpty => 'Nothing remembered yet';

  @override
  String get asstForget => 'Delete';

  @override
  String get asstForgetTitle => 'Delete this memory?';

  @override
  String get asstForgotten => 'Deleted';

  @override
  String get audioTitle => 'Audio & wake word';

  @override
  String get audioWakeEnabled => 'Wake word';

  @override
  String get audioWakeEnabledHint =>
      'When off, talk with the center button only (for TV time)';

  @override
  String get audioPhrase => 'Wake phrase';

  @override
  String get audioPhraseComputer => 'Computer';

  @override
  String get audioPhraseAlexa => 'Alexa';

  @override
  String get audioSensitivity => 'Sensitivity';

  @override
  String get audioSensitivityLow => 'Fewer false wakes';

  @override
  String get audioSensitivityHigh => 'Hears easily';

  @override
  String get audioAdvanced => 'Advanced';

  @override
  String get audioWakeGain => 'Wake input boost';

  @override
  String get audioWakeGainHint => 'Raise only if it misses you from afar';

  @override
  String audioWakeGainValue(int db) {
    return '+$db dB';
  }

  @override
  String get audioWakeTest => 'Detection test (60 s)';

  @override
  String audioWakeTestRunning(int seconds) {
    return 'Testing · $seconds s left';
  }

  @override
  String audioWakeTestHint(String phrase) {
    return 'Say “$phrase” a few times';
  }

  @override
  String audioWakeTestCount(int count) {
    return 'Detected $count times';
  }

  @override
  String audioWakeTestDone(int count) {
    return 'Detected $count times in 60 s';
  }

  @override
  String get audioVolume => 'Volume';

  @override
  String audioVolumeValue(int value, int max) {
    return '$value / $max';
  }

  @override
  String get audioDuck => 'Lower music while talking';

  @override
  String audioDb(int db) {
    return '$db dB';
  }

  @override
  String get audioMicGain => 'Mic gain';

  @override
  String get audioMicGainHint => 'Higher picks up quieter voices';

  @override
  String get audioAutoGain => 'Auto mic level';

  @override
  String get audioAutoGainHint => 'Adjusts gently to your voice level';

  @override
  String get audioTestTone => 'Speaker test tone';

  @override
  String get audioLed => 'LED brightness';

  @override
  String audioPercent(int value) {
    return '$value%';
  }

  @override
  String get appTitle => 'AI-PA';

  @override
  String get splashLoading => 'Loading speaker info…';

  @override
  String get settingsTheme => 'Appearance';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOk => 'OK';

  @override
  String get bleKey2Hint =>
      'Hold the speaker\'s middle button (Key2) for 3 seconds';

  @override
  String get errorUnknown => 'Something went wrong';

  @override
  String get errorNetwork => 'Can\'t reach the network';

  @override
  String get errorCache => 'Couldn\'t read data saved on this phone';

  @override
  String get errorDeviceUnreachable =>
      'Can\'t reach the speaker. Check that your phone and speaker are on the same Wi-Fi';

  @override
  String get errorDeviceUnauthorized =>
      'This phone was removed from the speaker. Register it again';

  @override
  String get errorDeviceRateLimited => 'Try again in a moment';

  @override
  String get errorDeviceTimeout => 'The speaker isn\'t responding';

  @override
  String get errorDeviceInvalidArg => 'The speaker rejected that value';

  @override
  String get errorDeviceBusy => 'The speaker is busy';

  @override
  String get errorDeviceStorage => 'The speaker couldn\'t save it';

  @override
  String get errorDeviceNoApiKey => 'No OpenAI key yet';

  @override
  String get errorDeviceNoWifi => 'The speaker isn\'t on Wi-Fi';

  @override
  String get errorDeviceVoiceActive => 'Not available during a conversation';

  @override
  String get errorDeviceNotFound => 'Not found';

  @override
  String get errorDeviceOtaTooLarge => 'The firmware file is too large';

  @override
  String get errorDeviceOtaSignature => 'The firmware signature doesn\'t match';

  @override
  String get errorBleAdapterOff => 'Turn on Bluetooth';

  @override
  String get errorBlePermission => 'Bluetooth permission is needed';

  @override
  String get errorBleNotFound =>
      'Speaker not found. Did you hold Key2 for 3 seconds?';

  @override
  String get errorBleConnect =>
      'Couldn\'t connect to the speaker over Bluetooth';

  @override
  String get errorBleDisconnected => 'Bluetooth disconnected';

  @override
  String get errorBleBondFailed =>
      'Pairing error. Remove the JARVIS device in Settings > Bluetooth and try again';

  @override
  String get errorBleProtocol => 'Error while talking to the speaker';

  @override
  String get errorBleTimeout => 'The speaker isn\'t responding over Bluetooth';

  @override
  String get errorBleWindowClosed =>
      'Setup time ran out. Hold Key2 for 3 seconds to reopen';

  @override
  String get errorBlePhonesFull =>
      'The speaker has the maximum number of phones';

  @override
  String get errorBleUnsupportedVersion =>
      'Update the app to the latest version';

  @override
  String get errorWifiAuth => 'Wrong Wi-Fi password';

  @override
  String get errorWifiNotFound => 'Couldn\'t find this Wi-Fi';

  @override
  String get errorWifiTimeout => 'Wi-Fi connection timed out';

  @override
  String get errorDeviceNotPlaying => 'Nothing is playing';

  @override
  String get errorDeviceNoTelegramToken =>
      'The speaker has no Telegram bot token yet';

  @override
  String get errorDeviceNotesFull =>
      'The speaker is full of notes (1,000). Delete old events or memos you no longer need';

  @override
  String get errorDeviceConflict =>
      'It was just changed on the speaker. Check the new version and edit again';

  @override
  String get engTitle => 'Korean teacher';

  @override
  String get engHomeSubtitle =>
      'Pronunciation · Basic · Everyday · Business · Advanced';

  @override
  String get engIntro =>
      'Pick a course and start free-talking in Korean with the speaker right away. The teacher corrects your phrasing and pronunciation as you talk.';

  @override
  String get engCoursePron => 'Pronunciation';

  @override
  String get engCoursePronDesc =>
      'Talk freely in Korean; mispronounced words get pointed out as you go';

  @override
  String get engCourseBasic => 'Basic conversation';

  @override
  String get engCourseBasicDesc =>
      'Easy everyday Korean, slowly. English help when you get stuck';

  @override
  String get engCourseDaily => 'Everyday conversation';

  @override
  String get engCourseDailyDesc =>
      'Natural Korean in situations like travel, restaurants, hospitals';

  @override
  String get engCourseBiz => 'Business conversation';

  @override
  String get engCourseBizDesc =>
      'Meetings, calls and negotiations in polite, honorific Korean';

  @override
  String get engCourseAdv => 'Advanced conversation';

  @override
  String get engCourseAdvDesc =>
      'Current affairs and opinions, Korean only, polished to sound natural';

  @override
  String get engLevelAll => 'All levels';

  @override
  String get engLevelBeginner => 'Beginner';

  @override
  String get engLevelEasy => 'Easy–mid';

  @override
  String get engLevelMid => 'Intermediate';

  @override
  String get engLevelAdvanced => 'Advanced';

  @override
  String get engExplain => 'Explanations';

  @override
  String get engExplainKorean => 'Korean only';

  @override
  String get engExplainEnglish => 'Mix in English';

  @override
  String get engSpeed => 'Speed';

  @override
  String get engSpeedSlow => 'Slow';

  @override
  String get engSpeedNormal => 'Normal';

  @override
  String get engLength => 'Length';

  @override
  String engMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String engStart(String course) {
    return 'Start $course free talk';
  }

  @override
  String get engVoiceHint => 'Or say: “Alexa, let\'s study Korean”';

  @override
  String get engCostNote =>
      'Lessons are up to 5 minutes. OpenAI voice charges apply for the lesson time.';

  @override
  String get engLessonTitle => 'Free talk';

  @override
  String engFreeTalk(String course) {
    return '$course · free talk';
  }

  @override
  String engRemaining(String time) {
    return '$time left';
  }

  @override
  String get engStarting => 'Starting the lesson…';

  @override
  String get engListening => 'Listening';

  @override
  String get engListeningBody =>
      'Talk to the speaker in Korean. Mistakes are fine; the teacher corrects you as you talk.';

  @override
  String get engTopic => 'Current topic';

  @override
  String get engTopicUnknown => 'The teacher is picking a topic';

  @override
  String get engChangeTopic => 'New topic';

  @override
  String get engCorrections => 'Corrections from your teacher';

  @override
  String get engCorrectionsEmpty =>
      'Corrections show up here (about every 45 seconds)';

  @override
  String get engPronunciationBadge => 'Sound';

  @override
  String get engEnd => 'End lesson';

  @override
  String get engSummarizing => 'Summarizing today\'s lesson…';

  @override
  String get engDoneTitle => 'Lesson finished';

  @override
  String engDoneMeta(String course, int minutes) {
    return '$course free talk · $minutes min';
  }

  @override
  String get engTodayCorrections => 'Corrected today';

  @override
  String get engNoCorrections => 'No corrections today. Well done!';

  @override
  String get engPractice => 'Words to practice saying';

  @override
  String get engNextTopic => 'Topic for next time';

  @override
  String get engAgain => 'Free talk again';

  @override
  String get engHome => 'Home';

  @override
  String get engLastLesson => 'Last lesson summary';

  @override
  String get engRealtimeNote =>
      'Korean lessons use the real-time API (OpenAI) · about ₩70 a minute';

  @override
  String get engNeedOpenAiKey =>
      'Korean lessons need an OpenAI key. Add it in Assistant > AI · Conversation mode.';

  @override
  String get homeTitle => 'Speaker';

  @override
  String get homeAddSpeaker => 'Add speaker';

  @override
  String get homeSelectSpeaker => 'Choose speaker';

  @override
  String get homeConnected => 'Connected';

  @override
  String get homeWifiGood => 'Strong Wi-Fi';

  @override
  String get homeWifiFair => 'Fair Wi-Fi';

  @override
  String get homeWifiWeak => 'Weak Wi-Fi';

  @override
  String get homeIdleTitle => 'Listening';

  @override
  String get homeIdleBody => 'Say “Alexa” or tap the button below';

  @override
  String get homeTalkingTitle => 'In conversation';

  @override
  String get homeTalkingBody =>
      'Ends by itself 60 seconds after you stop talking';

  @override
  String get homeConnectingTitle => 'Connecting…';

  @override
  String get homeStartTalk => 'Start talking';

  @override
  String get homeStopTalk => 'End conversation';

  @override
  String get homeNothingPlaying => 'Nothing playing';

  @override
  String get homeOpenRadio => 'Open radio';

  @override
  String get homeRadioPlaying => 'Radio · playing';

  @override
  String get homeRadioPaused => 'Radio · paused';

  @override
  String get homeRadioBuffering => 'Radio · connecting';

  @override
  String get homeVolume => 'Volume';

  @override
  String get homePrevious => 'Previous station';

  @override
  String get homeNext => 'Next station';

  @override
  String get homePause => 'Pause';

  @override
  String get homeResume => 'Play';

  @override
  String get homeStop => 'Stop';

  @override
  String get homeTelegram => 'Telegram';

  @override
  String homeTelegramUnread(int count) {
    return '$count new';
  }

  @override
  String get homeTelegramSetup => 'Set up';

  @override
  String get homeMenuRadio => 'Radio';

  @override
  String get homeMenuAssistant => 'Assistant';

  @override
  String get homeMenuAudio => 'Audio';

  @override
  String get homeMenuSystem => 'System';

  @override
  String get homeUnreachableTitle => 'Can\'t reach the speaker';

  @override
  String get homeUnreachableBody =>
      'Check that your phone and the speaker are on the same Wi-Fi.';

  @override
  String get homeFindAgain => 'Find again';

  @override
  String get homeUnauthorizedTitle => 'This phone was removed';

  @override
  String get homeUnauthorizedBody =>
      'Hold the speaker\'s middle button for 3 seconds, then register again.';

  @override
  String get homeRegisterAgain => 'Register again';

  @override
  String get homeEmptyTitle => 'No speaker yet';

  @override
  String get homeEmptyBody =>
      'Keep your phone close to the speaker and start. A new speaker shows up right away.';

  @override
  String get homeComingSoon => 'This screen is coming soon';

  @override
  String get homeRemoveFromPhone => 'Remove from this phone';

  @override
  String get notesTitle => 'Notes & schedule';

  @override
  String notesHomeToday(int count, String next) {
    return '$count today · $next';
  }

  @override
  String notesHomeTodayCount(int count) {
    return '$count events today';
  }

  @override
  String get notesHomeEmpty => 'See notes and events';

  @override
  String notesClockHour(int hour) {
    return '$hour o\'clock';
  }

  @override
  String notesClockHourMinute(int hour, String minute) {
    return '$hour:$minute';
  }

  @override
  String get notesSearchHint => 'Search notes and events';

  @override
  String get notesTabEvents => 'Events';

  @override
  String get notesTabMemos => 'Memos';

  @override
  String get notesTabTrash => 'Trash';

  @override
  String notesGroupToday(String date) {
    return 'Today · $date';
  }

  @override
  String notesGroupTomorrow(String date) {
    return 'Tomorrow · $date';
  }

  @override
  String get notesGroupThisWeek => 'This week';

  @override
  String get notesGroupLater => 'Later';

  @override
  String get notesGroupPast => 'Past events';

  @override
  String get notesAllDay => 'All day';

  @override
  String get notesBadgeScheduled => 'Reminder set';

  @override
  String get notesBadgeSent => 'Sent';

  @override
  String get notesBadgeAcked => 'Heard';

  @override
  String get notesBadgeNoAnswer => 'No answer';

  @override
  String get notesBadgeMissed => 'Missed';

  @override
  String get notesRemindLabel => 'Reminder';

  @override
  String get notesRemindNone => 'No reminder';

  @override
  String get notesRemindOnTime => 'At start time';

  @override
  String notesRemindSameDay(String time) {
    return 'Same day $time';
  }

  @override
  String notesRemindMinutes(int n) {
    return '$n min before';
  }

  @override
  String notesRemindHours(int n) {
    return '$n hr before';
  }

  @override
  String notesRemindHoursMinutes(int h, int m) {
    return '$h hr $m min before';
  }

  @override
  String get notesRemindDayBefore => '1 day before';

  @override
  String notesRemindDays(int n) {
    return '$n days before';
  }

  @override
  String get notesRemindCustom => 'Custom';

  @override
  String get notesRemindHintMany => 'You can pick several';

  @override
  String get notesRemindHintMax => 'Up to 3';

  @override
  String notesRemindSummary(String when) {
    return 'The speaker will tell you $when';
  }

  @override
  String get notesRemindOff =>
      'Event reminders are turned off in reminder settings';

  @override
  String get notesCustomTitle => 'How many minutes before?';

  @override
  String get notesCustomHelp => 'From 1 minute to 7 days (10080 minutes)';

  @override
  String get notesCustomUnit => 'min before';

  @override
  String get notesCustomAdd => 'Add';

  @override
  String get notesMemoToday => 'Today';

  @override
  String get notesMemoYesterday => 'Yesterday';

  @override
  String get notesTrashInfo => 'Notes deleted by voice stay here for 30 days.';

  @override
  String notesTrashLeft(int days) {
    return 'Deleted for good in $days days';
  }

  @override
  String get notesRestore => 'Restore';

  @override
  String get notesDeleteForever => 'Delete for good';

  @override
  String get notesVoiceHint =>
      'You can also say: “Alexa, add a hospital visit tomorrow at 3 and remind me an hour before” · “Alexa, make a memo to buy milk” · “Alexa, what\'s on tomorrow?”';

  @override
  String get notesPrivacy =>
      'When you search by voice or get a reminder, the note is sent to the OpenAI conversation. Notes are stored only on the speaker and phones.';

  @override
  String get notesNew => 'New';

  @override
  String get notesOffline => 'You can edit on your home Wi-Fi';

  @override
  String get notesOfflineBody => 'Showing the copy saved on this phone.';

  @override
  String get notesEmptyEvents => 'No events';

  @override
  String get notesEmptyMemos => 'No memos';

  @override
  String get notesEmptyTrash => 'Trash is empty';

  @override
  String get notesNoMatch => 'Nothing found';

  @override
  String get notesEditEvent => 'Edit event';

  @override
  String get notesEditMemo => 'Edit memo';

  @override
  String get notesNewEvent => 'New event';

  @override
  String get notesNewMemo => 'New memo';

  @override
  String get notesFieldTitle => 'Title';

  @override
  String get notesFieldBody => 'Details';

  @override
  String get notesTitleRequired => 'Please enter a title';

  @override
  String get notesEditHint =>
      'You can edit notes made by voice here too. Changes go to the speaker right away.';

  @override
  String get notesSave => 'Save';

  @override
  String get notesDelete => 'Delete';

  @override
  String notesDeleteTitle(String title) {
    return 'Delete “$title”?';
  }

  @override
  String get notesDeleteBody =>
      'It will be deleted from the speaker too and can\'t be restored. It will also disappear from other family phones.';

  @override
  String get notesDeleteAction => 'Delete';

  @override
  String get notesSaved => 'Saved';

  @override
  String get notesDeleted => 'Deleted';

  @override
  String get notesRestored => 'Restored';

  @override
  String get notesSettingsTitle => 'Event reminders';

  @override
  String get notesSettingsEnabled => 'Speaker tells you about events';

  @override
  String get notesSettingsEnabledSub => 'Also at night, at the time you set';

  @override
  String get notesSettingsDefaults =>
      'Default reminders · used when an event has none set';

  @override
  String get notesSettingsTimed => 'Events with a time';

  @override
  String get notesSettingsAllDay => 'All-day events';

  @override
  String get notesSettingsSameMorning => 'Morning of the day';

  @override
  String get notesSettingsDayBeforeMorning => 'Morning of the day before';

  @override
  String get notesSettingsAllDayTime => 'Reminder time';

  @override
  String get notesSettingsInfoTitle => 'Good to know';

  @override
  String get notesSettingsInfo =>
      'The speaker opens a short conversation to tell you. Each reminder costs a little OpenAI usage. Without internet, it plays a chime and shows an orange light.';

  @override
  String get provTitle => 'Speaker setup';

  @override
  String get provKeysTitle => 'Which AI should it use?';

  @override
  String get provKeysBody =>
      'Decide before connecting to the speaker. It\'s fine to leave the app to copy a key.';

  @override
  String get provOpenAiKey => 'OpenAI API key';

  @override
  String get provOpenAiKeyInvalid => 'Enter a key that starts with sk-';

  @override
  String get provTelegramToken => 'Telegram bot token';

  @override
  String get provOptional => '(optional)';

  @override
  String get provTelegramTokenHint =>
      'You can also add it later on the Telegram screen.';

  @override
  String get provTelegramTokenInvalid => 'This is not a 123456789:ABC… token';

  @override
  String get provPhoneName => 'This phone\'s name';

  @override
  String get provRemember => 'Remember keys on this phone';

  @override
  String get provRememberHint =>
      'Filled in next time. Stored encrypted in the phone\'s secure storage.';

  @override
  String get provPaste => 'Paste';

  @override
  String get provFindSpeaker => 'Find speaker';

  @override
  String get provScanTitle => 'Looking for nearby speakers';

  @override
  String get provScanHint =>
      'A new speaker shows up right away. For a speaker already set up, hold the middle button (Key2) for 3 seconds.';

  @override
  String provScanFound(int count) {
    return '$count found';
  }

  @override
  String get provScanNone => 'No speaker found yet';

  @override
  String get provScanAgain => 'Search again';

  @override
  String get provSignalNear => 'Very close';

  @override
  String get provSignalFar => 'Far away';

  @override
  String get provConnecting => 'Connecting to the speaker…';

  @override
  String get provWifiChoiceTitle => 'This speaker is already on Wi-Fi';

  @override
  String get provWifiChoiceBody =>
      'Keep it and we register right away without restarting.';

  @override
  String get provWifiKeep => 'Keep current Wi-Fi';

  @override
  String get provWifiChange => 'Change Wi-Fi';

  @override
  String get provWifiTitle => 'Choose the speaker\'s Wi-Fi';

  @override
  String get provWifiScanning => 'The speaker is scanning for Wi-Fi…';

  @override
  String get provWifiNote =>
      'The speaker supports 2.4 GHz Wi-Fi only. The speaker found this list itself.';

  @override
  String get provWifiOpen => 'Open';

  @override
  String get provWifiManual => 'Enter a Wi-Fi that\'s not listed';

  @override
  String get provWifiName => 'Wi-Fi name';

  @override
  String get provWifiPassword => 'Password';

  @override
  String provWifiPasswordTitle(String ssid) {
    return 'Password for $ssid';
  }

  @override
  String get provWifiShowPassword => 'Show password';

  @override
  String get provWifiConnect => 'Connect';

  @override
  String provWifiConnecting(String ssid) {
    return 'Connecting to $ssid… (up to 20 s)';
  }

  @override
  String get provWifiRescan => 'Scan again';

  @override
  String get provSending => 'Saving keys and registering this phone…';

  @override
  String get provPhonesFullTitle =>
      'The speaker has the maximum number of phones';

  @override
  String get provPhonesFullBody =>
      'Pick one to remove and this phone takes its place.';

  @override
  String get provPhonesFullAction => 'Remove and register this phone';

  @override
  String get provDiscovering =>
      'The speaker is restarting. Looking for it on your Wi-Fi…';

  @override
  String get provDoneTitle => 'All set';

  @override
  String get provDoneBody =>
      'When you hear “AI speaker is ready”, say “Alexa”.';

  @override
  String get provDoneWifi => 'Wi-Fi connected';

  @override
  String get provDoneKey => 'Keys saved';

  @override
  String get provDonePair => 'This phone registered';

  @override
  String provDoneFound(String host) {
    return 'Found the speaker on Wi-Fi ($host)';
  }

  @override
  String get provDoneNotFound =>
      'Not found on your Wi-Fi yet. You can search again from Home.';

  @override
  String get provGoHome => 'Go home';

  @override
  String get provFailedTitle => 'Setup didn\'t finish';

  @override
  String get provCancel => 'Cancel';

  @override
  String get provAiSection => '① AI';

  @override
  String get provRequired => '(required)';

  @override
  String get provKeyTyped =>
      'Key entered. It is sent to the speaker only over Bluetooth.';

  @override
  String get provKeyExistingHint =>
      'After connecting we check that the speaker has this key. If not, this AI can\'t be chosen.';

  @override
  String get provKeyRequiredHint => 'This AI needs a key.';

  @override
  String get provExistingKey =>
      'This speaker already has this AI\'s key (adding another phone)';

  @override
  String get provModeSection => '② Conversation mode';

  @override
  String get provModeLater => '(you can change it later in Assistant settings)';

  @override
  String provMore(String other) {
    return 'More (optional): $other key · Telegram token';
  }

  @override
  String provMoreOtherHint(String other) {
    return 'Add the $other key too and you can switch AI anytime later.';
  }

  @override
  String provKeyBlocked(String key) {
    return 'Enter the $key to continue';
  }

  @override
  String provMissingKey(String provider) {
    return 'This speaker has no $provider key. Enter the key or choose another AI.';
  }

  @override
  String get provMaybeNotReady => '(may not be ready yet on some speakers)';

  @override
  String provNotReady(String provider) {
    return 'This speaker can\'t use $provider yet (coming soon). Choose another AI, or update the speaker and try again.';
  }

  @override
  String get radioTitle => 'Radio';

  @override
  String get radioSearch => 'Find stations';

  @override
  String get radioEdit => 'Edit';

  @override
  String get radioPlaying => 'Playing';

  @override
  String get radioPaused => 'Paused';

  @override
  String get radioBuffering => 'Connecting';

  @override
  String get radioNothingPlaying => 'Nothing is playing';

  @override
  String get radioPickStation => 'Pick a station below';

  @override
  String get radioPlay => 'Play';

  @override
  String get radioPause => 'Pause';

  @override
  String get radioResume => 'Resume';

  @override
  String get radioStop => 'Stop';

  @override
  String get radioPrevious => 'Previous station';

  @override
  String get radioNext => 'Next station';

  @override
  String get radioGroupMusic => 'Music';

  @override
  String get radioGroupKorean => 'Korean music';

  @override
  String get radioGroupNews => 'News & business';

  @override
  String get radioGroupTalk => 'Talk';

  @override
  String get radioGroupOther => 'Other';

  @override
  String get radioEmpty =>
      'No saved stations yet. Use Find stations to add some';

  @override
  String get radioNotPlaying => 'No station is playing right now';

  @override
  String get radioEditTitle => 'Edit stations';

  @override
  String get radioEditHint => 'Drag to reorder. Save to update the speaker';

  @override
  String radioCount(int count, int max) {
    return '$count / $max';
  }

  @override
  String get radioSave => 'Save';

  @override
  String get radioSaved => 'Saved';

  @override
  String get radioAddCustom => 'Add by URL';

  @override
  String get radioRename => 'Rename';

  @override
  String get radioDelete => 'Delete';

  @override
  String radioDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get radioDiscardTitle => 'Discard your changes?';

  @override
  String get radioDiscard => 'Discard';

  @override
  String get radioFormName => 'Name';

  @override
  String get radioFormUrl => 'Stream URL';

  @override
  String get radioFormUrlHint =>
      'An MP3 or AAC stream starting with http:// or https://';

  @override
  String get radioFormGenre => 'Genre tags';

  @override
  String get radioFormGenreHint => 'Separate with commas (e.g. jazz,english)';

  @override
  String get radioFormAdd => 'Add';

  @override
  String radioErrTooMany(int max) {
    return 'You can save up to $max stations';
  }

  @override
  String get radioErrNameEmpty => 'Enter a name';

  @override
  String get radioErrNameTooLong => 'Name is too long (48 bytes max)';

  @override
  String get radioErrUrlInvalid => 'Only http:// or https:// URLs work';

  @override
  String get radioErrUrlTooLong => 'URL is too long (256 characters max)';

  @override
  String get radioErrGenreTooLong =>
      'Genre tags are too long (64 characters max)';

  @override
  String get radioErrTooLarge =>
      'The list is too large. Shorten some names or URLs';

  @override
  String get radioErrDuplicate => 'This station is already saved';

  @override
  String get radioSearchTitle => 'Find stations';

  @override
  String get radioSearchByName => 'Name';

  @override
  String get radioSearchByTag => 'Genre';

  @override
  String get radioSearchNameHint => 'Station name (e.g. BBC, jazz)';

  @override
  String get radioSearchTagHint => 'Genre tag (e.g. jazz, kpop, news)';

  @override
  String get radioSearchHlsNote =>
      'Korean broadcasters like KBS, MBC and SBS only stream in HLS, which the speaker can\'t play, so they don\'t appear';

  @override
  String get radioSearchIdle =>
      'Search by name or genre. Only stations the speaker can play are shown';

  @override
  String get radioSearchNoResults => 'No stations the speaker can play';

  @override
  String get radioSearchFailed =>
      'Couldn\'t get the station list. Check your internet connection';

  @override
  String get radioSearchAdd => 'Add';

  @override
  String get radioSearchAdded => 'Added';

  @override
  String get radioSearchPlayNow => 'Play now';

  @override
  String radioAdded(String name) {
    return 'Added $name';
  }

  @override
  String radioKbps(int kbps) {
    return '$kbps kbps';
  }

  @override
  String get sysTitle => 'System';

  @override
  String get sysFirmware => 'Firmware';

  @override
  String get sysUptime => 'Uptime';

  @override
  String get sysWifi => 'Wi-Fi signal';

  @override
  String sysWifiGood(int dbm) {
    return 'Good ($dbm dBm)';
  }

  @override
  String sysWifiFair(int dbm) {
    return 'Fair ($dbm dBm)';
  }

  @override
  String sysWifiWeak(int dbm) {
    return 'Weak ($dbm dBm)';
  }

  @override
  String get sysWifiNone => 'Not connected';

  @override
  String get sysIp => 'IP address';

  @override
  String sysUptimeDays(int days, int hours) {
    return '$days d $hours h';
  }

  @override
  String sysUptimeHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String sysUptimeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String sysPhonesTitle(int count, int max) {
    return 'Registered phones ($count / $max)';
  }

  @override
  String get sysPhoneSelf => 'This phone';

  @override
  String sysPhoneCreated(String date) {
    return 'Added $date';
  }

  @override
  String get sysPhoneRevoke => 'Revoke';

  @override
  String sysPhoneRevokeTitle(String name) {
    return 'Revoke $name?';
  }

  @override
  String get sysPhoneRevokeBody =>
      'That phone can no longer control the speaker. It has to register again to use it.';

  @override
  String get sysPhoneRevoked => 'Phone revoked';

  @override
  String get sysPhonesFailed => 'Couldn\'t load the phone list';

  @override
  String get sysMenuKeys => 'Keys';

  @override
  String get sysMenuKeysHint => 'OpenAI key, Telegram bot token';

  @override
  String get sysMenuApp => 'App settings';

  @override
  String get sysMenuAppHint => 'Theme, language';

  @override
  String get sysDiagnostics => 'Diagnostics';

  @override
  String get sysBuildDate => 'Build';

  @override
  String get sysResetReason => 'Last start reason';

  @override
  String get sysResetPowerOn => 'Power on';

  @override
  String get sysResetSoftware => 'Restart';

  @override
  String get sysResetCrash => 'Restarted after an error';

  @override
  String get sysResetWatchdog => 'Restarted after a hang';

  @override
  String get sysResetBrownout => 'Low power';

  @override
  String sysResetOther(int code) {
    return 'Other ($code)';
  }

  @override
  String get sysHeapFree => 'Internal RAM free';

  @override
  String get sysHeapMin => 'Internal RAM lowest';

  @override
  String get sysPsramFree => 'PSRAM free';

  @override
  String sysKb(int value) {
    return '$value KB';
  }

  @override
  String get sysFailures => 'Recent failures';

  @override
  String get sysNoFailures => 'None';

  @override
  String get sysReboot => 'Restart speaker';

  @override
  String get sysRebootTitle => 'Restart the speaker?';

  @override
  String get sysRebootBody =>
      'Playback stops and it reconnects in about 30 seconds.';

  @override
  String get sysRebootAction => 'Restart';

  @override
  String get sysRebooting => 'Restarting…';

  @override
  String get sysFactoryResetTitle => 'Factory reset';

  @override
  String get sysFactoryResetBody =>
      ' is done on the speaker. Hold the middle button for 10 seconds to erase all settings and registrations.';

  @override
  String get sysForget => 'Remove speaker from this phone';

  @override
  String get sysForgetTitle => 'Remove this speaker from this phone?';

  @override
  String get sysForgetBody =>
      'If the speaker is reachable, this phone\'s registration is revoked too. Otherwise it stays on the speaker; revoke it from another phone.';

  @override
  String get sysForgetAction => 'Remove';

  @override
  String get sysKeysTitle => 'Keys';

  @override
  String get sysKeysPhoneSection => 'Keys remembered on this phone';

  @override
  String get sysKeysPhoneHint =>
      'Filled in when you set up a speaker. Stored encrypted in the phone\'s secure storage.';

  @override
  String get sysKeysSpeakerSection => 'Keys on the speaker';

  @override
  String get sysKeysSpeakerHint =>
      'Keys are sent over Bluetooth only. Stay near the speaker.';

  @override
  String get sysKeyOpenAi => 'OpenAI API key';

  @override
  String get sysKeyTelegram => 'Telegram bot token';

  @override
  String get sysKeySaved => 'Saved';

  @override
  String get sysKeyNotSaved => 'Not set';

  @override
  String get sysKeyUnknown => 'Unknown';

  @override
  String get sysKeyForget => 'Delete';

  @override
  String get sysKeyForgetTitle => 'Delete this key from the phone?';

  @override
  String get sysKeyForgetBody => 'The key on the speaker stays.';

  @override
  String get sysKeyReplace => 'Replace';

  @override
  String get sysKeyAdd => 'Add';

  @override
  String get sysKeyDelete => 'Delete';

  @override
  String get sysKeyDeleteTitle => 'Delete this key from the speaker?';

  @override
  String get sysKeyDeleteBodyOpenAi =>
      'If the speaker uses OpenAI, it can\'t talk. Korean lessons also stop working.';

  @override
  String get sysKeyDeleteBodyTelegram => 'Telegram messages stop arriving.';

  @override
  String get sysKeyDeleted => 'Deleted from the speaker';

  @override
  String get sysKeySend => 'Send to speaker';

  @override
  String get sysKeySending => 'Finding the speaker and sending…';

  @override
  String get sysKeySent => 'Saved on the speaker';

  @override
  String get sysKeyInvalidOpenAi => 'Enter a key that starts with sk-';

  @override
  String get sysKeyInvalidTelegram => 'This is not a 123456789:ABC… token';

  @override
  String get sysPaste => 'Paste';

  @override
  String get sysAppTitle => 'App settings';

  @override
  String get sysAppHint => 'Applies to this phone only.';

  @override
  String get sysLanguageSystem => 'Use phone language';

  @override
  String get sysLanguageKo => '한국어';

  @override
  String get sysLanguageEn => 'English';

  @override
  String get sysKeyGemini => 'Gemini API key';

  @override
  String get sysKeyDeleteBodyGemini =>
      'If the speaker uses Gemini, it can\'t talk.';

  @override
  String get sysKeyInvalidGemini =>
      'A Gemini key starts with AIza and has only letters, digits, - and _ (check nothing like :wq got pasted at the end)';

  @override
  String get tgTitle => 'Telegram';

  @override
  String get tgConnectTitle => 'Connect Telegram';

  @override
  String get tgStep1Title => 'Create a bot and get its token';

  @override
  String get tgStep1Body =>
      'Send /newbot to BotFather to create a bot just for this speaker, then copy the token.';

  @override
  String get tgOpenBotFather => 'Open BotFather';

  @override
  String get tgStep2Title => 'Check the token and save it to the speaker';

  @override
  String get tgTokenLabel => 'Bot token';

  @override
  String get tgTokenShow => 'Show token';

  @override
  String get tgTokenHide => 'Hide token';

  @override
  String get tgCheckToken => 'Check token';

  @override
  String get tgTokenChecking => 'Checking…';

  @override
  String tgTokenValid(String bot) {
    return '@$bot verified';
  }

  @override
  String tgTokenSaved(String bot) {
    return '@$bot verified · saved to the speaker';
  }

  @override
  String get tgTokenInvalid =>
      'That token doesn\'t work. Paste the token exactly as BotFather gave it';

  @override
  String get tgTokenNetwork =>
      'Can\'t reach Telegram. Check your internet connection';

  @override
  String get tgKey2Body =>
      'The token goes to the speaker over Bluetooth only, never over Wi-Fi.';

  @override
  String get tgSaveToSpeaker => 'Save to speaker';

  @override
  String get tgSaving => 'Finding the speaker and saving…';

  @override
  String get tgStep3Title => 'Register a family chat';

  @override
  String get tgPairBody =>
      'In the chat you want to add (private or family group), send this to the bot.';

  @override
  String tgPairGroupHint(String bot, String code) {
    return 'In a group: /pair@$bot $code';
  }

  @override
  String tgPairRemaining(int min, int sec) {
    return '${min}m ${sec}s left · works only once';
  }

  @override
  String get tgCopy => 'Copy';

  @override
  String get tgCopied => 'Copied';

  @override
  String get tgOpenTelegram => 'Open Telegram';

  @override
  String get tgOpenFailed => 'Couldn\'t open Telegram';

  @override
  String get tgPairWaiting => 'Waiting for the chat…';

  @override
  String get tgPairExpired => 'The code expired. Get a new one';

  @override
  String get tgPairNewCode => 'Get a new code';

  @override
  String get tgPairGetCode => 'Get a code';

  @override
  String get tgPairLocked => 'Save the token to the speaker to get a code';

  @override
  String get tgPairNoToken =>
      'The speaker has no bot token yet. Save the token first';

  @override
  String tgPaired(String name) {
    return 'Added the chat “$name”';
  }

  @override
  String get tgDone => 'Done';

  @override
  String get tgAddAnother => 'Add another chat';

  @override
  String get tgAddChatTitle => 'Add a chat';

  @override
  String get tgReplaceToken => 'Change token';

  @override
  String get tgStateOk => 'Connected';

  @override
  String get tgStateConnecting => 'Connecting';

  @override
  String get tgStateOff => 'Not connected';

  @override
  String get tgStateConflict => 'The bot is in use elsewhere';

  @override
  String get tgStateConflictBody =>
      'If another program uses the same bot, the speaker can\'t get messages. Create a bot just for this speaker and change the token.';

  @override
  String get tgStateTokenInvalid => 'The token doesn\'t work';

  @override
  String get tgStateTokenInvalidBody =>
      'The bot token was changed or revoked. Enter a new token.';

  @override
  String tgUnread(int count) {
    return '$count unread';
  }

  @override
  String get tgChatsTitle => 'Registered chats';

  @override
  String get tgAddChat => '+ Add';

  @override
  String get tgChatsEmpty =>
      'No chats yet. Tap “+ Add” to register a family chat.';

  @override
  String get tgChatsHint =>
      'Call chats by their alias, like “Tell Mom I\'ll be late.”';

  @override
  String get tgChatPrivate => 'Private chat';

  @override
  String get tgChatGroup => 'Group';

  @override
  String get tgChatChannel => 'Channel';

  @override
  String tgRenameLabel(String alias) {
    return 'Rename $alias';
  }

  @override
  String tgDeleteLabel(String alias) {
    return 'Delete $alias';
  }

  @override
  String get tgRenameTitle => 'Change alias';

  @override
  String get tgAliasHelp => 'The name you say to the speaker';

  @override
  String get tgAliasEmpty => 'Enter an alias';

  @override
  String get tgAliasTooLong => 'Too long (up to 32 letters)';

  @override
  String get tgSave => 'Save';

  @override
  String tgDeleteTitle(String alias) {
    return 'Delete “$alias”?';
  }

  @override
  String get tgDeleteBody =>
      'The speaker will stop getting messages from this chat. You\'ll need a new code to add it again.';

  @override
  String get tgDeleteAction => 'Delete';

  @override
  String get tgNotifyTitle => 'Message alerts';

  @override
  String get tgAutoRead => 'Read new messages aloud';

  @override
  String get tgAutoReadBody =>
      'When off, you hear a chime and can say “Read my messages”';

  @override
  String get tgQuietHours => 'Quiet hours';

  @override
  String get tgQuietStart => 'Start';

  @override
  String get tgQuietEnd => 'End';
}
