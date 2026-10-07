/// XAUUSD trading-session calendar (methodology §17).
///
/// Gold spot runs from **Sunday 18:00 New York to Friday 17:00 New York**.
/// Outside that window the market is closed, and the correct answer is "no
/// trade" rather than a setup evaluated against a stale last bar.
///
/// # Why this lives in the engine
///
/// The UI must not claim a market is live when it is closed, and the scanner
/// must not evaluate setups outside the session. Both need the same rule, so it
/// lives here as pure logic rather than being reimplemented in the app.
///
/// # DST
///
/// New York is UTC-5 (EST) or UTC-4 (EDT), and the offset switches at 02:00
/// **local** time: 07:00 UTC in March, 06:00 UTC in November. A fixed -4h
/// offset is wrong for roughly eight months of the year, which would open the
/// gate an hour early in winter and shut it an hour late.
library;

/// US daylight saving: second Sunday in March to first Sunday in November.
const _est = Duration(hours: 5);
const _edt = Duration(hours: 4);

/// Converts [utc] to New York wall-clock time.
DateTime newYorkTime(DateTime utc) {
  final dstStart = _transitionUtc(utc.year, 3, 2);
  final dstEnd = _transitionUtc(utc.year, 11, 1);
  final isSummer = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return utc.subtract(isSummer ? _edt : _est);
}

/// The UTC instant of the [nth] Sunday of [month] at the local 02:00 DST flip.
///
/// Spring flips at 02:00 standard (07:00 UTC); autumn at 02:00 daylight
/// (06:00 UTC).
DateTime _transitionUtc(int year, int month, int nth) {
  var day = DateTime.utc(year, month, 1);
  while (day.weekday != DateTime.sunday) {
    day = day.add(const Duration(days: 1));
  }
  final sunday = day.add(Duration(days: (nth - 1) * 7));
  final localOffset = month == 3 ? _est : _edt;
  return sunday.add(const Duration(hours: 2) + localOffset);
}

/// Whether the XAUUSD spot market is open at [utc].
bool isSessionOpen(DateTime utc) {
  final ny = newYorkTime(utc);
  // Daily trading halt, 17:00-18:00 New York (rollover). The venue publishes no
  // tradable quotes in this hour. Weekend logic alone would call midweek 17:xx
  // open - on 2026-10-06 the header showed a live "LATE US" pill at 17:30 New
  // York while the market was halted. The hour check comes first so it applies
  // uniformly: Friday 17:xx was already shut by the 17:00 close, Sunday 17:xx
  // by the 18:00 open, and midweek had no rule at all until this one.
  if (ny.hour == 17) return false;
  switch (ny.weekday) {
    case DateTime.saturday:
      return false;
    case DateTime.sunday:
      return ny.hour >= 18;
    case DateTime.friday:
      return ny.hour < 17;
    default:
      return true;
  }
}

/// A coarse session label for display.
///
/// Deliberately coarse: it names the phase rather than implying a precise
/// clock, so the UI never promises a level of precision it does not have.
enum MarketSession { closed, asia, europe, us, lateUs }

/// Classifies the session at [utc].
MarketSession sessionAt(DateTime utc) {
  if (!isSessionOpen(utc)) return MarketSession.closed;
  final ny = newYorkTime(utc);
  final minuteOfDay = ny.hour * 60 + ny.minute;

  // 18:00 Sun -> 03:00 Mon is Asia in New York terms.
  final asiaStart = 18 * 60;
  final europeStart = 3 * 60;
  final usStart = 8 * 60;
  final lateUsStart = 12 * 60;

  if (minuteOfDay < europeStart || minuteOfDay >= asiaStart) return MarketSession.asia;
  if (minuteOfDay < usStart) return MarketSession.europe;
  if (minuteOfDay < lateUsStart) return MarketSession.us;
  return MarketSession.lateUs;
}

/// Why the market is closed, for honest labelling.
///
/// A trader reading "closed for the weekend" on a Tuesday evening has been
/// misled about when to come back - and "reopens in 30 minutes" next to a
/// weekend message is a contradiction on screen. The two closures mean
/// different waits, so they get different words.
enum MarketClosure { weekend, dailyHalt }

/// The reason the market is closed at [utc], or null when it is open.
MarketClosure? closureAt(DateTime utc) {
  if (isSessionOpen(utc)) return null;
  final ny = newYorkTime(utc);
  // The halt only reads as a halt on Monday-Thursday evenings. Friday 17:xx is
  // already the weekend (closed since 17:00), and Sunday 17:xx is still the
  // weekend (opens 18:00) - calling either "a 30-minute break" would lie about
  // the wait.
  final isMidweek =
      ny.weekday >= DateTime.monday && ny.weekday <= DateTime.thursday;
  if (isMidweek && ny.hour == 17) return MarketClosure.dailyHalt;
  return MarketClosure.weekend;
}

/// Short label for the header, e.g. `CLOSED`, `US`, `ASIA`.
String sessionLabel(MarketSession s) => switch (s) {
      MarketSession.closed => 'CLOSED',
      MarketSession.asia => 'ASIA',
      MarketSession.europe => 'EUROPE',
      MarketSession.us => 'US',
      MarketSession.lateUs => 'LATE US',
    };

/// Start of the trading day that contains [utc], as a UTC instant.
///
/// A gold "day" runs 18:00 New York to 17:00 New York (then the halt). The
/// Radar range must bound exactly this window: an unbounded trailing-N-rows
/// read once printed a 4-hour min/max as the day's range, and a UTC-midnight
/// cut would donate the 18:00-00:00 UTC stretch to the wrong day. Built purely
/// from UTC instants (never local-zone fields): 18:00 New York is 22:00 UTC
/// in daylight time and 23:00 UTC in standard time, exactly one of which
/// reads back as 18:00 — the DST flips happen at 02:00 local, never here.
DateTime sessionStartUtc(DateTime utc) {
  final ny = newYorkTime(utc);
  var day = DateTime.utc(ny.year, ny.month, ny.day);
  if (ny.hour < 18) day = day.subtract(const Duration(days: 1));
  final edt = DateTime.utc(day.year, day.month, day.day, 22);
  if (newYorkTime(edt).hour == 18) return edt;
  return DateTime.utc(day.year, day.month, day.day, 23);
}

/// When the market next opens, or null when already open.
///
/// Used by the UI to tell a trader when to look back rather than leaving them
/// staring at a closed market.
///
/// The coarse 15-minute sweep finds the first open point, then a 1-minute
/// refinement walks forward to the actual boundary. Without the refinement the
/// returned instant rides on a grid anchored to *now*: every probe advances
/// with the clock, so the reported wait stays pinned - during the daily halt
/// it read a constant ~30:00, then ~15:00, a countdown that never counts. The
/// reopen instant must be a fixed wall-clock time for the UI countdown to move.
DateTime? nextOpenUtc(DateTime utc) {
  if (isSessionOpen(utc)) return null;
  const coarse = Duration(minutes: 15);
  var probe = utc.add(coarse);
  // 4 days covers the longest closed stretch (Saturday) at 15-minute steps.
  DateTime? firstOpen;
  for (var i = 0; i < 4 * 24 * 4; i++) {
    if (isSessionOpen(probe)) {
      firstOpen = probe;
      break;
    }
    probe = probe.add(coarse);
  }
  if (firstOpen == null) return null;
  // Refine: the boundary lies inside the last coarse step. Walk forward from
  // its start at 1-minute resolution so the answer is the transition itself,
  // not the grid point after it.
  //
  // Truncated to the minute, not the caller's seconds. Session boundaries fall
  // exactly on minute transitions (the rules only read hour and minute), so
  // the transition instant carries no seconds - but a candidate built from
  // DateTime.now() does, and those seconds ride along into the answer. On
  // 2026-10-07 the countdown read a constant 02:59 across screenshots 13s
  // apart: reopen-now was always exactly 180.0s because the seconds of the
  // answer tracked the seconds of the question. A wall-clock instant must not
  // depend on when it was asked.
  DateTime trunc(DateTime dt) =>
      DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute);
  var candidate = trunc(firstOpen.subtract(coarse));
  if (isSessionOpen(candidate)) return candidate;
  for (var i = 0; i < 16; i++) {
    candidate = candidate.add(const Duration(minutes: 1));
    if (isSessionOpen(candidate)) return candidate;
  }
  return trunc(firstOpen);
}