import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// FCM push, wired to be optional: if `google-services.json` isn't present the
/// Firebase init fails, [available] stays false, and the app runs exactly as
/// before (phones poll pending requests when the app opens — design 5f).
///
/// The push payload is routing-only ({type, requestId, pairingId}); it never
/// carries the domain, account, or code. Its only job is to wake the phone.
/// When a request arrives we show a local notification that opens the app; the
/// approval listener then fetches the pending request and shows A11.
/// A one-glance snapshot of the push subsystem, surfaced in Security so a
/// person (or we, from a screenshot) can tell where a silent failure is.
/// [notificationsAllowed] is the OS-level display permission (Android 13+
/// POST_NOTIFICATIONS): a push can arrive and wake us with this off, but no
/// banner will show — a distinct failure from "no token".
typedef PushDiag = ({
  bool available,
  bool hasToken,
  bool notificationsAllowed,
  String? error,
});

class PushService {
  static bool available = false;

  /// The last thing that went wrong bringing push up (Firebase init or
  /// getToken). Null when push is healthy. Shown in the Security diagnostics.
  static String? lastError;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static const _channelId = 'approval_requests';
  static const _channelName = 'Sign-in requests';

  // init() may be called from startup and again from token()/requestPermission()
  // if they run before startup's init resolved (fresh pairing races app boot).
  // Memoise so those callers all await the same one-time initialisation.
  static Future<void>? _initFuture;

  static Future<void> init() => _initFuture ??= _doInit();

  static Future<void> _doInit() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // No google-services.json (or misconfigured) — push disabled, app fine.
      debugPrint('Push disabled (Firebase not configured): $e');
      available = false;
      lastError = 'init: $e';
      return;
    }
    available = true;
    lastError = null;

    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await _ensureLocalReady();

    // App in foreground when the wake arrives: still surface a notification so
    // the user notices; the approval listener also picks the request up live.
    FirebaseMessaging.onMessage.listen((_) => showRequestNotification());
  }

  /// Everything the Security screen needs to explain the push state in one row.
  /// Ensures init has run first, so a fresh boot doesn't read a false negative.
  static Future<PushDiag> diagnose() async {
    await init();
    final tok = available ? await token() : null;
    var allowed = false;
    if (available) {
      try {
        final settings =
            await FirebaseMessaging.instance.getNotificationSettings();
        allowed =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
      } catch (_) {
        allowed = false;
      }
    }
    return (
      available: available,
      hasToken: tok != null,
      notificationsAllowed: allowed,
      error: lastError,
    );
  }

  static Future<void> _ensureLocalReady() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      settings: const InitializationSettings(android: android),
    );
    final android_ = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android_?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Shown when your browser asks for a code',
        importance: Importance.high,
      ),
    );
  }

  static Future<void> showRequestNotification() async {
    await _ensureLocalReady();
    await _local.show(
      id: 1,
      title: 'Your browser needs a code',
      body: 'Tap to approve on your phone',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// Triggers the Android 13+ runtime notification prompt (and iOS later).
  static Future<bool> requestPermission() async {
    await init();
    if (!available) return false;
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  static Future<String?> token() async {
    await init();
    if (!available) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      lastError = 'getToken: $e';
      return null;
    }
  }

  static void onTokenRefresh(void Function(String) cb) {
    if (!available) return;
    FirebaseMessaging.instance.onTokenRefresh.listen(cb);
  }
}

/// Background isolate entry point. Must be a top-level function. It only shows
/// a local notification, so it doesn't need to touch Firebase services beyond
/// init.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // If Firebase can't init here we can't do much; bail quietly.
  }
  await PushService.showRequestNotification();
}
