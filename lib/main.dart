import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:ui';

import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app_links/app_links.dart';
import 'package:gymies_app/config/app_config.dart';
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
import 'package:gymies_app/services/connectivity_service.dart';
import 'package:gymies_app/services/storefront_cms_provider.dart';
import 'package:gymies_app/services/precache_service.dart';
import 'package:gymies_app/services/optimistic_action_service.dart';
import 'package:gymies_app/services/milestone_service.dart';
import 'package:gymies_app/services/promotion_service.dart';
import 'package:gymies_app/services/subscription_entitlements_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:gymies_app/theme/gymies_theme.dart';
import 'package:gymies_app/utils/haptics.dart';
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
  if (kDebugMode) debugPrint('[FCM Background] ${message.notification?.title}: ${message.notification?.body}');
  // FCM toont de notificatie automatisch via het systeem (iOS/Android).
  // Hier kun je data verwerken, bijv. badge teller bijwerken of lokale cache refreshen.
}

/// Mollie Connect success bij cold start (gymies://mollie-connect/success).
bool _initialMollieConnectSuccess = false;


/// Sentry DSN — override via --dart-define=SENTRY_DSN=https://...
/// Laat leeg om Sentry uit te schakelen (alleen Crashlytics).
const _sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: 'https://ddf226f4c6f9c2a4eb02730d1af99a95@o4511314784354304.ingest.de.sentry.io/4511314816991312');

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ── Sentry Init ──────────────────────────────────────────────
    // Initialiseert Sentry naast Firebase Crashlytics.
    // User context wordt gezet na login (zie AuthService._persist).
    if (_sentryDsn.isNotEmpty) {
      await SentryFlutter.init(
        (options) {
          options.dsn = _sentryDsn;
          options.tracesSampleRate = kDebugMode ? 0.0 : 0.2;
          options.environment = kDebugMode ? 'development' : 'production';
          options.sendDefaultPii = false;
          options.attachScreenshot = !kDebugMode;
          options.diagnosticLevel = SentryLevel.warning;
        },
      );

    }

    // ── Locale voor Nederlandse datumnotatie ──────────────────────
    await initializeDateFormatting('nl_NL', null);

    // ── Haptics (trillingen) instelling laden ──────────────────────
    await Haptics.init();

    // ── Firebase Init (met timeout) ────────────────────────────────
    // Voorkomt dat een hangende Firebase-init de app permanent op wit scherm zet.
    try {
      await Firebase.initializeApp()
          .timeout(const Duration(seconds: 8), onTimeout: () {
        if (kDebugMode) debugPrint('[Init] Firebase.initializeApp() timeout na 8s — ga door zonder Firebase');
        throw TimeoutException('Firebase init timeout');
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Init] Firebase initialisatie mislukt: $e — app start zonder Firebase');
    }

    // ── Crashlytics Init ───────────────────────────────────────────
    // In debug mode: geen crash reports versturen (voorkomt ruis).
    // In release/profile: automatisch alle crashes rapporteren.
    try {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
    } catch (e) {
      if (kDebugMode) debugPrint('[Init] Crashlytics init mislukt: $e');
    }

    // ── HMAC Secret Validatie ──────────────────────────────────────
    // Waarschuwt in release mode als de dev-default HMAC secret actief is.
    AppSecurityService.validateHmacConfiguration();

    // ── Security Check (met timeout) ────────────────────────────────
    // Voer beveiligingschecks uit VOORDAT de app verder laadt.
    // Timeout na 5s: als native plugins hangen, app gewoon doorlaten
    // in plaats van eeuwig wit scherm tonen.
    try {
      final securityResult = await AppSecurityService.instance
          .performFullCheck()
          .timeout(const Duration(seconds: 8), onTimeout: () {
        if (kDebugMode) debugPrint('[Security] performFullCheck() timeout na 8s — app doorlaten');
        return const SecurityCheckResult(isSecure: true);
      });
      if (!securityResult.isSecure) {
        runApp(SecurityBlockedScreen(result: securityResult));
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Security] Security check fout: $e — app doorlaten');
    }

    // Registreer background handler VOOR runApp — verplicht door FCM.
    // Alleen registreren als Firebase succesvol is geïnitialiseerd.
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      if (kDebugMode) debugPrint('[Init] FCM background handler registratie mislukt: $e');
    }

    // ── Crashlytics + Sentry: vang alle fouten op ──────────────
    // Flutter framework fouten (rendering, layout, gestures, etc.)
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (kDebugMode) {
        debugPrint('[FlutterError] ${details.exceptionAsString()}');
      } else {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        Sentry.captureException(details.exception, stackTrace: details.stack);
      }
    };

    // Async fouten die niet door Flutter zelf worden gevangen
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        debugPrint('[PlatformError] $error');
        return false; // Laat debugger het oppakken
      }
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      Sentry.captureException(error, stackTrace: stack);
      return true;
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
    final connectivity = ConnectivityService();
    final localPush = LocalPushService();
    final realtime = NotificationRealtimeService(auth: auth, push: localPush, api: gymApi);
    try {
      await auth.loadStoredAuth().timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          if (kDebugMode) debugPrint('[Init] loadStoredAuth() timeout na 6s — ga door als niet-ingelogd');
        },
      );
    } catch (e) {
      // PlatformException (channel-error) kan voorkomen na hot restart op iOS.
      if (kDebugMode) debugPrint('[Init] Auth laden mislukt: $e');
    }
    try {
      await realtime.start().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          if (kDebugMode) debugPrint('[Init] realtime.start() timeout na 5s — ga door zonder realtime');
        },
      );
    } catch (e) {
      // Realtime mag appstart niet blokkeren.
      if (kDebugMode) debugPrint('[Init] Realtime service fout: $e');
    }
    try {
      await ActionRetryQueueService.flushPending(gymApi).timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          if (kDebugMode) debugPrint('[Init] flushPending() timeout na 4s — overgeslagen');
          return 0;
        },
      );
    } catch (e) {
      // Retry queue mag appstart niet blokkeren.
      if (kDebugMode) debugPrint('[Init] Retry queue flush fout: $e');
    }
    try {
      final pushService = PushNotificationService(auth: auth, api: gymApi, localPush: localPush);
      await pushService.start().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          if (kDebugMode) debugPrint('[Init] pushService.start() timeout na 5s — push niet beschikbaar');
        },
      );
    } catch (e) {
      // Push-notificaties mogen appstart niet blokkeren (Firebase-config kan ontbreken).
      if (kDebugMode) debugPrint('[Init] Push notificatie service fout: $e');
    }

    // Deep link bij cold start (payment, trainer slug, of dashboard routes)
    try {
      final appLinks = AppLinks();
      final uri = await appLinks.getInitialLink().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode) debugPrint('[Init] getInitialLink() timeout na 3s — geen deep link');
          return null;
        },
      );
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
          ChangeNotifierProvider.value(value: connectivity),
          ChangeNotifierProvider(
            create: (_) => SubscriptionEntitlementsService(
              api: gymApi,
              auth: auth,
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => PromotionService(api: gymApi),
          ),
          ChangeNotifierProvider(
            create: (_) => StorefrontCmsProvider(api: gymApi),
          ),
          ChangeNotifierProvider(
            create: (_) => PrecacheService(api: gymApi),
          ),
          ChangeNotifierProvider(
            create: (_) => OptimisticActionService(api: gymApi),
          ),
          ChangeNotifierProvider(
            create: (_) => MilestoneService()..init(),
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
    if (kDebugMode) {
      debugPrint('Uncaught: $error\n$stack');
    } else {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      Sentry.captureException(error, stackTrace: stack);
    }
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
    // Material You: gebruik dynamische kleuren van het systeem (Android 12+),
    // met de Gymies branding als fallback voor oudere devices.
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? _) {
        // Behoud Gymies gold als primary — meng optioneel met systeem accent
        final theme = gymiesTheme.copyWith(
          colorScheme: lightDynamic != null
              ? lightDynamic.copyWith(
                    primary: GymiesColors.primary,
                    onPrimary: GymiesColors.darkBlue,
                  )
              : null,
        );

        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: AppConfig.appName,
          theme: theme,
          locale: const Locale('nl', 'NL'),
          supportedLocales: const [
            Locale('nl', 'NL'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
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
      },
    );
  }
}
