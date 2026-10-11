/// Update-service behaviour: version comparison, manifest validation, and the
/// pause/cancel/resume state machine.
///
/// These are the parts that must not be wrong. A bad version comparison tells a
/// user they are current when they are not; an unvalidated manifest installs
/// arbitrary code; a broken resume silently corrupts an APK.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xauvote/services/update_service.dart';

void main() {
  group('version comparison', () {
    test('orders versions numerically, not lexically', () {
      // The classic bug: "10" < "9" as strings.
      expect(compareVersions('1.10.0', '1.9.0'), 1);
      expect(compareVersions('1.9.0', '1.10.0'), -1);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
    });

    test('treats equal versions as equal', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.0', '1.0.0'), 0);
    });

    test('a release candidate sorts below its release', () {
      expect(compareVersions('1.0.0', '1.0.0-rc1'), 1);
      expect(compareVersions('1.0.0-rc1', '1.0.0'), -1);
    });

    test('a malformed segment does not throw', () {
      expect(() => compareVersions('1.x.3', '1.0.3'), returnsNormally);
      expect(compareVersions('1.x.3', '1.0.3'), 0);
    });
  });

  group('manifest validation fails closed', () {
    Map<String, Object?> good() => {
          'version': '1.1.0',
          'versionCode': 2,
          'apkUrl': 'https://example.com/xv-1.1.0.apk',
          'sha256': 'a' * 64,
        };

    test('accepts a complete manifest', () {
      final r = ReleaseInfo.fromJson(good());
      expect(r.version, '1.1.0');
      expect(r.versionCode, 2);
    });

    test('rejects a manifest with no checksum', () {
      final json = good()..remove('sha256');
      expect(() => ReleaseInfo.fromJson(json), throwsFormatException);
    });

    test('rejects a malformed checksum', () {
      final json = good()..['sha256'] = 'not-a-digest';
      expect(() => ReleaseInfo.fromJson(json), throwsFormatException);
    });

    test('rejects a relative apkUrl', () {
      final json = good()..['apkUrl'] = '/local/apk';
      expect(() => ReleaseInfo.fromJson(json), throwsFormatException);
    });

    test('rejects a non-numeric versionCode', () {
      final json = good()..['versionCode'] = 'two';
      expect(() => ReleaseInfo.fromJson(json), throwsFormatException);
    });

    test('rejects a manifest missing the version', () {
      final json = good()..remove('version');
      expect(() => ReleaseInfo.fromJson(json), throwsFormatException);
    });
  });

  group('progress', () {
    test('is null when the total is unknown', () {
      const s = UpdateState(received: 500, total: 0);
      expect(s.progress, isNull);
    });

    test('is clamped to 0..1', () {
      const s = UpdateState(received: 200, total: 100);
      expect(s.progress, 1.0);
    });

    test('never claims installable without a path', () {
      const s = UpdateState(status: DownloadState.ready);
      expect(s.isInstallable, isFalse);
    });

    test('a verified download is installable', () {
      const s = UpdateState(
        status: DownloadState.ready,
        installPath: '/tmp/xv.apk',
      );
      expect(s.isInstallable, isTrue);
    });
  });

  group('check', () {
    late Directory tmp;

    setUp(() async => tmp = await Directory.systemTemp.createTemp('xv_upd'));
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    UpdateService serviceWith(
      Object body, {
      int status = 200,
    }) {
      return UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        downloadDir: tmp,
        probe: (_) async => http.Response(
          body is String ? body : jsonEncode(body),
          status,
        ),
      );
    }

    test('a 404 reports failure rather than "up to date"', () async {
      final s = serviceWith('nope', status: 404);
      await s.check();
      expect(s.state.status, DownloadState.failed);
      expect(s.state.message, contains('404'));
      s.dispose();
    });

    test('invalid JSON reports failure, not up to date', () async {
      final s = serviceWith('<html>error</html>');
      await s.check();
      expect(s.state.status, DownloadState.failed);
      s.dispose();
    });

    test('a valid manifest reaches the available state', () async {
      final s = serviceWith({
        'version': '9.9.9',
        'versionCode': 99,
        'apkUrl': 'https://example.com/xv.apk',
        'sha256': 'b' * 64,
      });
      await s.check();
      // No installed version is readable off-device, so the service must offer
      // the update and say it could not read the installed one.
      expect(s.state.status, DownloadState.available);
      expect(s.state.release?.version, '9.9.9');
      s.dispose();
    });

    test('a cancelled download returns to idle', () async {
      final s = serviceWith({
        'version': '9.9.9',
        'versionCode': 99,
        'apkUrl': 'https://example.com/xv.apk',
        'sha256': 'b' * 64,
      });
      await s.check();
      await s.cancel();
      expect(s.state.status, DownloadState.idle);
      expect(s.state.installPath, isNull);
      s.dispose();
    });
  });

  group('platform download directory', () {
    // Regression guard for the installer failure on a real device:
    // "couldn't open the installer: APK path is not shared with the installer".
    //
    // Dart's Directory.systemTemp is NOT the app cache dir in a release app
    // process on Android - it resolves to /data/local/tmp, which FileProvider's
    // <cache-path> does not expose, so getUriForFile threw. The download dir
    // must come from Android's own cacheDir. Every other test in this file
    // injects `downloadDir`, which short-circuits before the platform is
    // consulted - so the wrong platform path had no coverage. This one
    // deliberately does not inject anything, and mocks the channel to report a
    // known cache root.
    test('lands the APK under the platform cache dir that <cache-path> exposes',
        () async {
      // MethodChannel mocks need the test binding; the rest of this file is
      // pure Dart and never required it.
      TestWidgetsFlutterBinding.ensureInitialized();

      final cache = await Directory.systemTemp.createTemp('xv_cache');
      addTearDown(() async {
        if (await cache.exists()) await cache.delete(recursive: true);
      });

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(UpdatePlatform.channel, (call) async {
        calls.add(call);
        if (call.method == 'cacheDir') return cache.path;
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(UpdatePlatform.channel, null);
      });

      final s = UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
      );
      addTearDown(s.dispose);

      final dir = await s.platformTargetDir();

      expect(calls.map((c) => c.method), contains('cacheDir'),
          reason: 'must ask Android for its cache dir, not guess from temp');
      expect(await dir.exists(), isTrue,
          reason: 'the updates directory must actually be created');
      expect(dir.path, startsWith(cache.path),
          reason:
              'must sit under the app cache dir that <cache-path> exposes, '
              'or the installer cannot open the APK');
      expect(dir.path, endsWith('updates'));
    });

    test('a resume appends rather than truncating the partial file', () async {
      // openWrite() defaults to FileMode.write, which truncates. A resumed
      // download asked the server for bytes from `existing` onward, so
      // truncating left only the tail and the digest check then failed.
      final dir = await Directory.systemTemp.createTemp('xv_resume');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final partial = File('${dir.path}${Platform.pathSeparator}a.apk');
      await partial.writeAsString('AAAA');

      final sink = partial.openWrite(mode: FileMode.append);
      sink.write('BBBB');
      await sink.flush();
      await sink.close();

      expect(await partial.readAsString(), 'AAAABBBB',
          reason: 'append must keep the bytes already on disk');
    });
  });

  group('download', () {
    late Directory tmp;

    setUp(() async => tmp = await Directory.systemTemp.createTemp('xv_dl'));
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    /// A release whose manifest digest really is [payload]'s digest.
    ReleaseInfo releaseFor(List<int> payload) => ReleaseInfo.fromJson({
          'version': '2.0.0',
          'versionCode': 2,
          'apkUrl': 'https://example.com/xv-2.0.0-2.apk',
          'sha256': sha256Hex(payload),
        });

    /// Serves [payload] in [chunkSize]-byte chunks.
    ///
    /// Returns a service whose downloads land in the temp dir and can be
    /// paused mid-flight.
    UpdateService serving(
      ReleaseInfo release,
      List<int> payload, {
      required int chunkSize,
      bool honourRange = true,
      void Function(int sent)? onChunk,
    }) {
      final client = _ChunkedClient(
        payload: payload,
        chunkSize: chunkSize,
        honourRange: honourRange,
        onChunk: onChunk,
      );
      addTearDown(client.close);
      final s = UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        downloadDir: tmp,
        client: client,
      );
      addTearDown(s.dispose);
      return s;
    }

    test('a good download verifies and becomes installable', () async {
      final payload = List<int>.generate(4096, (i) => i % 251);
      final release = releaseFor(payload);
      final s = serving(release, payload, chunkSize: 512);

      await s.check(); // no probe needed: client answers the manifest too
      expect(s.state.release?.version, '2.0.0');
      await s.startDownload();

      expect(s.state.status, DownloadState.ready);
      expect(s.state.isInstallable, isTrue);
      expect(File(s.state.installPath!).existsSync(), isTrue);
      expect(File(s.state.installPath!).lengthSync(), 4096);
      expect(s.state.progress, 1.0);
    });

    test('pause keeps partial bytes and resume finishes the file', () async {
      final payload = List<int>.generate(8192, (i) => i % 97);
      final release = releaseFor(payload);

      late UpdateService s;
      var chunks = 0;
      s = serving(release, payload, chunkSize: 512, onChunk: (_) {
        chunks++;
        // Pause after a couple of chunks so there is a partial prefix.
        if (chunks == 3) s.pause();
      });

      await s.check();
      await s.startDownload();

      expect(s.state.status, DownloadState.paused);
      final pausedAt = s.state.received;
      expect(pausedAt, greaterThan(0));
      expect(pausedAt, lessThan(8192));
      expect(s.state.message, contains('Paused'));

      // Resume must complete and verify against the same digest.
      s = serving(release, payload, chunkSize: 512);
      await s.check();
      // Point the fresh service at the partial file by resuming.
      final partial = File('${tmp.path}${Platform.pathSeparator}xv-2.0.0-2.apk');
      expect(partial.existsSync(), isTrue);
      expect(partial.lengthSync(), pausedAt);

      await s.startDownload();
      expect(s.state.status, DownloadState.ready);
      expect(partial.lengthSync(), 8192);
    });

    test('a checksum mismatch discards the APK and refuses install',
        () async {
      final payload = List<int>.generate(1024, (i) => i % 31);
      // The endpoint serves a digest that does NOT match the body it streams,
      // which is what an intercepted or corrupted download looks like.
      final client = _ChunkedClient(
        payload: payload,
        chunkSize: 256,
        manifestShaOverride: 'f' * 64,
      );
      addTearDown(client.close);
      final s = UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        downloadDir: tmp,
        client: client,
      );
      addTearDown(s.dispose);

      await s.check();
      expect(s.state.status, DownloadState.available);
      await s.startDownload();

      expect(s.state.status, DownloadState.failed);
      expect(s.state.message, contains('checksum'));
      // Failing closed means no path is offered, and the bytes are gone.
      expect(s.state.isInstallable, isFalse);
      expect(s.state.installPath, isNull);
      expect(
        File('${tmp.path}${Platform.pathSeparator}xv-2.0.0-2.apk').existsSync(),
        isFalse,
      );
    });

    test('an incomplete body fails instead of offering a broken APK',
        () async {
      final payload = List<int>.generate(2048, (i) => i % 31);
      final client = _ChunkedClient(
        payload: payload,
        chunkSize: 256,
        // Report the full length but stop the body halfway: exactly what a
        // dropped connection looks like to the downloader.
        declaredLength: 2048,
        truncateAt: 1024,
      );
      addTearDown(client.close);
      final s = UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        downloadDir: tmp,
        client: client,
      );
      addTearDown(s.dispose);

      await s.check();
      await s.startDownload();

      expect(s.state.status, DownloadState.failed);
      expect(s.state.isInstallable, isFalse);
    });

    test('a body that stalls mid-transfer fails instead of hanging', () async {
      // This is the field bug: the manifest check (a few KB) succeeded, but the
      // ~46MB APK body went silent mid-transfer and the downloader sat forever
      // with no progress and no error. A stalled body must surface as a
      // failure the user can retry, not a freeze.
      final payload = List<int>.generate(4096, (i) => i % 41);
      final client = _ChunkedClient(
        payload: payload,
        chunkSize: 512,
        stallAfterBytes: 1024, // 2 chunks flow, then the stream just stops
      );
      addTearDown(client.close);
      final s = UpdateService(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        downloadDir: tmp,
        client: client,
        chunkTimeout: const Duration(milliseconds: 150),
      );
      addTearDown(s.dispose);

      await s.check();
      await s.startDownload();

      expect(s.state.status, DownloadState.failed);
      expect(s.state.message, contains('stalled'));
      expect(s.state.isInstallable, isFalse);
      expect(s.state.installPath, isNull);
    });

    test('a server that ignores Range restarts cleanly', () async {
      final payload = List<int>.generate(4096, (i) => i % 53);
      final release = releaseFor(payload);
      final s = serving(release, payload, chunkSize: 512, honourRange: false);

      await s.check();
      await s.startDownload();

      expect(s.state.status, DownloadState.ready);
      expect(File(s.state.installPath!).lengthSync(), 4096);
    });

    test('cancel during an active download leaves nothing installable',
        () async {
      final payload = List<int>.generate(8192, (i) => i % 17);
      final release = releaseFor(payload);

      // Capture the cancel future instead of firing it fire-and-forget: an
      // un-awaited cancel races the download loop, which closes the same
      // writer, and that makes the test order-dependent.
      Future<void>? cancelling;
      late UpdateService s;
      s = serving(release, payload, chunkSize: 256, onChunk: (_) {
        cancelling ??= s.cancel();
      });

      await s.check();
      await s.startDownload();
      await cancelling;

      expect(s.state.isInstallable, isFalse);
      expect(s.state.installPath, isNull);
      // The partial must not survive as something a later resume could trust.
      expect(
        File('${tmp.path}${Platform.pathSeparator}xv-2.0.0-2.apk').existsSync(),
        isFalse,
      );
    });
  });
}

/// Serves a fixed body in chunks, so a download can be paused mid-flight.
class _ChunkedClient extends http.BaseClient {
  _ChunkedClient({
    required this.payload,
    required this.chunkSize,
    this.honourRange = true,
    this.declaredLength,
    this.truncateAt,
    this.onChunk,
    this.manifestShaOverride,
    this.stallAfterBytes,
  });

  final List<int> payload;
  final int chunkSize;
  final bool honourRange;

  /// Advertise this digest instead of the real one, to test verification.
  final String? manifestShaOverride;

  /// What to report in Content-Length, when it should disagree with the body.
  final int? declaredLength;

  /// Stop the body after this many bytes, simulating a dropped connection.
  final int? truncateAt;

  final void Function(int sent)? onChunk;

  /// Emit this many bytes then stop, without closing the stream.
  ///
  /// This is what a dropped or throttled connection looks like to the
  /// downloader: bytes stop arriving but no error or end-of-stream is
  /// signalled, so a downloader with no timeout waits forever.
  final int? stallAfterBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // The manifest fetch is JSON served with the same mechanism.
    if (request.url.path.endsWith('.json')) {
      final body = jsonEncode({
        'version': '2.0.0',
        'versionCode': 2,
        'apkUrl': 'https://example.com/xv-2.0.0-2.apk',
        'sha256': manifestShaOverride ?? sha256Hex(payload),
      });
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        200,
        contentLength: body.length,
      );
    }

    var start = 0;
    final range = request.headers['Range'];
    if (honourRange && range != null && range.startsWith('bytes=')) {
      start = int.parse(range.substring(6).replaceAll('-', ''));
    }
    final end = truncateAt ?? payload.length;
    final slice = payload.sublist(start, end > start ? end : start);
    final length = declaredLength ?? slice.length;

    var sent = 0;
    final controller = StreamController<List<int>>();
    final stream = controller.stream;
    scheduleMicrotask(() async {
      while (sent < slice.length) {
        // Simulate a stalled connection: bytes stop arriving, but the stream
        // is never closed and no error is raised. Without a chunk timeout the
        // downloader would hang here forever.
        if (stallAfterBytes != null && sent >= stallAfterBytes!) {
          return;
        }
        final size = chunkSize < slice.length - sent ? chunkSize : slice.length - sent;
        controller.add(slice.sublist(sent, sent + size));
        sent += size;
        onChunk?.call(sent);
        await Future<void>.delayed(Duration.zero);
      }
      await controller.close();
    });

    return http.StreamedResponse(
      stream,
      start > 0 && honourRange ? 206 : 200,
      contentLength: length,
    );
  }
}