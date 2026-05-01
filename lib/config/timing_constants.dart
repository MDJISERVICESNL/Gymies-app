/// ──────────────────────────────────────────────────────────────────────────
/// Gymies Timing Constants
/// ──────────────────────────────────────────────────────────────────────────
/// Alle timeouts, intervals, durations en numerieke limieten op één plek.
/// Voorkomt magic numbers verspreid over services en screens.
/// ──────────────────────────────────────────────────────────────────────────

class TimingConstants {
  TimingConstants._();

  // ── API & Netwerk ───────────────────────────────────────────────────────
  static const Duration apiRequestTimeout = Duration(seconds: 20);
  static const Duration getRetryDelay = Duration(milliseconds: 450);
  static const Duration securityCheckTimeout = Duration(milliseconds: 500);

  // ── WebSocket ───────────────────────────────────────────────────────────
  static const Duration wsReconnectDelay = Duration(seconds: 2);
  static const Duration wsReconnectDelayMax = Duration(seconds: 30);
  static const double wsReconnectBackoffMultiplier = 1.5;

  // ── Check-in ────────────────────────────────────────────────────────────
  /// Hoeveel minuten voor/na de sessie een check-in mogelijk is.
  static const Duration checkInWindow = Duration(minutes: 15);
  static const Duration checkInTimerInterval = Duration(seconds: 30);

  // ── Polling & Refresh ───────────────────────────────────────────────────
  static const Duration messagePollInterval = Duration(seconds: 4);
  static const Duration trainerRefreshInterval = Duration(seconds: 5);
  static const Duration clockTickInterval = Duration(seconds: 1);

  // ── Login Security ──────────────────────────────────────────────────────
  /// Minimale lockout-base in seconden bij herhaalde mislukte logins.
  static const int lockoutBaseSeconds = 5;

  /// Maximale lockout in seconden (5 minuten).
  static const int lockoutMaxSeconds = 300;

  /// Timer-interval voor lockout-countdown.
  static const Duration lockTimerInterval = Duration(seconds: 1);

  // ── Booking & Sessies ───────────────────────────────────────────────────
  static const Duration bookingTimeout = Duration(seconds: 10);
  static const Duration slotHoldTickerInterval = Duration(seconds: 1);

  // ── Datumranges ─────────────────────────────────────────────────────────
  /// Maximaal bereik voor datumpicker (1 jaar).
  static const Duration datePickerMaxRange = Duration(days: 365);

  /// Bereik voor 2-jarige datumfilters.
  static const Duration twoYearRange = Duration(days: 365 * 2);

  /// Aantal dagen voor groepssessie filter.
  static const Duration groupSessionFilterRange = Duration(days: 60);

  /// Vervaldatum facturen in dagen.
  static const int invoiceDueDays = 14;

  // ── Paginering ──────────────────────────────────────────────────────────
  static const int itemsPerPage = 20;

  // ── Retry Queue ─────────────────────────────────────────────────────────
  static const int maxRetryHistory = 250;

  // ── Loading Screen ──────────────────────────────────────────────────────
  static const Duration loadingTimeout = Duration(milliseconds: 4500);
  static const Duration loadingFadeIn = Duration(milliseconds: 800);
  static const Duration loadingFadeOut = Duration(milliseconds: 600);
}
