import 'package:flutter/material.dart';

import '../screens/client_sessions_screen.dart';
import '../screens/client_trainer_profile_screen.dart';
import '../screens/password_reset_screen.dart';
import '../screens/trainer_sessions_screen.dart';
import '../screens/trainer_finance_screen.dart';
import '../screens/trainer_messages_screen.dart';
import '../screens/trainer_notifications_screen.dart';
import '../screens/client_messages_screen.dart';
import '../screens/client_invoices_screen.dart';
import '../screens/trainer_subscription_screen.dart';
import '../screens/trainer_onboarding_screen.dart';
import '../screens/client_my_group_sessions_screen.dart';
import '../screens/gym_finance_screen.dart';
import '../screens/gym_register_screen.dart';
import '../services/auth_service.dart';
import 'deep_link_validator.dart';

/// Deep link routes voor gymies://
/// Voorbeelden:
/// - gymies://trainer/sessions?tab=0
/// - gymies://trainer/income
/// - gymies://client/sessions
/// - gymies://client/messages
class DeepLinkService {
  DeepLinkService._();

  /// Base URL voor deep links (voor delen/notificaties).
  static const String scheme = 'gymies';
  static const String baseUrl = '$scheme://';

  // --- Trainer routes ---
  static const String trainerSessions = '${baseUrl}trainer/sessions';
  static const String trainerIncome = '${baseUrl}trainer/income';
  static const String trainerMessages = '${baseUrl}trainer/messages';
  static const String trainerNotifications = '${baseUrl}trainer/notifications';

  // --- Client routes ---
  static const String clientSessions = '${baseUrl}client/sessions';

  /// Buddy-uitnodiging: train met een vriend voor een specifieke sessie.
  static String buddyInviteUrl({
    required String bookingId,
    String? trainerId,
    String? trainerName,
  }) {
    final params = <String, String>{'booking_id': bookingId};
    if (trainerId != null && trainerId.isNotEmpty) params['trainer_id'] = trainerId;
    if (trainerName != null && trainerName.isNotEmpty) {
      params['trainer'] = trainerName;
    }
    // Gebruik Uri class voor correcte encoding van speciale tekens.
    final uri = Uri(scheme: scheme, host: 'buddy', path: '/join', queryParameters: params);
    return uri.toString();
  }
  static const String clientMessages = '${baseUrl}client/messages';
  static const String clientFavorites = '${baseUrl}client/favorites';
  static const String clientInvoices = '${baseUrl}client/invoices';

  /// Bouwt URL voor trainer sessies met tab.
  static String trainerSessionsUrl({int tab = 0}) =>
      '${baseUrl}trainer/sessions?tab=$tab';

  /// Bouwt URL voor client sessies (bijv. na betaling).
  static String clientSessionsUrl({String? bookingId}) {
    if (bookingId != null && bookingId.isNotEmpty) {
      return '${baseUrl}payment/complete?booking_id=$bookingId';
    }
    return clientSessions;
  }

  /// Parseert URI en retourneert het te tonen scherm (of null).
  /// Werkt voor cold start en foreground links.
  static Widget? screenFromUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase().replaceFirst('/', '').trim();
    final tab = int.tryParse(uri.queryParameters['tab'] ?? '') ?? 0;

    // Wachtwoord reset: gymies://wachtwoord-reset?token=X&email=Y
    if (host == 'wachtwoord-reset' || path == 'wachtwoord-reset') {
      final token = uri.queryParameters['token'];
      if (token != null && token.trim().isNotEmpty) {
        return PasswordResetScreen(
          token: token.trim(),
          email: uri.queryParameters['email']?.trim(),
        );
      }
    }

    // Payment return: gymies://payment?booking_id=X of gymies://payment/complete?booking_id=X
    if (host == 'payment' && (path.isEmpty || path == 'complete')) {
      final bookingId = uri.queryParameters['booking_id'];
      if (bookingId != null && bookingId.isNotEmpty) {
        return ClientSessionsScreen(paymentReturnBookingId: bookingId);
      }
      // Geen booking_id: toon sessies-overzicht
      return const ClientSessionsScreen();
    }

    // Group session payment return: gymies://group-payment/complete?participant_id=X
    if (host == 'group-payment' && (path.isEmpty || path == 'complete')) {
      // After paying for group session, go to "Mijn inschrijvingen"
      return const ClientMyGroupSessionsScreen();
    }

    // Mollie Connect success: gymies://mollie-connect/success (terugkeer na OAuth)
    // Note: Role-aware navigation is handled in main.dart and loading_screen.dart
    if (host == 'mollie-connect' && (path.isEmpty || path == 'success')) {
      return const TrainerOnboardingScreen(mollieConnectSuccess: true);
    }

    // Subscription payment return: gymies://subscription/complete?tier=pro
    if (host == 'subscription' && (path.isEmpty || path == 'complete')) {
      final tier = uri.queryParameters['tier']?.trim().toLowerCase();
      if (tier != null && tier.isNotEmpty) {
        return TrainerSubscriptionScreen(paymentReturnTier: tier);
      }
    }

    // Trainer slug: gymies://t/{slug} of gymies.nl/t/{slug}
    if (host == 't' || (host.isEmpty && path.startsWith('t/'))) {
      final segments = uri.pathSegments;
      final rawSlug = segments.length >= 2 ? segments[1] : (segments.isNotEmpty ? segments.first : null);
      // Sanitize: alleen alfanumeriek, hyphens en underscores toegestaan.
      if (rawSlug != null && rawSlug.isNotEmpty) {
        final slug = rawSlug.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '');
        if (slug.isNotEmpty) {
          return ClientTrainerProfileScreen(trainerSlug: slug);
        }
      }
    }

    // Trainer dashboard routes
    if (host == 'trainer') {
      switch (path) {
        case 'sessions':
          return TrainerSessionsScreen(
            initialTabIndex: tab >= 0 && tab < 3 ? tab : 0,
          );
        case 'income':
          return const TrainerFinanceScreen();
        case 'messages':
          return const TrainerMessagesScreen();
        case 'notifications':
          return const TrainerNotificationsScreen();
      }
    }

    // Buddy-uitnodiging: gymies://buddy/join?booking_id=X&trainer_id=Y
    if (host == 'buddy' && path == 'join') {
      final bookingId = uri.queryParameters['booking_id'];
      final trainerId = uri.queryParameters['trainer_id'];
      if (bookingId != null && bookingId.isNotEmpty && trainerId != null && trainerId.isNotEmpty) {
        return ClientTrainerProfileScreen(trainerId: trainerId, buddyBookingId: bookingId);
      }
      if (trainerId != null && trainerId.isNotEmpty) {
        return ClientTrainerProfileScreen(trainerId: trainerId);
      }
      if (bookingId != null && bookingId.isNotEmpty) {
        return ClientSessionsScreen(paymentReturnBookingId: bookingId);
      }
    }

    // Gym registratie: gymies://gym/register?token=X
    if (host == 'gym' && path == 'register') {
      final token = uri.queryParameters['token']?.trim();
      if (token != null && token.isNotEmpty) {
        return GymRegisterScreen(token: token);
      }
    }

    // Client dashboard routes
    if (host == 'client') {
      switch (path) {
        case 'sessions':
          return const ClientSessionsScreen();
        case 'messages':
          return const ClientMessagesScreen();
        case 'favorites':
          // Favorites requires dashboard state (trainers, favoriteIds, callbacks).
          // Deep link to favorites not supported; returns null → app shows default.
          return null;
        case 'invoices':
          return const ClientInvoicesScreen();
      }
    }

    return null;
  }

  /// Bepaalt het juiste scherm voor Mollie Connect success op basis van gebruikersrol.
  /// - Gym owners/managers: navigeren naar GymFinanceScreen
  /// - Trainers: navigeren naar TrainerOnboardingScreen
  static Widget? mollieConnectSuccessScreen(AuthService authService) {
    if (authService.isGymOwner) {
      return const GymFinanceScreen();
    } else if (authService.isTrainer) {
      return const TrainerOnboardingScreen(mollieConnectSuccess: true);
    }
    return null;
  }

  /// Controleert of deze URI een payment/slug link is (bestaande logica).
  static bool isPaymentOrSlug(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'payment') return true;
    if (host == 'group-payment') return true;
    if (host == 'subscription') return true;
    if (host == 'mollie-connect') return true;
    if (host == 't') return true;
    final segs = uri.pathSegments;
    if (segs.isNotEmpty && segs.first.toLowerCase() == 't') return true;
    return false;
  }
}
