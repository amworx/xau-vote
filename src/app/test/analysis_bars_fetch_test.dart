import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xau_core/xau_core.dart';

import 'package:xauvote/data/live_repository.dart';

/// Regression guard for the stale-bar bug.
///
/// `analysisBars` used to make ONE request covering every timeframe, ordered by
/// `open_time` ASCENDING and with no limit. Supabase caps a PostgREST response
/// at 1000 rows, so the cap kept the OLDEST 1000 rows of the whole table and
/// discarded every recent bar. With ~2,800 rows present, all four timeframes were
/// truncated at the same instant and the app analysed bars about four days stale
/// while displaying them as live. Nothing errored.
///
/// The fix is one request per timeframe ordered DESCENDING with a per-timeframe
/// limit. Most of that is query shape, which cannot be exercised without a
/// network, so these tests cover what is reachable: the timeframe spelling, the
/// row-cap guard, and a source-level assertion that the ordering stays DESCENDING
/// and stays per-timeframe. That last one is unusual as a test and deliberate: the
/// bug it guards produced no runtime error at all, so the only way to catch its
/// return is to read the code that causes it.
void main() {
  group('dbTf', () {
    test('uses the spelling market_bars actually stores', () {
      // Tf.m15 is `m15` as an enum name but `15m` in the database. Getting this
      // wrong returns an empty series, not an error, so it fails silently.
      expect(LiveRepository.dbTf(Tf.m5), '5m');
      expect(LiveRepository.dbTf(Tf.m15), '15m');
      expect(LiveRepository.dbTf(Tf.m30), '30m');
      expect(LiveRepository.dbTf(Tf.h1), '1h');
    });
  });

  group('validateBarLimit', () {
    test('accepts a limit at the server cap', () {
      expect(() => LiveRepository.validateBarLimit(1000), returnsNormally);
    });

    test('accepts the default window', () {
      expect(() => LiveRepository.validateBarLimit(600), returnsNormally);
    });

    test('rejects a limit above the cap rather than silently truncating', () {
      // This is the whole point. A too-large limit returns a short response with
      // no error, which is precisely how the original bug stayed invisible.
      expect(
        () => LiveRepository.validateBarLimit(1001),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => LiveRepository.validateBarLimit(6000), throwsA(isA<ArgumentError>()));
    });

    test('the cap constant is 1000, matching observed server behaviour', () {
      expect(LiveRepository.postgrestRowCap, 1000);
    });
  });

  group('analysisBars query shape', () {
    late String source;

    setUpAll(() {
      source = File('lib/data/live_repository.dart').readAsStringSync();
    });

    test('fetches each timeframe as its own filtered request', () {
      // A single unfiltered request across all timeframes is the original bug:
      // the row cap then slices the whole table rather than one series.
      expect(
        source,
        contains(".eq('timeframe', dbTf(tf))"),
        reason: 'each timeframe must be requested separately',
      );
      expect(
        source,
        contains('.limit(maxPerTimeframe)'),
        reason: 'each request must be explicitly bounded',
      );
    });

    test('orders newest first so a cap cannot drop the recent tail', () {
      expect(
        source,
        contains(".order('open_time', ascending: false)"),
        reason:
            'DESCENDING ordering is the fix. ASCENDING plus a cap keeps the '
            'oldest rows and discards the current price.',
      );
    });

    test('no longer issues an unbounded ascending market_bars read', () {
      // Belt and braces: if someone reintroduces an ascending read anywhere in
      // this file, the source-ordering guard above should catch it, and this
      // makes the failure point obvious.
      final ascendingReads = RegExp(
        r"order\('open_time',\s*ascending:\s*true\)",
      ).allMatches(source);
      expect(
        ascendingReads.isEmpty,
        isTrue,
        reason:
            'found ${ascendingReads.length} ascending open_time read(s). An '
            'ascending read with more than $LiveRepository.postgrestRowCap rows '
            'available silently returns stale history.',
      );
    });

    test('does not select the timeframe column it no longer needs', () {
      // Selecting it was only necessary while the code had to work out which
      // timeframe each row belonged to.
      expect(
        source,
        isNot(contains("select('timeframe,open_time")),
      );
    });
  });
}