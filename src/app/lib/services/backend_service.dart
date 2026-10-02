/// Live-backend wiring, idle behind [mockMode].
///
/// In MOCK_MODE every method returns immediately so the app runs with zero
/// Supabase/Firebase configuration. The live path (T5.7) is stubbed:
/// [init] will initialize Supabase + Firebase, [registerPushToken] will
/// publish the FCM token, and [activeSignalStream] will subscribe to the
/// active consensus signal. Nothing here is called with live credentials
/// until `mockMode` is flipped to false.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Guarded backend facade: safe to call in any mode.
abstract final class BackendService {
  static bool _ready = false;

  /// True once live backends initialized (always false in MOCK_MODE).
  static bool get isReady => _ready;

  /// Last init failure, surfaced so a half-configured live build explains
  /// itself instead of appearing to show (fixture) data.
  static String? _error;
  static String? get error => _error;

  /// Initializes Supabase. No-op while [mockMode] is true.
  ///
  /// Firebase/FCM is intentionally NOT initialized here: push delivery needs
  /// the FCM server key on the Edge Function side and a real device
  /// subscription, neither of which exists yet. Initializing it would throw on
  /// platforms without Firebase config and take the whole app down for a
  /// feature that is not switched on.
  static Future<void> init() async {
    if (mockMode) {
      debugPrint('BackendService: MOCK_MODE — backends idle.');
      return;
    }
    if (!liveConfigured) {
      _error = 'LIVE mode requires SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY '
          'via --dart-define.';
      debugPrint('BackendService: $_error');
      return;
    }
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );
      _ready = true;
      _error = null;
      debugPrint('BackendService: Supabase live.');
    } catch (e) {
      _error = 'Supabase init failed: $e';
      debugPrint('BackendService: $_error');
    }
  }

  /// Registers the FCM token for signal notifications.
  ///
  /// Disabled until an FCM server key is configured on the Edge Function side;
  /// calling it is safe and simply reports false.
  static Future<bool> registerPushToken() async {
    // FCM is not wired yet: the tick Edge Function only dispatches when a
    // server key is present, and there is no push_tokens table. Returning
    // false keeps the door open without pretending the feature works.
    if (mockMode) return false;
    debugPrint('BackendService: FCM not configured — push registration skipped.');
    return false;
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
