/// Live-backend wiring, idle behind [mockMode].
///
/// In MOCK_MODE every method returns immediately so the app runs with zero
/// Supabase/Firebase configuration. The live path (T5.7) is stubbed:
/// [init] will initialize Supabase + Firebase, [registerPushToken] will
/// publish the FCM token, and [activeSignalStream] will subscribe to the
/// active consensus signal. Nothing here is called with live credentials
/// until `mockMode` is flipped to false.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Guarded backend facade: safe to call in any mode.
abstract final class BackendService {
  static bool _ready = false;

  /// True once live backends initialized (always false in MOCK_MODE).
  static bool get isReady => _ready;

  /// Initializes Supabase + Firebase. No-op while [mockMode] is true.
  static Future<void> init() async {
    if (mockMode) {
      debugPrint('BackendService: MOCK_MODE — backends idle.');
      return;
    }
    // LIVE (T5.7 stub): requires SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY via
    // --dart-define and a provisioned Firebase project before enabling.
    await Firebase.initializeApp();
    await Supabase.initialize(
      url: const String.fromEnvironment('SUPABASE_URL'),
      publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
    await registerPushToken();
    _ready = true;
  }

  /// Registers the FCM token for signal notifications. No-op in MOCK_MODE.
  static Future<void> registerPushToken() async {
    if (mockMode) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;
    await Supabase.instance.client.from('push_tokens').upsert({
      'token': token,
      'platform': defaultTargetPlatform.name,
    });
  }

  /// Subscribes to the active consensus row. Throws in MOCK_MODE by
  /// design — callers must branch on [mockMode] first.
  static Stream<Map<String, Object?>> activeSignalStream() {
    if (mockMode) {
      throw StateError('activeSignalStream requires live mode.');
    }
    return Supabase.instance.client
        .from('consensus_signals')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.isEmpty ? <String, Object?>{} : rows.first);
  }
}
