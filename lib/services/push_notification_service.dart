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

    // Luister naar token refresh
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

    // Luister naar berichten (background/terminated: via top-level handler)
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

    // Check of app geopend werd via notification (cold start)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationPayload(initialMessage);
    }

    // Eerste token ophalen
    await _registerCurrentToken();
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
      _localPush!.show(title: title, body: body);
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

  /// Logout: token van server verwijderen (backend ondersteunt dit).
  Future<void> unregister() async {
    _lastRegisteredToken = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _auth.removeListener(_onAuthChanged);
    _tapController.close();
  }
}
