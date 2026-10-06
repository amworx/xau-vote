// Guards the one duplication the outcome recorder cannot avoid.
//
// `supabase/functions/outcome-recorder/index.ts` compiles its own copy of the
// engine's thresholds, because the deploy bundler does not resolve `../_shared/`
// and shipping a second copy of the engine to avoid it would create exactly the
// drift this design exists to prevent.
//
// A duplicated constant is only safe if something fails when it diverges. This
// test is that something. It reads all three sources and asserts they agree:
//
//   1. xau_core Thresholds()                       (the source of truth)
//   2. _shared/analysis.ts DEFAULT_THRESHOLDS      (the TS port)
//   3. outcome-recorder CANONICAL_THRESHOLDS       (the fingerprint's basis)
//
// If someone retunes a threshold in Dart and forgets the other two, this fails.
// A silently changed fingerprint would split the record into cohorts that look
// identical, which is the specific failure the protocol exists to prevent.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xau_core/xau_core.dart';

/// Resolves a repo file. `flutter test` runs with the package root as the
/// working directory, but resolving from the script's own location keeps this
/// working under `dart test` and when a single file is run from elsewhere.
String _repoFile(String relative) {
  final candidates = [
    File('../../$relative'), // package root (src/app) -> repo root
    File('../../../$relative'), // script dir (src/app/test) -> repo root
  ];
  for (final file in candidates) {
    if (file.existsSync()) return file.readAsStringSync();
  }
  throw StateError(
    'Cannot find $relative. Tried: '
    '${candidates.map((f) => f.path).join(', ')}. '
    'The parity test only works from the repo checkout, not a published package.',
  );
}

/// Pulls `key: value` pairs out of a TypeScript object literal.
///
/// Anchors on the first `= {` after the marker rather than the first `{`. Both
/// declaration styles occur here: `const X = {` in the recorder, and
/// `export const X: SomeType = {` in the TS port, where anchoring on `{` alone
/// is fine but anchoring on a bare marker is not, because the type name and any
/// earlier mention of the symbol can be mistaken for the body.
Map<String, num> _tsObject(String source, String marker) {
  final start = source.indexOf(marker);
  expect(start, isNot(-1), reason: 'marker `$marker` not found');

  final assign = source.indexOf('=', start);
  expect(assign, isNot(-1), reason: '`$marker` has no assignment');

  final open = source.indexOf('{', assign);
  expect(open, isNot(-1), reason: '`$marker` is not assigned an object literal');

  var depth = 0;
  var end = -1;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  expect(end, isNot(-1), reason: 'unterminated object after `$marker`');

  final body = source.substring(open + 1, end);
  final out = <String, num>{};
  final pattern = RegExp(r'(\w+)\s*:\s*(-?\d+(?:\.\d+)?)');
  for (final m in pattern.allMatches(body)) {
    out[m.group(1)!] = num.parse(m.group(2)!);
  }
  expect(out, isNotEmpty, reason: 'no `key: number` pairs parsed from `$marker`');
  return out;
}

void main() {
  group('outcome recorder threshold parity', () {
    late Map<String, num> port;
    late Map<String, num> recorder;

    setUpAll(() {
      port = _tsObject(
        _repoFile('supabase/functions/_shared/analysis.ts'),
        'export const DEFAULT_THRESHOLDS',
      );
      recorder = _tsObject(
        _repoFile('supabase/functions/outcome-recorder/index.ts'),
        'const CANONICAL_THRESHOLDS',
      );
    });

    // The 14 values the rule fingerprint is computed from.
    const expected = <String, num>{
      'minTechnical': 8,
      'minFinal': 9,
      'rsiPreferredLow': 52,
      'rsiPreferredHigh': 68,
      'rsiExhaustedLong': 75,
      'rsiExhaustedShort': 25,
      'adxTrending': 20,
      'atrPercentileLow': 25,
      'atrPercentileHigh': 90,
      'atrPercentileExtreme': 95,
      'stopMinAtr': 0.8,
      'stopMaxAtr': 1.8,
      'tp2FloorR': 1.8,
      'maxDailySignals': 4,
    };

    test('the Dart Thresholds defaults are the values we expect', () {
      // If this fails, the methodology's [INIT] hypotheses were retuned and the
      // protocol needs re-reading before the expectation below is updated. Do not
      // just change the numbers here.
      const t = Thresholds();
      expect(t.minTechnical, 8);
      expect(t.minFinal, 9.0);
      expect(t.rsiPreferredLow, 52);
      expect(t.rsiPreferredHigh, 68);
      expect(t.rsiExhaustedLong, 75);
      expect(t.rsiExhaustedShort, 25);
      expect(t.adxTrending, 20);
      expect(t.atrPercentileLow, 25);
      expect(t.atrPercentileHigh, 90);
      expect(t.atrPercentileExtreme, 95);
      expect(t.stopMinAtr, 0.80);
      expect(t.stopMaxAtr, 1.80);
      expect(t.tp2FloorR, 1.8);
      expect(t.maxDailySignals, 4);
    });

    test('the TS port matches Dart', () {
      for (final e in expected.entries) {
        expect(port[e.key], e.value, reason: '${e.key} drifted in the TS port');
      }
    });

    test('the recorder fingerprint matches the TS port and Dart', () {
      for (final e in expected.entries) {
        expect(
          recorder[e.key],
          e.value,
          reason:
              '${e.key} drifted in outcome-recorder/index.ts. The rule_hash '
              'would change and split the record into a new cohort. Update all '
              'three sources together, or bump ENGINE_VERSION deliberately.',
        );
      }
    });

    test('neither TS object gained or lost a key', () {
      // An extra key changes the fingerprint without changing behaviour, which is
      // exactly the kind of invisible cohort split this test exists to prevent.
      expect(recorder.keys.toSet(), expected.keys.toSet());
      expect(port.keys.toSet(), expected.keys.toSet());
    });

    test('the recorder stop config matches the TS port', () {
      final portStop = _tsObject(
        _repoFile('supabase/functions/_shared/analysis.ts'),
        'export const DEFAULT_STOP_CONFIG',
      );
      final recStop = _tsObject(
        _repoFile('supabase/functions/outcome-recorder/index.ts'),
        'const CANONICAL_STOP_CONFIG',
      );

      // Level construction, not scoring. An earlier draft of the recorder
      // guessed tickSize/bufferTicks and tp2R 1.8 / tp3R 2.6; four of six values
      // were wrong, which would have fingerprinted the cohort against parameters
      // the engine never used.
      expect(portStop['atrBufferMultiple'], 0.2);
      expect(portStop['minStopAtr'], 0.8);
      expect(portStop['maxStopAtr'], 1.8);
      expect(portStop['tp1R'], 1);
      expect(portStop['tp2R'], 2);
      expect(portStop['tp3R'], 3);

      expect(recStop.keys.toSet(), portStop.keys.toSet());
      for (final e in portStop.entries) {
        expect(recStop[e.key], e.value, reason: '${e.key} drifted');
      }
    });

    test('the horizon in the recorder is the 12 bars the protocol fixes', () {
      final source = _repoFile(
        'supabase/functions/outcome-recorder/index.ts',
      );
      expect(
        source,
        contains('const HORIZON_BARS = 12;'),
        reason: 'Protocol section 3 fixes the horizon at 12 closed M15 bars.',
      );
      // The SQL trigger must derive the same horizon, or rows resolve later than
      // the function expects.
      final migration = _repoFile(
        'supabase/migrations/0008_outcome_recorder.sql',
      );
      expect(migration, contains("interval '3 hours'"));
    });
  });
}