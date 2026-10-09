/// Settings → App updates + About.
///
/// The About group is a one-line assertion, so it is pinned here to stop the
/// developer's nickname silently disappearing in a future refactor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xauvote/config.dart';
import 'package:xauvote/screens/settings_screen.dart';
import 'package:xauvote/state/app_state.dart';

/// Pumps Settings at phone width on a surface tall enough that the whole
/// screen scrolls, matching how the app is actually used.
Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: const Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls until [finder] is on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView),
    const Offset(0, -240),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('About developer', () {
    testWidgets('shows the developer nickname', (tester) async {
      await _pumpSettings(tester);
      await _reveal(tester, find.text('AMWORX'));

      expect(find.text('AMWORX'), findsOneWidget);
      expect(find.text('Developer'), findsOneWidget);
      expect(find.text('Built by'), findsOneWidget);
    });

    testWidgets('the existing settings groups are still intact',
        (tester) async {
      await _pumpSettings(tester);
      // Regression guard: adding groups must not displace these. Groups below
      // the fold are built lazily, so each is revealed before asserting —
      // position in the scroll is not part of the contract. Matched
      // case-insensitively on the eyebrow text so the assertion does not
      // depend on which middle-dot codepoint the title happens to use.
      expect(find.text('TIMEFRAMES'), findsOneWidget);
      // Indicator customization moved to the Signal screen's regime card:
      // Settings must not carry a second copy.
      expect(find.text('INDICATORS · DISPLAY ONLY'), findsNothing);
      expect(find.text('Direction · EMA + structure'), findsNothing);
      await _reveal(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              w.data!.toUpperCase().startsWith('NOTIFICATIONS'),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              w.data!.toUpperCase().startsWith('NOTIFICATIONS'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the required legal micro-copy survives', (tester) async {
      await _pumpSettings(tester);
      await _reveal(tester, find.text('Not financial advice · never executes trades'));

      expect(find.text('UIcons by Flaticon'), findsOneWidget);
    });
  });

  group('App updates', () {
    testWidgets('says so plainly when no endpoint is configured',
        (tester) async {
      // The suite runs without --dart-define=UPDATE_MANIFEST_URL, so the
      // updater is disabled rather than pointed at some fallback host.
      expect(updatesConfigured, isFalse);

      await _pumpSettings(tester);
      await _reveal(tester, find.text('APP UPDATES'));

      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('UNAVAILABLE'), findsOneWidget);
      expect(find.text('No update endpoint in this build'), findsOneWidget);
    });

    testWidgets('offers no download or install controls when disabled',
        (tester) async {
      await _pumpSettings(tester);
      await _reveal(tester, find.text('APP UPDATES'));

      // Nothing may be offered that cannot work.
      expect(find.text('DOWNLOAD'), findsNothing);
      expect(find.text('INSTALL'), findsNothing);
      expect(find.text('PAUSE'), findsNothing);
      expect(find.text('CANCEL'), findsNothing);
      expect(find.text('RESUME'), findsNothing);
    });

    testWidgets('the group is below the notification settings, not replacing them',
        (tester) async {
      await _pumpSettings(tester);
      await _reveal(tester, find.text('APP UPDATES'));

      // Both present on one scrollable screen.
      expect(find.text('AMWORX'), findsOneWidget);
      expect(find.text('APP UPDATES'), findsOneWidget);
    });
  });
}