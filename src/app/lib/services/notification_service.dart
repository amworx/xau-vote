/// Notification permission and delivery wiring.
///
/// # Why permission is not requested on first launch
///
/// Android 13+ shows a one-shot system prompt. Asking during cold start, before
/// the user has seen the app do anything, is the most reliable way to get a
/// permanent denial: the prompt means nothing without context, and a denied
/// permission cannot be re-requested from the system dialog.
///
/// So this asks at the moment the value becomes obvious — when the trader turns
/// an alert on in Settings — which is also the moment Android's own guidance
/// recommends. A second-launch prompt is deliberately NOT used; Settings is the
/// only place we ask.
///
/// # Honesty about delivery
///
/// A token is registered with Supabase so a sender can reach the device, but no
/// FCM server key is configured on the backend yet. [canDeliver] reports that,
/// and Settings says so rather than implying alerts are already arriving. This
/// is the difference between asking for a permission the app can honour and
/// asking for one it cannot.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Handles a notification while the app is in the background or terminated.
@pragma('vm:entry-point')
Future<void> xvFirebaseBackgroundHandler(RemoteMessage message) async {
  // Nothing to do here: OS-delivered notifications are displayed by the system
  // tray. This callback exists so a data-only message can be logged rather than
  // dropped, and so a foreground notification can be shown locally.
  debugPrint('XV background message ${message.messageId}');
}

/// Notification setup, safe to call in any build mode.
class NotificationService {
  NotificationService();

  bool _initialised = false;

  /// True when the OS granted notification permission.
  bool? _granted;

  /// Whether a backend sender can actually reach the device.
  ///
  /// False until an FCM server key is configured server-side. Permission can be
  /// granted while this is false, which is why the two are reported separately.
  bool canDeliver = false;

  bool? get granted => _granted;

  /// Prepares Firebase and creates the alert channel.
  ///
  /// Never throws: a failure here must not stop the app from starting, because
  /// the market data and the scanner do not depend on notifications.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _granted = await isGranted();
    } catch (e) {
      // No Firebase config on this platform/build. Alerts stay unavailable and
      // Settings reports that instead of silently doing nothing.
      debugPrint('NotificationService init failed: $e');
      _granted = false;
    }
  }

  /// Reads the current permission without prompting.
  ///
  /// firebase_messaging 16 removed `isGranted()`; the authoritative answer is
  /// the authorization status on the notification settings.
  Future<bool> isGranted() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      return false;
    }
  }

  /// Asks for permission, but only if it has not been permanently denied.
  ///
  /// Returns the resulting state. `false` can mean "denied" or "unavailable";
  /// the caller explains rather than assuming.
  Future<bool> request() async {
    try {
      await init();
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _granted =
          settings.authorizationStatus == AuthorizationStatus.authorized;
      return _granted ?? false;
    } catch (e) {
      debugPrint('NotificationService request failed: $e');
      _granted = false;
      return false;
    }
  }

  /// The device's FCM token, or null when unavailable.
  ///
  /// Registration is intentionally left to the caller: it needs the Supabase
  /// client and a table to write to, and inventing either would be dishonest.
  Future<String?> token() async {
    try {
      await init();
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }
}