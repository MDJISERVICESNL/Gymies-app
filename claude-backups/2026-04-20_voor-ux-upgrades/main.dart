import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gymies_app/screens/client_sessions_screen.dart';
import 'package:gymies_app/screens/client_trainer_profile_screen.dart';
import 'package:gymies_app/screens/loading_screen.dart';
import 'package:gymies_app/screens/security_blocked_screen.dart';
import 'package:gymies_app/services/deep_link_service.dart';
import 'package:gymies_app/services/api_client.dart';
import 'package:gymies_app/services/app_security_service.dart';
import 'package:gymies_app/services/auth_service.dart';
import 'package:gymies_app/services/gymies_api.dart';
import 'package:gymies_app/services/local_push_service.dart';
import 'package:gymies_app/services/notification_realtime_service.dart';
import 'package:gymies_app/services/push_notification_service.dart';
import 'package:gymies_app/services/action_retry_queue_service.dart';
import 'package:gymies_app/services/promotion_service.dart';
import 'package:gymies_app/services/subscription_entitlements_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:gymies_app/theme/gymies_theme.dart';
import 'package:gymies_app/screens/login_register_screen.dart';

/// Booking-ID van gymies://payment/complete?booking_id=X (app cold-start).
String? _initialPaymentBookingId;

/// Trainer slug van gymies.nl/t/{slug} of gymies://t/{slug} (app cold-start).
String? _initialTrainerSlug;

/// Buddy-uitnodiging bij cold start (gymies://buddy/join?booking_id=X&trainer_id=Y).
Uri? _initialBuddyUri;

/// Dashboard deep link bij cold start (gymies://trainer/sessions, gymies://client/messages, etc.).
Uri? _initialDashboardUri;

/// Wachtwoord reset bij cold start (gymies://wachtwoord-reset?token=X&email=Y).
Uri? _initialPasswordResetUri;

/// Subscription payment return bij cold start (gymies://subscription/complete?tier=pro).
String? _initialSubscriptionTier;

/// Background message handler — wordt aangeroepen door FCM als de app gesloten is.
/// Moet een top-level functie zijn (niet in een class).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase moet opnieuw geïnitialiseerd worden in de background isolate.
  await Firebase.initializeApp();
  debugPrint('[FCM Background] ${message.notification?.title}: ${message.notification?.body}');
  // FCM toont de notificatie automatisch via het systeem (iOS/Android).
  // Hier kun je data verwerken, bijv. badge teller bijwerken of lokale cache refreshen.
}

/// Mollie Connect success bij cold start (gymies://mollie-connect/success).
bool _initialMollieConnectSuccess = false;


void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    // ── Security Check ──────────────────────────────────────────────
    // Voer ALLE beveiligingschecks uit VOORDAT de app verder laadt.
    // Bij een bedreiging (root, emulator, debugger, hooking) wordt de app
    // volledig geblokkeerd met een security screen.
    final securityResult = await AppSecurityService.instance.performFullCheck();
    if (!securityResult.isSecure) {
      runApp(SecurityBlockedScreen(result: securityResult));
      return;
    }

    // Registreer background handler VOOR runApp — verplicht door FCM.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Voorkom dat onafgevangen fouten de app crashen (vermindert "Lost connection")
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[FlutterError] ${details.exceptionAsString()}');
    };

    final navigatorKey = GlobalKey<NavigatorState>();

    final api = ApiClient();
    final gymApi = GymiesApi(apiClient: api);
    final auth = AuthService(apiClient: api);
    api.setTokenProvider(() => auth.token);

    // Bij 401 (verlopen/ongeldige sessie): automatisch uitloggen en naar login navigeren.
    // Voorkomt dat de gebruiker een kapotte dashboard ziet met handmatige "Log opnieuw in" knop.
    api.setOn401(() {
      auth.logout();
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
        (route) => false,
      );
    });
    final localPush = LocalPushService();
    final realtime = NotificationRealtimeService(auth: auth, push: localPush, api: gymApi);
    try {
      await auth.loadStoredAuth();
    } catch (_) {
      // PlatformException (channel-error) kan voorkomen na hot restart op iOS.
    }
    try {
      await realtime.start();
    } catch (_) {
      // Realtime mag appstart niet blokkeren.
    }
    try {
      await ActionRetryQueueService.flushPending(gymApi);
    } catch (_) {
      // Retry queue mag appstart niet blokkeren.
    }
    try {
      final pushService = PushNotificationService(auth: auth, api: gymApi);
      await pushService.start();
    } catch (_) {
      // Push-notificaties mogen appstart niet blokkeren (Firebase-config kan ontbreken).
    }

    // Deep link bij cold start (payment, trainer slug, of dashboard routes)
    try {
      final appLinks = AppLinks();
      final uri = await appLinks.getInitialLink();
      if (uri != null) {
        final host = uri.host.toLowerCase();
        _initialPaymentBookingId = _parsePaymentBookingIdFromUri(uri);
        _initialTrainerSlug ??= _parseTrainerSlugFromUri(uri);
        // Buddy-uitnodiging of dashboard routes of wachtwoord reset
        if (host == 'buddy') {
          _initialBuddyUri = uri;
        } else if (host == 'wachtwoord-reset') {
          _initialPasswordResetUri = uri;
        } else if (host == 'mollie-connect') {
          _initialMollieConnectSuccess = true;
        } else if (!DeepLinkService.isPaymentOrSlug(uri)) {
          _initialDashboardUri = uri;
        }
      }
    } catch (_) {
      // App links kan falen op sommige platforms
    }

    runApp(
      MultiProvider(
        providers: [
          Provider.value(value: api),
          Provider.value(value: gymApi),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: realtime),
          ChangeNotifierProvider(
            create: (_) => SubscriptionEntitlementsService(
              api: gymApi,
              auth: auth,
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => PromotionService(api: gymApi),
          ),
        ],
        child: GymiesApp(navigatorKey: navigatorKey),
      ),
    );

    // Luister naar deep links wanneer app in foreground komt
    final appLinks = AppLinks();
    appLinks.uriLinkStream.listen((uri) {
      final host = uri.host.toLowerCase();
      // Buddy-uitnodiging: altijd tonen (ook voor niet-ingelogde vrienden)
      if (host == 'buddy') {
        final screen = DeepLinkService.screenFromUri(uri);
        if (screen != null) {
          navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => screen));
        }
        return;
      }
      // Wachtwoord reset: altijd tonen (geen login vereist)
      if (host == 'wachtwoord-reset') {
        final screen = DeepLinkService.screenFromUri(uri);
        if (screen != null) {
          navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => screen));
        }
        return;
      }
      // Dashboard routes
      final screen = DeepLinkService.screenFromUri(uri);
      if (screen != null) {
        if (!auth.isLoggedIn) return;
        if (host == 'trainer' && !auth.isTrainer) return;
        if (host == 'client' && (auth.isTrainer || auth.isAdmin)) return;
        navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => screen));
        return;
      }
      // Subscription payment return (trainer)
      if (host == 'subscription') {
        final screen = DeepLinkService.screenFromUri(uri);
        if (screen != null && auth.isLoggedIn && auth.isTrainer) {
          navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => screen));
        }
        return;
      }
      // Mollie Connect success (trainer)
      if (host == 'mollie-connect') {
        final screen = DeepLinkService.screenFromUri(uri);
        if (screen != null && auth.isLoggedIn && auth.isTrainer) {
          navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => screen));
        }
        return;
      }
      // Fallback: payment return
      final bookingId = _parsePaymentBookingIdFromUri(uri);
      if (bookingId != null) {
        if (!auth.isLoggedIn || auth.isTrainer || auth.isAdmin) return;
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ClientSessionsScreen(
              paymentReturnBookingId: bookingId,
            ),
          ),
        );
        return;
      }
      // Fallback: trainer slug
      final trainerSlug = _parseTrainerSlugFromUri(uri);
      if (trainerSlug != null && trainerSlug.isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ClientTrainerProfileScreen(trainerSlug: trainerSlug),
          ),
        );
      }
    });
  }, (error, stack) {
    // WebSocket-errors worden al afgehandeld in NotificationRealtimeService – voorkom spam.
    final msg = error.toString();
    if (msg.contains('WebSocket') ||
        msg.contains('was not upgraded to websocket')) {
      return;
    }
    debugPrint('Uncaught: $error\n$stack');
  });
}

/// Haalt booking_id uit gymies://payment/complete?booking_id=X
String? _parsePaymentBookingIdFromUri(Uri uri) {
  return uri.queryParameters['booking_id'];
}

/// Haalt trainer slug uit gymies.nl/t/{slug} of gymies://t/{slug}
String? _parseTrainerSlugFromUri(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length >= 2 && segments[0] == 't') {
    return segments[1];
  }
  if (segments.length == 1 && segments[0].isNotEmpty && segments[0] != 't') {
    return segments[0];
  }
  if (uri.host == 't' && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first;
  }
  return null;
}

class GymiesApp extends StatelessWidget {
  const GymiesApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'GYMIES',
      theme: gymiesTheme,
      home: LoadingScreen(
        initialPaymentBookingId: _initialPaymentBookingId,
        initialTrainerSlug: _initialTrainerSlug,
        initialBuddyUri: _initialBuddyUri,
        initialDashboardUri: _initialDashboardUri,
        initialPasswordResetUri: _initialPasswordResetUri,
        initialSubscriptionTier: _initialSubscriptionTier,
        initialMollieConnectSuccess: _initialMollieConnectSuccess,
      ),
    );
  }
}
