import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

DateTime utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

void main() {
  group('New York conversion honours US DST', () {
    // 2026: DST starts 8 March, ends 1 November.
    test('winter uses EST (-5)', () {
      expect(newYorkTime(utc(2026, 1, 15, 17)), utc(2026, 1, 15, 12));
    });

    test('summer uses EDT (-4)', () {
      expect(newYorkTime(utc(2026, 7, 15, 16)), utc(2026, 7, 15, 12));
    });

    test('spring forward skips the 02:00 local hour', () {
      final before = newYorkTime(utc(2026, 3, 8, 6, 59));
      final after = newYorkTime(utc(2026, 3, 8, 7, 0));
      expect(before, utc(2026, 3, 8, 1, 59));
      expect(after, utc(2026, 3, 8, 3, 0));
      // One minute of UTC advances the wall clock by 1h01m.
      expect(after.difference(before), const Duration(hours: 1, minutes: 1));
    });

    test('autumn repeats the 01:00 local hour', () {
      // Both instants map to 01:30, the observable signature of fall-back.
      expect(newYorkTime(utc(2026, 11, 1, 5, 30)), utc(2026, 11, 1, 1, 30));
      expect(newYorkTime(utc(2026, 11, 1, 6, 30)), utc(2026, 11, 1, 1, 30));
      expect(newYorkTime(utc(2026, 11, 1, 7, 30)), utc(2026, 11, 1, 2, 30));
    });
  });

  group('session boundaries are New York, not UTC', () {
    test('Saturday is always closed', () {
      expect(isSessionOpen(utc(2026, 1, 10, 15)), isFalse);
      expect(isSessionOpen(utc(2026, 7, 11, 15)), isFalse);
    });

    test('Sunday opens at 18:00 New York', () {
      // Winter: 22:00 UTC is 17:00 EST, still shut.
      expect(isSessionOpen(utc(2026, 1, 11, 22)), isFalse);
      expect(isSessionOpen(utc(2026, 1, 11, 23)), isTrue);
      // Summer: 22:00 UTC is 18:00 EDT, already open.
      expect(isSessionOpen(utc(2026, 7, 12, 22)), isTrue);
    });

    test('Friday closes at 17:00 New York', () {
      // Winter: 21:00 UTC is 16:00 EST, still open.
      expect(isSessionOpen(utc(2026, 1, 9, 21)), isTrue);
      expect(isSessionOpen(utc(2026, 1, 9, 22)), isFalse);
      // Summer: 20:00 UTC is 16:00 EDT, still open.
      expect(isSessionOpen(utc(2026, 7, 10, 20)), isTrue);
      expect(isSessionOpen(utc(2026, 7, 10, 21)), isFalse);
    });

    test('midweek is open in both seasons', () {
      expect(isSessionOpen(utc(2026, 1, 14, 15)), isTrue);
      expect(isSessionOpen(utc(2026, 7, 15, 15)), isTrue);
    });
  });

  group('session labelling', () {
    test('a closed weekend is labelled CLOSED', () {
      expect(sessionLabel(sessionAt(utc(2026, 1, 10, 12))), 'CLOSED');
      expect(sessionAt(utc(2026, 1, 10, 12)), MarketSession.closed);
    });

    test('open phases are named, never "LIVE"', () {
      // 13:00 UTC in July = 09:00 EDT, the US session.
      expect(sessionLabel(sessionAt(utc(2026, 7, 15, 13))), 'US');
      // 20:00 UTC in July = 16:00 EDT, still the US day.
      expect(sessionAt(utc(2026, 7, 15, 20)), MarketSession.lateUs);
      // 23:30 UTC in July = 19:30 EDT, which is the next session's Asia hours,
      // so the label rolls over rather than calling it "late US".
      expect(sessionAt(utc(2026, 7, 16, 1)), MarketSession.asia);
      // 10:00 UTC in July = 06:00 EDT, Europe.
      expect(sessionLabel(sessionAt(utc(2026, 7, 15, 10))), 'EUROPE');
    });

    test('no label ever claims the market is live', () {
      // Regression: the header used a hardcoded "LIVE" literal, which claimed
      // a live market while it was shut.
      for (var d = 0; d < 7; d++) {
        for (var h = 0; h < 24; h++) {
          final label = sessionLabel(sessionAt(utc(2026, 10, 1 + d, h)));
          expect(label, isNot(contains('LIVE')));
        }
      }
    });
  });

  group('next open', () {
    test('null while the market is already open', () {
      expect(nextOpenUtc(utc(2026, 7, 15, 13)), isNull);
    });

    test('Saturday points at the Sunday 18:00 New York open', () {
      final next = nextOpenUtc(utc(2026, 1, 10, 12))!;
      expect(isSessionOpen(next), isTrue);
      expect(newYorkTime(next).weekday, DateTime.sunday);
      expect(newYorkTime(next).hour, greaterThanOrEqualTo(18));
      // It must be in the future, not the instant we asked about.
      expect(next.isAfter(utc(2026, 1, 10, 12)), isTrue);
    });

    test('Friday close points at the Sunday open', () {
      final next = nextOpenUtc(utc(2026, 1, 9, 23))!;
      expect(isSessionOpen(next), isTrue);
      expect(newYorkTime(next).weekday, DateTime.sunday);
    });
  });
}