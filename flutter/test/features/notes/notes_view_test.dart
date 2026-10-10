import 'package:aispeaker/features/notes/domain/entities/note.dart';
import 'package:aispeaker/features/notes/domain/notes_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-10-04 (Sun) 13:00
final now = DateTime(2026, 10, 4, 13);

Note ev(String id, NoteTime start,
        {List<int> remind = const [60],
        List<int> reminded = const [],
        List<int> missed = const [],
        NoteAlert? alert,
        DateTime? snoozeAt,
        NoteState state = NoteState.active}) =>
    Note(
        id: id,
        kind: NoteKind.event,
        title: id,
        start: start,
        remind: remind,
        reminded: reminded,
        missed: missed,
        alert: alert,
        snoozeAt: snoozeAt,
        state: state);

NoteTime at(int d, int h, [int m = 0]) => NoteTime.at(DateTime(2026, 10, d, h, m));
NoteTime day(int d) => NoteTime.date(DateTime(2026, 10, d));

void main() {
  group('groupEvents', () {
    test('오늘 · 내일 · 이번 주 · 나중 · 지난 일정, 날짜순 (같은 날은 하루 종일 먼저)', () {
      final notes = [
        ev('later', at(20, 10)),
        ev('today15', at(4, 15)),
        ev('todayAllDay', day(4)),
        ev('today9', at(4, 9)),
        ev('tomorrow', day(5)),
        ev('week', at(10, 10)),
        ev('past1', at(1, 10)),
        ev('past3', at(3, 10)),
        ev('trashed', at(4, 10), state: NoteState.trash),
        const Note(id: 'memo'),
      ];
      final groups = groupEvents(notes, now);
      expect(groups.map((g) => g.kind), EventGroupKind.values);
      expect(groups[0].items.map((n) => n.id), ['todayAllDay', 'today9', 'today15']);
      expect(groups[0].day, DateTime(2026, 10, 4));
      expect(groups[1].day, DateTime(2026, 10, 5));
      expect(groups[2].items.single.id, 'week');
      expect(groups[3].items.single.id, 'later');
      expect(groups[4].items.map((n) => n.id), ['past3', 'past1'], reason: '지난 일정은 최근 것부터');
    });

    test('빈 묶음은 빼고, 이번 주는 7일 안까지', () {
      final groups = groupEvents([ev('d10', at(10, 9)), ev('d11', at(11, 9))], now);
      expect(groups.map((g) => g.kind), [EventGroupKind.thisWeek, EventGroupKind.later]);
    });
  });

  test('찾기: 대소문자·띄어쓰기 무시, 제목·내용', () {
    const n = Note(id: '1', title: '병원 (정형외과)', body: 'Insurance Card');
    expect(matchesQuery(n, '정형 외과'), isTrue);
    expect(matchesQuery(n, 'insurancecard'), isTrue);
    expect(matchesQuery(n, '치과'), isFalse);
    expect(matchesQuery(n, '  '), isTrue);
  });

  test('메모는 최근 수정순, 휴지통은 남은 날', () {
    final memos = sortedMemos([
      Note(id: 'old', updated: DateTime(2026, 10, 1)),
      Note(id: 'new', updated: DateTime(2026, 10, 4)),
      Note(id: 'trash', updated: DateTime(2026, 10, 5), state: NoteState.trash),
    ]);
    expect(memos.map((n) => n.id), ['new', 'old']);
    expect(trashDaysLeft(Note(id: 't', updated: DateTime(2026, 10, 3, 13)), now), 29);
    expect(trashDaysLeft(Note(id: 't', updated: DateTime(2026, 8, 1)), now), 0);
  });

  group('badgeOf', () {
    const nine = ClockTime.morning;

    test('앞으로 울릴 알림이 있으면 알림 예정', () {
      expect(badgeOf(ev('a', at(4, 15), remind: [60]), now, nine), NoteBadge.scheduled);
    });

    test('알림이 없거나 다 지났으면 표시 없음', () {
      expect(badgeOf(ev('a', at(4, 15), remind: []), now, nine), NoteBadge.none);
      expect(badgeOf(ev('a', at(4, 13, 30), remind: [60]), now, nine), NoteBadge.none);
    });

    test('최근 알림 결과: 확인됨·대답 없음·보냄·놓침', () {
      final recent = now.subtract(const Duration(minutes: 30));
      for (final (status, badge) in [
        (AlertStatus.acked, NoteBadge.acked),
        (AlertStatus.noAnswer, NoteBadge.noAnswer),
        (AlertStatus.sent, NoteBadge.sent),
        (AlertStatus.missed, NoteBadge.missed),
      ]) {
        final n = ev('a', at(4, 15), remind: [1440, 60], reminded: [1440], alert: NoteAlert(offset: 1440, status: status, at: recent));
        expect(badgeOf(n, now, nine), badge);
      }
    });

    test('오래된 결과보다 다음 알림 예정이 먼저', () {
      final n = ev('a', at(5, 15),
          remind: [1440 * 2, 60],
          reminded: [1440 * 2],
          alert: NoteAlert(offset: 2880, status: AlertStatus.acked, at: now.subtract(const Duration(days: 1))));
      expect(badgeOf(n, now, nine), NoteBadge.scheduled);
    });

    test('놓친 알림만 남으면 놓침, "나중에 다시"가 남았으면 알림 예정', () {
      expect(badgeOf(ev('a', at(4, 12), remind: [60], missed: [60]), now, nine), NoteBadge.missed);
      expect(badgeOf(ev('a', at(4, 12), remind: [], snoozeAt: now.add(const Duration(minutes: 5))), now, nine),
          NoteBadge.scheduled);
    });

    test('하루 종일 일정은 알림 시각(기본 9시) 기준', () {
      // All day tomorrow: 0 = tomorrow 9:00 (upcoming), 1440 = today 9:00 (past)
      expect(ev('a', day(5), remind: [0]).pendingReminders(now, nine), [0]);
      expect(ev('a', day(5), remind: [1440]).pendingReminders(now, nine), isEmpty);
      expect(ev('a', day(5), remind: [1440]).pendingReminders(now, const ClockTime(18, 0)), [1440]);
    });
  });

  group('toggleRemind (알림 칩)', () {
    test('넣고 빼기, 이른 알림부터 정렬', () {
      expect(toggleRemind([60], 1440), [1440, 60]);
      expect(toggleRemind([1440, 60], 60), [1440]);
    });

    test('최대 3개: 넘으면 그대로', () {
      final full = toggleRemind(toggleRemind([60], 10), 30);
      expect(full, [60, 30, 10]);
      expect(toggleRemind(full, 120), full);
      expect(toggleRemind(full, 30), [60, 10], reason: '가득 차도 빼기는 된다');
    });

    test('범위 밖(0–10080)은 넣지 않는다', () {
      expect(toggleRemind([], 10081), isEmpty);
      expect(toggleRemind([], -1), isEmpty);
    });
  });

  test('홈 요약: 오늘 일정 수와 다음 일정', () {
    final notes = [ev('아침', at(4, 9)), ev('병원', at(4, 15)), ev('생일', day(4)), ev('내일', at(5, 9))];
    final s = todaySummary(notes, now);
    expect(s.count, 3);
    expect(s.next?.id, '병원');
    final done = todaySummary([ev('아침', at(4, 9))], now);
    expect(done.next?.id, '아침', reason: '다 지났으면 오늘 첫 일정');
    expect(todaySummary(const [], now).next, isNull);
  });
}
