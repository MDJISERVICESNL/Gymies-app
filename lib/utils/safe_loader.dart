import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// SafeLoader — Graceful degradation helper
/// ─────────────────────────────────────────
/// Laadt data met fallback waarde als de call faalt.
/// Logt errors naar Sentry voor niet-auth fouten.
///
/// Gebruik:
/// ```dart
/// final bookings = await SafeLoader.load(
///   () => api.getBookings(),
///   fallback: <Booking>[],
///   label: 'bookings',
/// );
/// ```
class SafeLoader {
  /// Voer een async call uit met graceful fallback.
  /// Bij falen wordt [fallback] geretourneerd en de error gelogd.
  static Future<T> load<T>({
    required Future<T> Function() loader,
    required T fallback,
    String label = 'data',
    bool reportToSentry = true,
  }) async {
    try {
      return await loader();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SafeLoader] $label laden mislukt: $e');
      }

      // Rapporteer naar Sentry (skip 401 auth errors)
      if (reportToSentry && !_isAuthError(e)) {
        Sentry.captureException(
          e,
          stackTrace: st,
          hint: Hint.withMap({'label': label}),
        );
      }

      return fallback;
    }
  }

  /// Laad meerdere resources tegelijk met individuele fallbacks.
  /// Anders dan Future.wait, faalt dit niet als één call faalt.
  ///
  /// ```dart
  /// final [bookings, notifications, stats] = await SafeLoader.loadAll([
  ///   SafeLoad(() => api.getBookings(), []),
  ///   SafeLoad(() => api.getNotifications(), []),
  ///   SafeLoad(() => api.getStats(), {}),
  /// ]);
  /// ```
  static Future<List<dynamic>> loadAll(List<SafeLoad> loaders) async {
    return Future.wait(
      loaders.map((l) => load(
        loader: l.loader,
        fallback: l.fallback,
        label: l.label,
        reportToSentry: l.reportToSentry,
      )),
      eagerError: false,
    );
  }

  static bool _isAuthError(Object error) {
    final str = error.toString().toLowerCase();
    return str.contains('401') || str.contains('unauthorized');
  }
}

/// Data class voor SafeLoader.loadAll()
class SafeLoad<T> {
  final Future<T> Function() loader;
  final T fallback;
  final String label;
  final bool reportToSentry;

  const SafeLoad(
    this.loader,
    this.fallback, {
    this.label = 'data',
    this.reportToSentry = true,
  });
}
