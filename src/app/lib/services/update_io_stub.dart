/// Web fallback for the `dart:io` surface used by `update_service.dart`.
///
/// Imported ONLY when `dart:io` is unavailable (web), via:
/// ```dart
/// import 'update_io_stub.dart' if (dart.library.io) 'dart:io' as io;
/// ```
/// Every member throws if touched: the in-app updater is Android-only and
/// `main.dart` provides no `UpdateService` on web (no manifest URL is passed
/// to web builds), so reaching any of these is a programming error, never a
/// runtime case. The stubs exist so the file compiles for browser testing;
/// they must never gain real behavior, because real behavior here would mean
/// downloading APKs in a browser.
library;

/// Mirror of [Platform] members used by the updater. Always non-Android.
abstract final class Platform {
  static bool get isAndroid => false;
  static String get pathSeparator => '/';
}

/// Mirror of [HttpException]. Thrown, never caught by type here.
class HttpException implements Exception {
  const HttpException(this.message);
  final String message;
  @override
  String toString() => 'HttpException: $message';
}

/// Mirror of [FileMode] constants. Not abstract: the two constants below
/// instantiate it (exactly like the real one).
final class FileMode {
  static const append = FileMode._('append');
  static const write = FileMode._('write');
  const FileMode._(this.name);
  final String name;
}

/// Unreachable file handle. Every member throws.
class File {
  File(String path) {
    throw UnsupportedError('File is unavailable on web ()');
  }
  String get path => throw UnsupportedError('File is unavailable on web');
  Future<bool> exists() => throw UnsupportedError('File is unavailable on web');
  Future<int> length() => throw UnsupportedError('File is unavailable on web');
  Future<FileSystemEntity> delete() =>
      throw UnsupportedError('File is unavailable on web');
  IOSink openWrite({FileMode mode = FileMode.write}) =>
      throw UnsupportedError('File is unavailable on web');
  Stream<List<int>> openRead([int? start, int? end]) =>
      throw UnsupportedError('File is unavailable on web');
}

/// Unreachable directory handle. Every member throws.
class Directory {
  Directory(String path) {
    throw UnsupportedError('Directory is unavailable on web ($path)');
  }
  static Directory get systemTemp =>
      throw UnsupportedError('Directory is unavailable on web');
  String get path => throw UnsupportedError('Directory is unavailable on web');
  Future<bool> exists() => throw UnsupportedError('Directory is unavailable on web');
  Future<Directory> create({bool recursive = false}) =>
      throw UnsupportedError('Directory is unavailable on web');
}

/// Unreachable sink. Every member throws.
abstract class IOSink {
  void add(List<int> data) =>
      throw UnsupportedError('IOSink is unavailable on web');
  Future<void> flush() =>
      throw UnsupportedError('IOSink is unavailable on web');
  Future<void> close() => throw UnsupportedError('IOSink is unavailable on web');
}

/// Unreachable entity base for [File.delete]'s return type.
abstract class FileSystemEntity {}
