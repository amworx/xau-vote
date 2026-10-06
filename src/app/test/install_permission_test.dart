/// Install-permission behaviour.
///
/// The bug this covers: `REQUEST_INSTALL_PACKAGES` is granted by the USER in
/// Settings from Android 8, so the native `canInstallPackages` handler used to
/// answer `SDK_INT >= O` — true on every device the app can run on. Dart
/// therefore believed it could always install, launched the installer, and the
/// system refused. There was also no handler that opened the permission screen,
/// so nothing in the app could ask for the grant.
///
/// These tests pin the reporting contract across the MethodChannel: the
/// distinction between "granted", "not granted" and "cannot tell" must survive,
/// and the not-granted case must map to an outcome the UI can offer to fix.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xauvote/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.xauvote.app/update');
  final calls = <MethodCall>[];

  void mock({
    String? throwCode,
    String? throwMessage,
    bool? canInstall,
    bool? openedSettings,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (throwCode != null) {
        throw PlatformException(code: throwCode, message: throwMessage);
      }
      switch (call.method) {
        case 'canInstallPackages':
          return canInstall;
        case 'requestInstallPermission':
          return openedSettings ?? true;
        case 'installApk':
          return null;
      }
      return null;
    });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('canInstallPackages', () {
    test('reports the real grant, not the SDK level', () async {
      // The whole point: an SDK check is always true on a supported device, so
      // it can never detect the missing grant that breaks the install.
      mock(canInstall: false);
      expect(await const UpdatePlatform().canInstallPackages(), isFalse);

      mock(canInstall: true);
      expect(await const UpdatePlatform().canInstallPackages(), isTrue);
    });

    test('null means "cannot tell", which is not the same as allowed', () async {
      mock(throwCode: 'boom');
      expect(await const UpdatePlatform().canInstallPackages(), isNull);
    });
  });

  group('requestInstallPermission', () {
    test('opens the system screen and reports success', () async {
      mock(openedSettings: true);
      expect(await const UpdatePlatform().requestInstallPermission(), isTrue);
      expect(calls.single.method, 'requestInstallPermission');
    });

    test('a device with no such screen reports false rather than throwing', () async {
      mock(throwCode: 'no_settings');
      expect(await const UpdatePlatform().requestInstallPermission(), isFalse);
    });
  });

  group('install outcome', () {
    test('a missing grant is distinguishable from a generic failure', () async {
      // This is what lets the UI offer to open Settings instead of shrugging.
      mock(throwCode: 'needs_permission');
      final r = await const UpdatePlatform().installApk('/tmp/x.apk');
      expect(r.outcome, InstallOutcome.needsPermission);
      expect(r.ok, isFalse);
      expect(r.needsPermission, isTrue);
    });

    test('a SecurityException from the system maps to needsPermission', () async {
      mock(throwCode: 'permission_denied');
      final r = await const UpdatePlatform().installApk('/tmp/x.apk');
      expect(r.outcome, InstallOutcome.needsPermission);
    });

    test('a missing or empty download is reported as such', () async {
      mock(throwCode: 'missing_file');
      expect(
        (await const UpdatePlatform().installApk('/tmp/x.apk')).outcome,
        InstallOutcome.missingFile,
      );

      mock(throwCode: 'empty_file');
      expect(
        (await const UpdatePlatform().installApk('/tmp/x.apk')).outcome,
        InstallOutcome.missingFile,
      );
    });

    test('an unshared path is a failure, not a permission problem', () async {
      // bad_uri means the APK landed outside the FileProvider paths, so
      // asking for install permission would not help.
      mock(throwCode: 'bad_uri', throwMessage: 'Failed to find configured root');
      final r = await const UpdatePlatform().installApk('/tmp/x.apk');
      expect(r.outcome, InstallOutcome.failed);
      expect(r.detail, 'Failed to find configured root',
          reason: 'the native message must survive so the UI can explain it');
    });

    test('a failure with no native message still yields a usable outcome', () async {
      mock(throwCode: 'no_installer');
      final r = await const UpdatePlatform().installApk('/tmp/x.apk');
      expect(r.outcome, InstallOutcome.failed);
      expect(r.detail, isNull, reason: 'the UI must cope with a null detail');
    });

    test('a successful launch reports opened', () async {
      mock();
      final r = await const UpdatePlatform().installApk('/tmp/x.apk');
      expect(r.outcome, InstallOutcome.opened);
      expect(r.ok, isTrue);
    });
  });

  group('InstallResult', () {
    test('ok is true only for opened', () {
      for (final o in InstallOutcome.values) {
        expect(InstallResult(o).ok, o == InstallOutcome.opened, reason: '$o');
      }
    });

    test('needsPermission mirrors the outcome', () {
      expect(const InstallResult(InstallOutcome.needsPermission).needsPermission, isTrue);
      expect(const InstallResult(InstallOutcome.opened).needsPermission, isFalse);
    });
  });
}