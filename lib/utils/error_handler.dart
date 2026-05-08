import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../services/api_client.dart';
import '../l10n/generated/app_localizations.dart';

/// Centrale error handler voor API calls in screens.
/// Toont een gebruiksvriendelijke SnackBar en logt naar Sentry.
///
/// Gebruik:
/// ```dart
/// try {
///   final data = await context.read<GymiesApi>().someCall();
///   // verwerk data
/// } catch (e, st) {
///   if (!mounted) return;
///   GymiesErrorHandler.handle(context, e, st);
/// }
/// ```
class GymiesErrorHandler {
  GymiesErrorHandler._();

  /// Toont een SnackBar met het foutbericht. Stuurt non-401/429 fouten naar Sentry.
  static void handle(BuildContext context, Object error, [StackTrace? stack]) {
    final message = _userMessage(error);
    final statusCode = error is ApiException ? error.statusCode : 0;

    // 401 wordt al afgehandeld door ApiClient._on401 (auto-logout)
    // 429 is een in-flight guard — geen foutmelding nodig
    if (statusCode == 401 || statusCode == 429) return;

    // Toon SnackBar
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: statusCode >= 500 ? 5 : 3),
          action: statusCode >= 500
              ? SnackBarAction(
                  label: 'Opnieuw',
                  onPressed: () {
                    // Caller moet zelf retry implementeren via een callback.
                    // De SnackBar verdwijnt — caller kan opnieuw proberen.
                  },
                )
              : null,
        ),
      );
    }

    // Log naar Sentry (alleen server errors en onverwachte fouten)
    if (statusCode == 0 || statusCode >= 500) {
      Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) {
          scope.setTag('error.type', statusCode == 0 ? 'network' : 'server');
          if (error is ApiException) {
            scope.setContexts('error', {
              'statusCode': statusCode,
              'message': error.message,
            });
          }
        },
      );
    }
  }

  /// Variant met retry callback — toont "Opnieuw" knop die de callback uitvoert.
  static void handleWithRetry(
    BuildContext context,
    Object error,
    VoidCallback onRetry, [
    StackTrace? stack,
  ]) {
    final message = _userMessage(error);
    final statusCode = error is ApiException ? error.statusCode : 0;

    if (statusCode == 401 || statusCode == 429) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Opnieuw',
            onPressed: onRetry,
          ),
        ),
      );
    }

    if (statusCode == 0 || statusCode >= 500) {
      Sentry.captureException(error, stackTrace: stack);
    }
  }

  static String _userMessage(Object error) {
    if (error is ApiException) return error.message;
    final msg = error.toString();
    if (msg.contains('SocketException') || msg.contains('TimeoutException')) {
      return 'Geen verbinding. Probeer het later opnieuw.';
    }
    return 'Er ging iets mis. Probeer het later opnieuw.';
  }
}
