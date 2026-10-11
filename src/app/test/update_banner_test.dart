/// The update banner.
///
/// The banner's job is narrow and easy to get wrong in two directions: it must
/// not appear when there is nothing to say, and it must not claim an update is
/// installed when Android still needs the user to approve it. These assertions
/// pin both, plus the "no second download path" rule.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:xauvote/services/update_service.dart';
import 'package:xauvote/widgets/update_banner.dart';

Widget _host(UpdateService service, {bool dismissed = false}) =>
    MaterialApp(
      home: ChangeNotifierProvider<UpdateService?>.value(
        value: service,
        child: Scaffold(
          body: UpdateBanner(
            service: service,
            dismissed: dismissed,
            onDismiss: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );

/// A service parked in the `available` state with a plausible release.
UpdateService _available({
  String version = '1.0.4',
  String notes = 'Fixes the in-app downloader.',
  int sizeBytes = 51112909,
}) =>
    UpdateService(
      manifestUrl: Uri.parse('https://example.com/update.json'),
      initialState: UpdateState(
        status: DownloadState.available,
        release: ReleaseInfo(
          version: version,
          versionCode: 4,
          apkUrl: Uri.parse('https://example.com/app.apk'),
          sha256: 'a' * 64,
          sizeBytes: sizeBytes,
          notes: notes,
        ),
        message: '$version is available.',
      ),
    );

void main() {
  group('relevance', () {
    test('speaks only when there is something to say', () {
      expect(
        UpdateBanner.isRelevant(
          UpdateState(status: DownloadState.available),
        ),
        isTrue,
      );
      expect(
        UpdateBanner.isRelevant(UpdateState(status: DownloadState.ready)),
        isTrue,
      );
    });

    test('stays quiet while a download is already running', () {
      // Settings shows the progress bar; repeating it here would be noise.
      expect(
        UpdateBanner.isRelevant(
          UpdateState(status: DownloadState.downloading),
        ),
        isFalse,
      );
      expect(
        UpdateBanner.isRelevant(UpdateState(status: DownloadState.paused)),
        isFalse,
      );
      expect(
        UpdateBanner.isRelevant(UpdateState(status: DownloadState.upToDate)),
        isFalse,
      );
      expect(
        UpdateBanner.isRelevant(
          const UpdateState(status: DownloadState.failed),
        ),
        isFalse,
      );
    });
  });

  group('rendering', () {
    testWidgets('an available update shows the version and both actions',
        (tester) async {
      final s = _available();
      addTearDown(s.dispose);
      await tester.pumpWidget(_host(s));

      expect(find.text('Update available — 1.0.4'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      // Size is stated so the cost is known before acting.
      expect(find.textContaining('48.7 MB'), findsOneWidget);
    });

    testWidgets('"Later" hides it for the session', (tester) async {
      final s = _available();
      addTearDown(s.dispose);
      await tester.pumpWidget(_host(s, dismissed: true));

      expect(find.text('Update available — 1.0.4'), findsNothing);
      expect(find.text('Update now'), findsNothing);
    });

    testWidgets('a verified download does NOT claim to be installed',
        (tester) async {
      final s = UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        initialState: UpdateState(
          status: DownloadState.ready,
          installPath: '/data/cache/updates/a.apk',
          received: 51112909,
          total: 51112909,
          release: ReleaseInfo(
            version: '1.0.4',
            versionCode: 4,
            apkUrl: Uri.parse('https://example.com/app.apk'),
            sha256: 'a' * 64,
            sizeBytes: 51112909,
            notes: 'Fixes the in-app downloader.',
          ),
        ),
      );
      addTearDown(s.dispose);
      await tester.pumpWidget(_host(s));

      // Android still requires the user to approve the install, so the honest
      // wording is "restart to install", never "updated" or "installed".
      expect(
        find.textContaining('restart to install'),
        findsOneWidget,
        reason: 'must not imply the update is already done',
      );
      expect(find.textContaining('Update available'), findsNothing);
      expect(find.text('Install'), findsOneWidget);
    });

    testWidgets('an empty notes field still produces a usable description',
        (tester) async {
      final s = _available(notes: '   ');
      addTearDown(s.dispose);
      await tester.pumpWidget(_host(s));

      expect(
        find.textContaining('newer build is published'),
        findsOneWidget,
      );
    });

    testWidgets('renders nothing when no release is loaded', (tester) async {
      final s = UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
      );
      addTearDown(s.dispose);
      await tester.pumpWidget(_host(s));

      expect(find.byType(UpdateBanner), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(find.text('Update now'), findsNothing);
    });

    testWidgets('the banner never downloads - it only navigates',
        (tester) async {
      final s = _available();
      addTearDown(s.dispose);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<UpdateService?>.value(
            value: s,
            child: Scaffold(
              body: UpdateBanner(
                service: s,
                dismissed: false,
                onDismiss: () {},
                onOpenSettings: () => opened = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      expect(opened, isTrue);
      // Critically: the download must NOT have started from the banner.
      expect(s.state.status, DownloadState.available,
          reason: 'Settings owns the one download path');
    });

    testWidgets('taps do not overflow at 360dp', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final s = _available(notes: 'A rather longer release note than usual.');
      addTearDown(s.dispose);
      await tester.pumpWidget(_host(s));

      expect(tester.takeException(), isNull);
    });
  });

  group('startup check', () {
    // Regression guard for the unfinished banner wiring: before this the only
    // check() call was the Settings CHECK button, so the banner could never
    // appear unless the trader opened Settings first. The slot now runs one
    // check per launch; this pins that without a tap and without a network
    // call (probe injects the manifest response).
    testWidgets('surfaces an update with no tap on first launch',
        (tester) async {
      final manifest = jsonEncode({
        'version': '1.0.14',
        'versionCode': 27,
        'apkUrl': 'https://example.com/app.apk',
        'sha256': 'b' * 64,
        'sizeBytes': 51112909,
        'notes': 'Fixes the installer path.',
      });
      var probes = 0;
      final s = UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        probe: (url) async {
          probes += 1;
          return http.Response(manifest, 200);
        },
        // A code far below 27 so the check reports "available", not "current".
        initialState: const UpdateState(status: DownloadState.idle),
      );
      addTearDown(s.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<UpdateService?>.value(
            value: s,
            child: Scaffold(
              body: UpdateBannerSlot(onOpenSettings: () {}),
            ),
          ),
        ),
      );

      // Let the post-frame callback run the check and the result emit.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(probes, 1, reason: 'exactly one check per launch');
      expect(
        find.text('Update available — 1.0.14'),
        findsOneWidget,
        reason: 'the banner must appear without the trader tapping CHECK',
      );
    });
  });
}