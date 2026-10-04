/// Pip-convention tests (D-20260927-003) and the 390px layout invariants the
/// convention touches.
///
/// Points are canonical (spec A§11); pips are a display-only unit scaled by
/// [PipConvention.pipFactor]. These tests pin three things:
///
/// 1. **B is behaviour-preserving.** The pre-refactor code hardcoded `* 100`
///    in [pipsTo]. Convention B is exactly that, so every documented figure
///    must be unchanged — this suite would have caught a silent ×10.
/// 2. **A is exactly B ÷ 10**, sign preserved, and the convention never
///    touches a price, a level or an R:R.
/// 3. **A row's readout is derived, never stored**, so switching the setting
///    rescales Signal and History in place.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xauvote/data/mock_fixtures.dart';
import 'package:xauvote/config.dart' show mockMode;
import 'package:xauvote/main.dart';
import 'package:xauvote/models/display_models.dart';
import 'package:xauvote/screens/radar_screen.dart';
import 'package:xauvote/state/app_state.dart';

/// Verbatim copy of the pre-refactor implementation (hardcoded convention B).
/// Kept so "B changes nothing" is asserted against the real old behaviour
/// rather than against a restatement of it.
int _legacyPipsTo(double target, double entryMid) =>
    ((target - entryMid)).floor() * 100;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load('Sora', [
    'sora-v17-latin-regular.ttf',
    'sora-v17-latin-600.ttf',
    'sora-v17-latin-700.ttf',
    'sora-v17-latin-800.ttf',
  ]);
  await load('Space Mono', [
    'space-mono-v17-latin-regular.ttf',
    'space-mono-v17-latin-700.ttf',
  ]);
}

/// The document width every layout assertion below is made at.
const Size _phone = Size(390, 4000);

Future<void> _pumpApp(WidgetTester tester) async {
  await _loadFonts();
  // 390 wide = the target device; tall enough that every lazily-built list row
  // is mounted, so no assertion depends on a scroll position.
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const XauVoteApp());
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
}

/// Sets the target scope on the app's own [AppState].
///
/// The default scope is TP1, so a test about pip scaling or layout must state
/// the scope it wants instead of inheriting the default. `XauVoteApp` owns its
/// provider, so an outer one is shadowed. Must be called while the Radar tab is
/// showing, because the shell renders only the selected screen.
Future<void> _setTargets(WidgetTester tester, TargetSelection targets) async {
  final state = Provider.of<AppState>(
    tester.element(find.byType(RadarScreen)),
    listen: false,
  );
  state.setTargets(targets);
  await tester.pumpAndSettle();
}

/// Every mounted [Text] laid out taller than one line of its own font.
///
/// A real wrap roughly doubles the height, so a 1.5× factor separates a wrap
/// from the sub-pixel gap between the laid-out height and the preferred line
/// height. Body copy that is *designed* to run to several lines (the Sources
/// reasoning paragraph, the Events blackout note) is excluded by [skip] so the
/// assertion covers the one-line grid lines, not prose.
List<String> wrappedTexts(WidgetTester tester, {Set<String> skip = const {}}) {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final data = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (data.trim().isEmpty || skip.any(data.startsWith)) continue;
    final style = w.style ?? DefaultTextStyle.of(e).style;
    final painted = TextPainter(
      text: TextSpan(text: data, style: style),
      textDirection: TextDirection.ltr,
      maxLines: w.maxLines,
    )..layout(maxWidth: 400);
    final actual = tester.getSize(find.byWidget(w)).height;
    if (actual > painted.preferredLineHeight * 1.5) out.add(data);
  }
  return out;
}

/// Prose that is meant to run long; excluded from the one-line assertion.
const _prose = {
  'A/B/C/E cluster tightly',
  'New signals paused from',
  // Sentences, not figures. These are allowed to wrap at 390px because they are
  // explanatory copy; every numeric/label string must still stay on one line.
  'The scan runs on closed bars only. Waiting for enough history to evaluate '
      'the 1H regime.',
  'XV does not execute trades.',
};

void main() {
  group('pip math', () {
    test('B reproduces the pre-refactor hardcoded figures EXACTLY', () {
      const s = MockFixtures.strongLong;
      for (final level in [s.stopLoss, s.tp1!, s.tp2!, s.tp3!]) {
        expect(
          pipsTo(level, s.entryMid, pipFactor: PipConvention.b.pipFactor),
          _legacyPipsTo(level, s.entryMid),
          reason: 'level $level must be unchanged by the refactor',
        );
      }
      // The figures D-20260927-003 pins for the 4,278 entry reference.
      expect(pipsTo(4262, 4277.5, pipFactor: PipConvention.b.pipFactor), -1600);
      expect(pipsTo(4295, 4277.5, pipFactor: PipConvention.b.pipFactor), 1700);
      expect(pipsTo(4315, 4277.5, pipFactor: PipConvention.b.pipFactor), 3700);
      expect(pipsTo(4340, 4277.5, pipFactor: PipConvention.b.pipFactor), 6200);
      expect(zonePips(4275, 4280, pipFactor: PipConvention.b.pipFactor), 500);
      expect(pipsFromMove(0.30, pipFactor: PipConvention.b.pipFactor), 30);
      expect(pipsFromPoints(31, pipFactor: PipConvention.b.pipFactor), 3100);
      expect(
        pipsFromPoints(MockFixtures.historyNetPipsPoints,
            pipFactor: PipConvention.b.pipFactor),
        8400,
      );
    });

    test('A is exactly B ÷ 10 with the sign preserved', () {
      const s = MockFixtures.strongLong;
      for (final level in [s.stopLoss, s.tp1!, s.tp2!, s.tp3!]) {
        final b =
            pipsTo(level, s.entryMid, pipFactor: PipConvention.b.pipFactor);
        final a =
            pipsTo(level, s.entryMid, pipFactor: PipConvention.a.pipFactor);
        expect(a, b ~/ 10, reason: 'level $level');
      }
      expect(pipsTo(4262, 4277.5, pipFactor: PipConvention.a.pipFactor), -160);
      expect(pipsTo(4295, 4277.5, pipFactor: PipConvention.a.pipFactor), 170);
      expect(zonePips(4275, 4280, pipFactor: PipConvention.a.pipFactor), 50);
      expect(pipsFromMove(0.30, pipFactor: PipConvention.a.pipFactor), 3);
    });

    test('the convention never changes a price, a level or an R:R', () {
      // Every converter takes its level arguments unchanged and only the
      // factor varies, so no convention can move a price or an R:R. Assert the
      // pure functions stay level-exact.
      const s = MockFixtures.strongLong;
      expect(formatLevel(s.entryLow), '4,275');
      expect(formatLevel(s.entryHigh), '4,280');
      expect(formatLevel(s.stopLoss), '4,262');
      expect(formatLevel(s.tp1!), '4,295');
      expect(formatLevel(s.tp2!), '4,315');
      expect(formatLevel(s.tp3!), '4,340');
      expect(formatPrice(s.price), '4,278.30');
      expect(
        riskReward(
            target: s.tp3!, entryLow: s.entryLow, stopLoss: s.stopLoss),
        closeTo(5.0, 0.001),
      );
    });

    test('a zero-point outcome stays a flat 0 PIPS, never a sign', () {
      expect(
        pipsLabel(0, pipFactor: PipConvention.b.pipFactor),
        '0 PIPS',
      );
      expect(
        pipsLabel(-0.4, pipFactor: PipConvention.b.pipFactor),
        '0 PIPS',
        reason: 'a sub-pip loss must not read as a negative result',
      );
    });
  });

  group('AppState', () {
    test('defaults to B and notifies once per real change', () {
      final state = AppState();
      expect(state.pipConvention, PipConvention.b,
          reason: 'D-20260927-003 defaults to B (FXPro/Vantage)');

      var notified = 0;
      state.addListener(() => notified++);
      state.setPipConvention(PipConvention.a);
      expect(state.pipConvention, PipConvention.a);
      expect(notified, 1);

      state.setPipConvention(PipConvention.a);
      expect(notified, 1, reason: 're-selecting the same value is a no-op');
    });
  });

  group('Signal + History readouts follow the active convention', () {
    testWidgets('B renders the documented figures and one-line cells',
        skip: !mockMode,
      (tester) async {
      await _pumpApp(tester);
      // Pin all three targets: this suite is about pip scaling, and inheriting
      // the TP1 default would hide TP2/TP3 readouts.
      await _setTargets(tester, TargetSelection.all);
      await _openTab(tester, 'SIGNAL');

      expect(find.text('+1700 PIPS'), findsOneWidget);
      expect(find.text('−1600 pips · risk 15.5'), findsOneWidget);
      expect(find.text('500-pip zone'), findsOneWidget);
      expect(find.text('IN-PROFIT +30 PIPS'), findsOneWidget);
      // Prices and the R:R are convention-independent.
      expect(find.text('4,275-4,280'), findsOneWidget);
      expect(find.text('4,262'), findsOneWidget);
      expect(find.text('+6200 · 1:5.0'), findsOneWidget);

      expect(wrappedTexts(tester), isEmpty,
          reason: 'no Signal text may wrap at 390px');

      await _openTab(tester, 'HISTORY');
      expect(find.text('+3100 PIPS'), findsOneWidget);
      expect(find.text('-1500 PIPS'), findsOneWidget);
      expect(find.text('+8400'), findsOneWidget);
      expect(find.text('Pips x0.01 · per D-003'), findsOneWidget);
      expect(wrappedTexts(tester), isEmpty,
          reason: 'every History row detail line must fit one line at 390px');
    });

    testWidgets('picking A rescales the readouts and nothing else',
        skip: !mockMode,
      (tester) async {
      await _pumpApp(tester);
      await _setTargets(tester, TargetSelection.all);
      await _openTab(tester, 'SETTINGS');
      await tester.ensureVisible(find.text('A · 0.10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A · 0.10'));
      await tester.pumpAndSettle();

      await _openTab(tester, 'SIGNAL');
      expect(find.text('+170 PIPS'), findsOneWidget);
      expect(find.text('−160 pips · risk 15.5'), findsOneWidget);
      expect(find.text('50-pip zone'), findsOneWidget);
      expect(find.text('IN-PROFIT +3 PIPS'), findsOneWidget);
      // Unchanged by the convention: the levels and the R:R.
      expect(find.text('4,275-4,280'), findsOneWidget);
      expect(find.text('4,262'), findsOneWidget);
      expect(find.text('4,295'), findsOneWidget);
      expect(find.text('4,315'), findsOneWidget);
      expect(find.text('4,340'), findsOneWidget);
      expect(find.text('+620 · 1:5.0'), findsOneWidget);
      expect(wrappedTexts(tester), isEmpty,
          reason: 'the shorter A figures must still be one line');

      await _openTab(tester, 'HISTORY');
      expect(find.text('+310 PIPS'), findsOneWidget);
      expect(find.text('+840'), findsOneWidget);
      expect(find.text('Pips x0.10 · per D-003'), findsOneWidget);
      expect(wrappedTexts(tester), isEmpty);
    });

    testWidgets('a source stop distance is derived, not stored', skip: !mockMode,
      (tester) async {
      await _pumpApp(tester);
      await _openTab(tester, 'SOURCES');
      await tester.tap(find.text('DESK A · GoldPulse'));
      await tester.pumpAndSettle();

      expect(find.text('4,262 · −1600p'), findsOneWidget,
          reason: 'the desk distance must be re-derived at B');
      // A desk that quotes a bare level shows no invented distance.
      expect(MockFixtures.sources.firstWhere((s) => s.id == 'D').stopPoints,
          isNull);

      await _openTab(tester, 'SETTINGS');
      await tester.ensureVisible(find.text('A · 0.10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A · 0.10'));
      await tester.pumpAndSettle();

      await _openTab(tester, 'SOURCES');
      await tester.tap(find.text('DESK A · GoldPulse'));
      await tester.pumpAndSettle();
      expect(find.text('4,262 · −160p'), findsOneWidget,
          reason: 'the same desk distance must rescale to A');
    });
  });

  group('390px layout', () {
    testWidgets('no tab overflows or wraps a one-line string',
        skip: !mockMode,
      (tester) async {
      await _pumpApp(tester);
      // Pin the scope so this sweep measures layout, not the target default.
      await _setTargets(tester, TargetSelection.all);
      for (final tab in [
        'RADAR',
        'SIGNAL',
        'SOURCES',
        'HISTORY',
        'EVENTS',
        'SETTINGS',
      ]) {
        await _openTab(tester, tab);
        expect(tester.takeException(), isNull, reason: '$tab threw');
        expect(
          wrappedTexts(tester, skip: _prose),
          isEmpty,
          reason: '$tab wrapped a one-line string at 390px',
        );
      }
    });
  });
}
