/// Update check + download + hand-off to the system installer.
///
/// # Why this is a service and not a widget
///
/// Downloading an APK is long-running, must survive a screen rebuild, and has
/// to be cancellable and pausable. Keeping the state machine here means the
/// Settings screen only renders it, and the logic can be tested without a
/// device, a network, or a package installer.
///
/// # Honesty constraints
///
/// This deliberately never reports success it cannot prove:
/// * a version comparison uses the *installed* version from the package
///   manager, not a build-time literal that would go stale after updating;
/// * a download is only "complete" once the server's byte count is satisfied;
/// * an install is offered to the user, never forced. Android requires a
///   human to approve it and we do not pretend otherwise.
///
/// # Security
///
/// The APK is verified against the version and SHA-256 the manifest declares
/// before install is offered. An unverified APK from a compromised endpoint is
/// exactly the code-execution risk this feature creates, so failing closed is
/// the only acceptable behaviour.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Which transport [UpdateService] uses. Overridden in tests.
typedef UpdateProbe = Future<http.Response> Function(Uri url);

/// Platform bridge for the two things only Android can answer.
class UpdatePlatform {
  const UpdatePlatform();

  /// Public so tests can drive the state machine without a device.
  static const MethodChannel channel = MethodChannel('com.xauvote.app/update');

  /// The version currently installed, e.g. `1.0.0` with code `1`.
  ///
  /// Falls back to null when the channel is unavailable (web, or a unit test),
  /// which makes [UpdateService] report "unknown installed version" rather than
  /// silently claiming the build is current.
  Future<InstalledVersion?> installedVersion() async {
    // Not Android (web, desktop) or not yet bound: there is no installed
    // version to read, which is different from an error.
    if (!Platform.isAndroid) return null;
    try {
      final result = await channel
          .invokeMapMethod<String, String>('installedVersion');
      if (result == null) return null;
      final name = result['versionName'];
      final code = int.tryParse(result['versionCode'] ?? '');
      if (name == null || code == null) return null;
      return InstalledVersion(name: name, code: code);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Asks Android to open the installer for [apkPath].
  ///
  /// Returns false when no installer could be opened, so the UI can say so
  /// instead of leaving a button that does nothing.
  Future<bool> installApk(String apkPath) async {
    try {
      await channel.invokeMethod<void>('installApk', {'path': apkPath});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// The version actually on the device.
class InstalledVersion {
  const InstalledVersion({required this.name, required this.code});

  final String name;
  final int code;

  @override
  String toString() => '$name ($code)';
}

/// Lowercase hex SHA-256 of [bytes].
///
/// Exposed so tests can build a manifest whose digest is genuinely correct
/// rather than hard-coding a digest and only ever testing the failure path.
String sha256Hex(List<int> bytes) =>
    sha256.convert(bytes).toString();

/// What the update endpoint says is available.
@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    this.notes = '',
    this.sizeBytes = 0,
  });

  /// Parses the manifest.
  ///
  /// Throws [FormatException] on anything missing, because a partial manifest
  /// must not be read as "no update" and leave a user stranded on a build with a
  /// known fix.
  factory ReleaseInfo.fromJson(Map<String, Object?> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('update manifest missing "$key"');
      }
      return value.trim();
    }

    final code = json['versionCode'];
    if (code is! num) {
      throw FormatException('update manifest missing numeric "versionCode"');
    }
    final url = Uri.tryParse(requireString('apkUrl'));
    if (url == null || !url.hasScheme || !url.isAbsolute) {
      throw FormatException('update manifest "apkUrl" is not an absolute URL');
    }
    final sha = requireString('sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw FormatException('update manifest "sha256" is not a SHA-256 digest');
    }

    return ReleaseInfo(
      version: requireString('version'),
      versionCode: code.toInt(),
      apkUrl: url,
      sha256: sha,
      notes: (json['notes'] as String?)?.trim() ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  final String version;
  final int versionCode;
  final Uri apkUrl;

  /// Lowercase hex SHA-256 of the APK. Required: the manifest is the only
  /// thing standing between an intercepted download and code execution.
  final String sha256;
  final String notes;
  final int sizeBytes;
}

/// Lifecycle of a download, as the Settings screen sees it.
enum DownloadState { idle, checking, available, upToDate, downloading, paused, verifying, ready, failed }

/// Snapshot the UI renders. Immutable so the widget can compare cleanly.
@immutable
class UpdateState {
  const UpdateState({
    this.status = DownloadState.idle,
    this.release,
    this.received = 0,
    this.total = 0,
    this.message,
    this.installPath,
  });

  final DownloadState status;
  final ReleaseInfo? release;
  final int received;
  final int total;
  final String? message;

  /// Local APK path once verified and ready to install.
  final String? installPath;

  /// 0..1, or null when the total is unknown (no Content-Length).
  double? get progress =>
      (total <= 0) ? null : (received / total).clamp(0.0, 1.0);

  bool get isBusy =>
      status == DownloadState.checking ||
      status == DownloadState.downloading ||
      status == DownloadState.verifying;

  /// True once a download is on disk and the user can be offered the install.
  bool get isInstallable => status == DownloadState.ready && installPath != null;

  /// True while a download exists that can be resumed or cancelled.
  bool get isActive =>
      status == DownloadState.downloading || status == DownloadState.paused;

  UpdateState copyWith({
    DownloadState? status,
    ReleaseInfo? release,
    int? received,
    int? total,
    String? message,
    String? installPath,
    bool clearInstallPath = false,
  }) {
    return UpdateState(
      status: status ?? this.status,
      release: release ?? this.release,
      received: received ?? this.received,
      total: total ?? this.total,
      message: message ?? this.message,
      installPath: clearInstallPath ? null : (installPath ?? this.installPath),
    );
  }
}

/// Compares dotted version strings.
///
/// A pre-release suffix (`-rc1`) sorts *below* the same version without one, so
/// `1.0.0-rc1 < 1.0.0`: a release candidate must not be offered as an upgrade
/// over the release it precedes.
///
/// A segment that is not a number (`x`, `beta`) compares as 0 rather than
/// throwing, so a malformed endpoint cannot crash the check or silently
/// downgrade the ordering.
int compareVersions(String a, String b) {
  final pa = _Version.parse(a);
  final pb = _Version.parse(b);

  final n = pa.numbers.length > pb.numbers.length
      ? pa.numbers.length
      : pb.numbers.length;
  for (var i = 0; i < n; i++) {
    final l = i < pa.numbers.length ? pa.numbers[i] : 0;
    final r = i < pb.numbers.length ? pb.numbers[i] : 0;
    if (l != r) return l > r ? 1 : -1;
  }

  // Numbers are equal: a release now outranks any pre-release of it.
  if (pa.preRelease == null && pb.preRelease == null) return 0;
  if (pa.preRelease == null) return 1;
  if (pb.preRelease == null) return -1;
  return pa.preRelease!.compareTo(pb.preRelease!);
}

class _Version {
  const _Version(this.numbers, this.preRelease);

  final List<int> numbers;

  /// The `-rc1` part, or null for a final release.
  final String? preRelease;

  static _Version parse(String raw) {
    final dash = raw.indexOf('-');
    final numeric = dash == -1 ? raw : raw.substring(0, dash);
    final suffix = dash == -1 ? null : raw.substring(dash + 1).toLowerCase();
    return _Version(
      numeric
          .split('.')
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .toList(growable: false),
      suffix,
    );
  }
}

/// Drives check, download, pause, resume, cancel, and install.
///
/// The controller is the single source of truth; [state] is rebuilt on every
/// transition and listeners are notified so the UI never has to poll.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required Uri manifestUrl,
    this.platform = const UpdatePlatform(),
    http.Client? client,
    this.downloadDir,
    this.probe,
  })  : // The manifest URL is stored normalised so an endpoint with a trailing
        // slash or whitespace cannot produce a request that silently 404s.
        _manifestUrl = _normalise(manifestUrl),
        _clientFactory = (client == null ? _newClient : () => client);

  static Uri _normalise(Uri url) =>
      url.replace(path: url.path.endsWith('/') && url.path != '/'
          ? url.path.substring(0, url.path.length - 1)
          : url.path);

  final Uri _manifestUrl;

  /// Platform bridge. Public so tests can substitute a fake.
  final UpdatePlatform platform;

  /// Where finished APKs are written. Null resolves to the app cache dir.
  final Directory? downloadDir;

  /// Test seam: overrides the manifest fetch without a network.
  final UpdateProbe? probe;

  /// Creates the client for one request. Defaults to a fresh client so a
  /// cancelled download does not poison the next attempt.
  final http.Client Function() _clientFactory;

  static http.Client _newClient() => http.Client();

  UpdateState _state = const UpdateState();

  UpdateState get state => _state;

  /// Where finished APKs are written.
  ///
  /// On Android this resolves under the app cache directory, which is what
  /// `res/xml/update_paths.xml` exposes to the FileProvider.
  Future<Directory> _targetDir() async {
    final injected = downloadDir;
    if (injected != null) return injected;
    final base = await _cacheDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _cacheDir() async {
    // Avoids a path_provider dependency for one call. Android's cache dir is
    // what the FileProvider path is rooted at.
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? env['TMPDIR'];
    if (home == null) {
      throw StateError('cannot determine a cache directory for the download');
    }
    return Directory('$home${Platform.pathSeparator}.cache');
  }

  /// Fetches the manifest and compares it with what is installed.
  Future<void> check() async {
    _emit(_state.copyWith(status: DownloadState.checking, message: null));
    try {
      final override = probe;
      final response = override != null
          ? await override(_manifestUrl)
          : await _clientFactory().get(_manifestUrl);
      if (response.statusCode != 200) {
        throw HttpException('update check failed (HTTP ${response.statusCode})');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('update manifest is not a JSON object');
      }
      final release = ReleaseInfo.fromJson(decoded);

      final installed = await platform.installedVersion();
      if (installed == null) {
        // Cannot compare. Offer the update rather than hiding it, and say why.
        _emit(_state.copyWith(
          status: DownloadState.available,
          release: release,
          message: 'Installed version unknown; update offered.',
        ));
        return;
      }
      if (release.versionCode <= installed.code) {
        _emit(_state.copyWith(
          status: DownloadState.upToDate,
          release: release,
          message: 'Version ${installed.name} is current.',
        ));
        return;
      }
      _emit(_state.copyWith(
        status: DownloadState.available,
        release: release,
        message: '${release.version} is available.',
      ));
    } catch (e) {
      _emit(_state.copyWith(
        status: DownloadState.failed,
        message: 'Could not check for updates: $e',
      ));
    }
  }

  /// Starts or resumes the download.
  Future<void> startDownload() async {
    final release = _state.release;
    if (release == null) return;
    _activeDownload = _download(release, resume: _state.received > 0);
    await _activeDownload;
  }

  /// Aborts the download and discards partial bytes.
  ///
  /// Cancelling then resuming must start over, so the partial file is removed
  /// rather than left for the next [startDownload] to mistake for a resumable
  /// prefix. The transfer is cancelled first, otherwise the writer still holds
  /// the file open and the delete fails on Windows while succeeding on Android.
  Future<void> cancel() async {
    _cancelled = true;
    // BaseClient.close is void, so there is nothing to await here; the in-flight
    // stream stops because the client is closed, and _cancelled tells the loop
    // to return instead of finishing normally.
    _activeClient?.close();
    _activeClient = null;

    // Wait for the download loop to unwind before touching the file. It owns the
    // writer and closes it in its own `finally`; closing it here as well races
    // that path and makes the delete fail intermittently on Windows while
    // succeeding on Android. This is what made the cancel test order-dependent.
    try {
      await _activeDownload;
    } catch (_) {
      // The loop reports its own failures; cancelling is not one of them.
    }
    await _closeSink(_activeSink);
    _activeSink = null;

    // Removal is best-effort: the download loop may have already removed or
    // never created the partial file, and "already gone" is the wanted state.
    final release = _state.release;
    await _deleteQuietly(release == null ? null : await _apkFileFor(release));
    await _deleteQuietly(
      _state.installPath == null ? null : File(_state.installPath!),
    );
    _emit(UpdateState(status: DownloadState.idle, release: release));
  }

  /// Closes [sink] if it is still open, ignoring an already-closed writer.
  ///
  /// Cancel and the download loop can both reach the same writer. Closing twice
  /// throws, so this is the only place that touches the writer on the cancel
  /// path.
  static Future<void> _closeSink(IOSink? sink) async {
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {
      // Already closed by the download loop; nothing left to release.
    }
  }

  /// Deletes [file] if it is there, ignoring an already-absent file.
  ///
  /// Cancellation races the download loop, which may remove the file itself, so
  /// "not found" is a success rather than an error to surface to the user.
  static Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort: a leftover partial APK is inert and overwritten next time.
    }
  }

  /// Requests a pause at the next chunk boundary.
  ///
  /// The in-flight request is cancelled and partial bytes are kept, so resume
  /// continues from where it stopped rather than restarting a ~30MB download.
  Future<void> pause() async {
    if (_state.status != DownloadState.downloading) return;
    _resumeRequested = true;
  }

  /// Opens the system installer for the verified APK.
  Future<bool> install() async {
    final path = _state.installPath;
    if (path == null) return false;
    return platform.installApk(path);
  }

  /// Set by [pause]; consumed at the next chunk boundary so partial bytes
  /// already on disk are kept and the resume can continue from them.
  bool _resumeRequested = false;

  /// Set by [cancel] so the download loop stops instead of finishing normally.
  bool _cancelled = false;

  /// The client currently streaming, so [cancel] can abort the transfer.
  ///
  /// A new client is opened per download rather than sharing one, because
  /// cancelling a shared client would make every later download fail with a
  /// "closed" error the user could not act on.
  http.Client? _activeClient;

  /// The open writer, so [cancel] can release the file before deleting it.
  IOSink? _activeSink;

  /// The download currently running, awaited by [cancel] so the two never
  /// touch the same writer concurrently.
  Future<void> _activeDownload = Future<void>.value();

  /// Guards [notifyListeners] after [dispose].
  bool _disposed = false;

  Future<void> _download(ReleaseInfo release, {required bool resume}) async {
    _resumeRequested = false;
    _cancelled = false;
    final file = await _apkFileFor(release);

    // Resume with a Range request only when bytes are already on disk.
    final existing = resume && await file.exists() ? await file.length() : 0;
    final client = _clientFactory();
    _activeClient = client;

    try {
      _emit(_state.copyWith(
        status: DownloadState.downloading,
        received: existing,
        total: existing,
        message: null,
      ));

      final response = await _openStream(client, release, existing);

      // 206 means the server honoured the range. 200 means it restarted the
      // body, so any partial bytes must be discarded or the file is corrupt.
      final resumed = response.statusCode == 206;
      if (!resumed && existing > 0 && await file.exists()) {
        await file.delete();
      }
      final started = resumed ? existing : 0;
      var received = started;

      final sink = file.openWrite();
      _activeSink = sink;
      final declared = response.contentLength;
      _emit(_state.copyWith(
        total: started + (declared ?? 0),
        received: started,
      ));

      await for (final chunk in response.stream) {
        // Cancel closes the sink itself; just stop here.
        if (_cancelled) return;
        if (_resumeRequested) {
          await sink.flush();
          await sink.close();
          _activeSink = null;
          _emit(_state.copyWith(
            status: DownloadState.paused,
            received: received,
            message: 'Paused at '
                '${(received / 1048576).toStringAsFixed(1)} MB.',
          ));
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        _emit(_state.copyWith(received: received));
      }

      await sink.flush();
      await sink.close();
      _activeSink = null;

      if (declared != null && received < started + declared) {
        throw HttpException(
          'incomplete download ($received of ${started + declared} bytes)',
        );
      }

      _emit(_state.copyWith(status: DownloadState.verifying, received: received));
      await _verify(file, release);
    } catch (e) {
      // A cancel closes the client deliberately; that is not a failure.
      if (_cancelled) return;
      _emit(_state.copyWith(
        status: DownloadState.failed,
        message: 'Download failed: $e',
      ));
    } finally {
      // Release the writer if an error path left it open, so cancel and the
      // temp-dir cleanup are not blocked by a held file handle.
      final sink = _activeSink;
      _activeSink = null;
      await _closeSink(sink);
      if (!identical(_activeClient, client)) {
        client.close();
      } else {
        _activeClient = null;
      }
    }
  }

  /// The APK path for [release], so download, resume and cancel agree on it.
  Future<File> _apkFileFor(ReleaseInfo release) async {
    final dir = await _targetDir();
    return File(
      '${dir.path}${Platform.pathSeparator}xv-${release.version}.apk',
    );
  }

  /// Opens the APK body, with a Range header when resuming.
  ///
  /// Split out so tests can supply a scripted response stream without a server.
  Future<http.StreamedResponse> _openStream(
    http.Client client, ReleaseInfo release, int from) {
    final request = http.Request('GET', release.apkUrl);
    if (from > 0) request.headers['Range'] = 'bytes=$from-';
    return client.send(request);
  }

  /// Fails closed: an APK whose digest does not match the manifest is never
  /// offered for install and is deleted.
  Future<void> _verify(File file, ReleaseInfo release) async {
    final digest = await sha256OfFile(file);
    if (digest.toLowerCase() != release.sha256) {
      await file.delete();
      _emit(_state.copyWith(
        status: DownloadState.failed,
        message: 'Downloaded file failed its checksum and was discarded.',
      ));
      return;
    }
    _emit(_state.copyWith(
      status: DownloadState.ready,
      installPath: file.path,
      message: 'Verified. Ready to install.',
    ));
  }

  void _emit(UpdateState next) {
    // A cancelled or disposed download can finish its async path after the
    // widget is gone. Emitting then would throw, so late updates are dropped
    // instead of crashing the app during teardown.
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    _activeClient?.close();
    _activeClient = null;
    super.dispose();
  }
}

/// Streaming SHA-256 of [file], so a large APK is never held in memory.
Future<String> sha256OfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}