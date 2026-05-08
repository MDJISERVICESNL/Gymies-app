import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:gymies_app/services/auth_service.dart';
import 'package:gymies_app/services/gymies_api.dart';
import 'package:gymies_app/services/local_push_service.dart';

/// Remote push via FCM (Android) / APNs (iOS via FCM).
/// Voor meldingen wanneer de app gesloten is.
class PushNotificationService {
  PushNotificationService({
    required AuthService auth,
    required GymiesApi api,
    LocalPushService? localPush,
  })  : _auth = auth,
        _api = api,
        _localPush = localPush {
    _auth.addListener(_onAuthChanged);
  }

  final AuthService _auth;
  final GymiesApi _api;
  final LocalPushService? _localPush;
  bool _initialized = false;
  String? _lastRegisteredToken;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  /// Stream controller voor deep-link navigatie vanuit notification taps.
  final _tapController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNotificationTap => _tapController.stream;

  bool get isInitialized => _initialized;

  /// Initialiseer FCM. Firebase.initializeApp() is al aangeroepen in main().
  Future<void> start() async {
    if (_initialized) return;
    _initialized = true;
    if (kDebugMode) debugPrint('[PushNotification] FCM start');

    try {
      // iOS: vraag toestemming
      if (Platform.isIOS) {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (kDebugMode) {
          debugPrint('[PushNotification] iOS permission: ${settings.authorizationStatus}');
        }
      }

      // BUG FIX: Add error handling for stream subscriptions
      // Luister naar token refresh
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
        _registerToken,
        onError: (e) {
          if (kDebugMode) debugPrint('[PushNotification] tokenRefresh stream error: $e');
        },
      );

      // Luister naar berichten (background/terminated: via top-level handler)
      _foregroundSub = FirebaseMessaging.onMessage.listen(
        _onForegroundMessage,
        onError: (e) {
          if (kDebugMode) debugPrint('[PushNotification] foregroundMessage stream error: $e');
        },
      );

      _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _onNotificationTap,
        onError: (e) {
          if (kDebugMode) debugPrint('[PushNotification] messageOpenedApp stream error: $e');
        },
      );

      // Check of app geopend werd via notification (cold start)
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationPayload(initialMessage);
      }

      // Eerste token ophalen
      await _registerCurrentToken();
    } catch (e) {
      if (kDebugMode) debugPrint('[PushNotification] start() error: $e');
      _initialized = false;
    }
  }

  void _onAuthChanged() {
    if (!_auth.isLoggedIn) {
      _lastRegisteredToken = null;
    } else if (_initialized) {
      _registerCurrentToken();
    }
  }

  Future<void> _registerCurrentToken() async {
    if (!_auth.isLoggedIn) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PushNotification] getToken failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    if (!_auth.isLoggedIn || token == _lastRegisteredToken) return;
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      await _api.registerDeviceToken(token: token, platform: platform);
      _lastRegisteredToken = token;
      if (kDebugMode) debugPrint('[PushNotification] Token registered ($platform)');
    } catch (e) {
      if (kDebugMode) debugPrint('[PushNotification] register failed: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('[PushNotification] Foreground: ${message.notification?.title}');
    }
    // Toon lokale notificatie zodat gebruiker de melding ook in-app ziet
    final title = message.notification?.title ?? 'GYMIES';
    final body = message.notification?.body ?? '';
    if (body.isNotEmpty && _localPush != null) {
      _localPush.show(title: title, body: body);
    }
  }

  void _onNotificationTap(RemoteMessage message) {
    _handleNotificationPayload(message);
  }

  void _handleNotificationPayload(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;
    if (kDebugMode) {
      debugPrint('[PushNotification] Tap payload: $data');
    }

    // Emit navigatie-event voor subscribers (bijv. main.dart luistert mee
    // en navigeert op basis van type/deep_link in de payload).
    _tapController.add(Map<String, dynamic>.from(data));
  }

  /// Logout: token van server verwijderen en lokaal verwijderen.
  /// Stuurt eerst een DELETE request naar de backend, vervolgens verwijdert lokaal.
  Future<void> unregister() async {
    // Stap 1: Informeer backend om token te verwijderen (voordat we het lokaal verwijderen)
    if (_lastRegisteredToken != null && _lastRegisteredToken!.isNotEmpty) {
      try {
        await _api.unregisterDeviceToken(token: _lastRegisteredToken!);
        if (kDebugMode) debugPrint('[PushNotification] Token unregistered from backend');
      } catch (e) {
        // Best-effort: fout bij backend unregister mag logout niet blokkeren
        if (kDebugMode) debugPrint('[PushNotification] Backend unregister failed: $e');
      }
    }

    // Stap 2: Verwijder lokaal token
    _lastRegisteredToken = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
      if (kDebugMode) debugPrint('[PushNotification] Local token deleted');
    } catch (e) {
      // Fail-open: Token deletion can fail silently on logout
      if (kDebugMode) debugPrint('[PushNotificationService] Local token deletion failed: $e');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _auth.removeListener(_onAuthChanged);
    // BUG FIX: Ensure tap controller is not already closed before closing
    if (!_tapController.isClosed) {
      _tapController.close();
    }
  }
}
