import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/timing_constants.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import '../utils/notification_display_helper.dart';
import '../models/booking.dart';
import '../models/trainer_summary.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../services/notification_realtime_service.dart';
import '../services/api_client.dart';
import '../services/action_retry_queue_service.dart';
import '../services/subscription_entitlements_service.dart';
import 'login_register_screen.dart';
import 'trainer_sessions_screen.dart';
import 'trainer_finance_screen.dart';
import 'trainer_notifications_screen.dart';
import 'trainer_onboarding_screen.dart';
import 'client_support_screen.dart';
import 'trainer_check_in_scanner_screen.dart';
import 'trainer_packages_screen.dart';
import 'trainer_widget_qr_screen.dart';
import 'shells/trainer_shell.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Trainer-dashboard met overzicht en hamburgermenu.
class TrainerDashboardScreen extends StatefulWidget {
  const TrainerDashboardScreen({
    super.key,
    this.onAvatarTap,
    this.avatarLabel,
  });

  final VoidCallback? onAvatarTap;
  final String? avatarLabel;

  @override
  State<TrainerDashboardScreen> createState() => _TrainerDashboardScreenState();
}

class _TrainerDashboardScreenState extends State<TrainerDashboardScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  TrainerSummary? _summary;
  List<Map<String, dynamic>> _recentNotifications = [];
  bool _loading = true;
  String? _error;
  bool _onboardingCompleted = true;
  bool _onboardingBannerDismissed = false; // Gebruiker heeft "Later" geklikt
  int _queuePendingCount = 0;
  int _queueFailedCount = 0;
  int _queueHighRetryCount = 0;
  bool _queueFlushing = false;
  Timer? _checkInWindowTimer;
  Timer? _countdownTimer;        // Live countdown – ticks elke seconde
  bool _hasGymAccess = false;
  late AnimationController _staggerController;
  bool _hasAnimated = false;

  NotificationRealtimeService? _realtime({bool listen = false}) {
    try {
      return Provider.of<NotificationRealtimeService>(context, listen: listen);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _load();
    _startCheckInTimer();
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {}); // Herlaad build voor live countdown
    });
  }

  void _startCheckInTimer() {
    _checkInWindowTimer?.cancel();
    _checkInWindowTimer = Timer.periodic(TimingConstants.checkInTimerInterval, (_) {
      if (!mounted) return;
      setState(() {}); // Herlaad build voor QR-knop zichtbaarheid
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _checkInWindowTimer?.cancel();
      _countdownTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startCheckInTimer();
      _startCountdownTimer();
      if (mounted) _load();
    }
  }

  /// Stagger animation helper: creates a curved interval for item at [index].
  Animation<double> _staggerAnimation(int index, {int total = 6}) {
    final start = (index / total).clamp(0.0, 1.0);
    final end = ((index + 1.5) / total).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkInWindowTimer?.cancel();
    _countdownTimer?.cancel();
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      final api = context.read<GymiesApi>();
      final apiClient = context.read<ApiClient>();
      if (kDebugMode) {
        debugPrint('[TrainerDashboard] _load start | isLoggedIn=${auth.isLoggedIn} tokenLen=${auth.token?.length ?? 0} apiClientToken=${apiClient.authToken?.length ?? 0}');
      }
      if (auth.isLoggedIn && auth.token != null && auth.token!.isNotEmpty) {
        apiClient.setAuthToken(auth.token);
        if (kDebugMode) debugPrint('[TrainerDashboard] setAuthToken called – apiClient heeft nu ${apiClient.authToken?.length ?? 0} chars');
      } else if (kDebugMode) {
        debugPrint('[TrainerDashboard] GEEN setAuthToken – auth.token is leeg of null');
      }
      final entitlements = context.read<SubscriptionEntitlementsService>();
      if (kDebugMode) debugPrint('[TrainerDashboard] GET trainer/summary...');
      final summary = await api.getTrainerSummary();
      if (kDebugMode) debugPrint('[TrainerDashboard] getTrainerSummary OK');
      await entitlements.load();
      final tier = entitlements.tier?.toLowerCase() ?? '';
      bool hasGymAccess = entitlements.suiteEnabled || tier == 'studio' || tier == 'elite';
      if (!hasGymAccess) {
        try {
          await api.getGymMembership();
          hasGymAccess = true;
        } on ApiException catch (e) {
          if (e.statusCode == 401) rethrow;
        } catch (e) {
          if (kDebugMode) debugPrint('[TrainerDashboard] Gym membership check fout: $e');
        }
      }
      int unread = 0;
      List<Map<String, dynamic>> notifications = const [];
      int queuePending = 0;
      int queueFailed = 0;
      int queueHighRetry = 0;
      try {
        unread = await api.getNotificationUnreadCount();
      } on ApiException catch (e) {
        if (e.statusCode == 401) rethrow;
        unread = 0;
      } catch (e) {
        if (kDebugMode) debugPrint('[TrainerDashboard] Unread count ophalen fout: $e');
        unread = 0;
      }
      try {
        notifications = await api.getNotifications();
      } on ApiException catch (e) {
        if (e.statusCode == 401) rethrow;
        notifications = const [];
      } catch (e) {
        if (kDebugMode) debugPrint('[TrainerDashboard] Notifications laden fout: $e');
        notifications = const [];
      }
      bool onboardingCompleted = false;
      try {
        final onboarding = await api.getOnboardingStatus();
        final step = onboarding['current_step'] as String? ?? '';
        final userData = context.read<AuthService>().user;
        final isVerified = (userData?['trainer_approved_at'] != null) || (onboarding['trainer_verified_at'] != null);
        onboardingCompleted = step == 'completed' || isVerified;
      } on ApiException catch (e) {
        if (e.statusCode == 401) rethrow;
        // Bij API fout: toon banner zodat trainer onboarding niet mist
        onboardingCompleted = false;
        if (kDebugMode) debugPrint('[TrainerDashboard] Onboarding status check mislukt: ${e.message}');
      } catch (e) {
        if (kDebugMode) debugPrint('[TrainerDashboard] Onboarding status check fout: $e');
        onboardingCompleted = false;
      }
      if (kDebugMode) {
        try {
          final stats = await ActionRetryQueueService.getQueueStats();
          queuePending = stats['pending'] ?? 0;
          queueFailed = stats['failed'] ?? 0;
          queueHighRetry = stats['high_retry'] ?? 0;
        } catch (e) {
          if (kDebugMode) debugPrint('[TrainerDashboard] Queue stats ophalen fout: $e');
          queuePending = 0;
          queueFailed = 0;
          queueHighRetry = 0;
        }
      }
      if (mounted) {
        _realtime()?.setUnreadCount(unread);
        setState(() {
          _summary = summary;
          _recentNotifications = _prioritizedNotifications(notifications);
          _queuePendingCount = queuePending;
          _queueFailedCount = queueFailed;
          _queueHighRetryCount = queueHighRetry;
          _onboardingCompleted = onboardingCompleted;
          _hasGymAccess = hasGymAccess;
          _loading = false;
        });
        if (!_hasAnimated) {
          _hasAnimated = true;
          _staggerController.forward();
        }
      }
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[TrainerDashboard] *** ApiException *** ${e.statusCode} – ${e.message}');
      if (mounted) setState(() => _error = e.message);
      if (mounted) setState(() => _loading = false);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[TrainerDashboard] *** Catch *** $e\n$st');
      if (mounted) setState(() => _error = 'Kon gegevens niet laden.');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _userDisplayName() {
    final user = context.read<AuthService>().user;
    if (user == null) return 'trainer';
    final name = user['display_name'] ?? user['first_name'] ?? user['name'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString().trim().split(RegExp(r'\s+')).first;
    }
    final email = user['email']?.toString().trim() ?? '';
    if (email.isNotEmpty) {
      final part = email.split('@').first;
      if (part.isNotEmpty) return part;
    }
    return 'trainer';
  }

  String _avatarInitials() {
    final user = context.read<AuthService>().user;
    if (user == null) return 'T';
    final full = (user['display_name'] ?? user['name'] ?? '').toString().trim();
    final parts = full.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    if (full.isNotEmpty) return full[0].toUpperCase();
    return 'T';
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'Goedenacht';
    if (hour < 12) return 'Goedemorgen';
    if (hour < 18) return 'Goedemiddag';
    return 'Goedenavond';
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
        (route) => false,
      );
    }
  }

  void _pushScreen(Widget screen) {
    Navigator.of(context)
        .push(CupertinoPageRoute(builder: (_) => screen))
        .then((_) => _load());
  }

  void _openOnboarding() {
    Navigator.of(context)
        .push(CupertinoPageRoute(
            builder: (_) => const TrainerOnboardingScreen()))
        .then((_) => _load());
  }

  void _openMySessions() {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const TrainerSessionsScreen()),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const TrainerNotificationsScreen()),
    );
    if (mounted) await _load();
  }

  /// Sessie in check-in venster? (15 min voor start tot 15 min na einde)
  bool _hasSessionInCheckInWindow() {
    final bookings = _summary?.upcomingBookings ?? [];
    final now = DateTime.now();
    for (final b in bookings) {
      final status = b.status.toLowerCase();
      if (status == 'cancelled' || status == 'completed') continue;
      final startWindow = b.scheduledAt.subtract(TimingConstants.checkInWindow);
      final endWindow = b.scheduledAt
          .add(Duration(minutes: b.durationMinutes))
          .add(TimingConstants.checkInWindow);
      if (!now.isBefore(startWindow) && !now.isAfter(endWindow)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openCheckInScanner() async {
    final changed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
          builder: (_) => const TrainerCheckInScannerScreen()),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _flushQueueNow() async {
    if (_queueFlushing) return;
    setState(() => _queueFlushing = true);
    try {
      final sent = await ActionRetryQueueService.flushPending(
        context.read<GymiesApi>(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retry klaar: $sent actie(s) verstuurd')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _queueFlushing = false);
    }
  }

  String _queueHealthLabel() {
    if (_queueFailedCount >= 3 || _queueHighRetryCount > 0) {
      return 'Kritiek: $_queueFailedCount acties falen ($_queueHighRetryCount met hoge retries).';
    }
    if (_queuePendingCount > 0) {
      return '$_queuePendingCount actie(s) wachten op retry.';
    }
    return 'Alle achtergrondacties zijn gesynchroniseerd.';
  }

  Future<void> _openIncidentSupport() async {
    final draft = await ActionRetryQueueService.buildIncidentSupportDraft(
      contextLabel: 'TrainerDashboard',
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientSupportScreen(
          initialType: draft['type'],
          initialSubject: draft['subject'],
          initialMessage: draft['message'],
          initialBookingId: draft['booking_id'],
          initialInvoiceId: draft['invoice_id'],
          openComposerOnStart: true,
        ),
      ),
    );
    if (mounted) await _load();
  }

  bool _isUnread(Map<String, dynamic> item) {
    final unread = mapPick(item, ['unread', 'is_unread']);
    if (unread is bool) return unread;
    if (unread is num) return unread.toInt() == 1;
    return mapStr(item, ['read_at', 'readAt']).isEmpty;
  }

  DateTime _createdAt(Map<String, dynamic> item) {
    final raw = mapStr(item, ['created_at', 'createdAt', 'date']);
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _notificationCategory(Map<String, dynamic> item) {
    final text =
        '${mapStr(item, ['type', 'notification_type', 'category'])} '
                '${mapStr(item, ['title', 'subject'])} '
                '${mapStr(item, ['body', 'message', 'text'])}'
            .toLowerCase();
    if (text.contains('booking') ||
        text.contains('boeking') ||
        text.contains('session') ||
        text.contains('sessie')) {
      return 'Boeking';
    }
    if (text.contains('message') ||
        text.contains('bericht') ||
        text.contains('chat')) {
      return 'Bericht';
    }
    if (text.contains('invoice') ||
        text.contains('factuur') ||
        text.contains('payment') ||
        text.contains('payout') ||
        text.contains('revenue') ||
        text.contains('omzet')) {
      return 'Financieel';
    }
    return 'Update';
  }

  bool _requiresAction(Map<String, dynamic> item) {
    final status = mapStr(item, ['status']).toLowerCase();
    if (status == 'requires_action' || status == 'pending') return true;
    final text =
        '${mapStr(item, ['type', 'notification_type', 'category'])} '
                '${mapStr(item, ['title', 'subject'])} '
                '${mapStr(item, ['body', 'message', 'text'])}'
            .toLowerCase();
    return text.contains('actie') ||
        text.contains('urgent') ||
        text.contains('required') ||
        (text.contains('booking') && _isUnread(item));
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Boeking':
        return Icons.event_rounded;
      case 'Bericht':
        return Icons.chat_bubble_outline_rounded;
      case 'Financieel':
        return Icons.euro_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Boeking':
        return Colors.blue.shade600;
      case 'Bericht':
        return Colors.teal.shade600;
      case 'Financieel':
        return Colors.green.shade600;
      default:
        return GymiesColors.darkBlue;
    }
  }

  List<Map<String, dynamic>> _prioritizedNotifications(
    List<Map<String, dynamic>> source,
  ) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7));
    // Filter: alleen meldingen van de laatste 7 dagen tonen in "Actie nodig"
    final items = source.where((n) => _createdAt(n).isAfter(cutoff)).toList();
    items.sort((a, b) {
      int score(Map<String, dynamic> n) {
        if (_requiresAction(n)) return 0;
        if (_isUnread(n)) return 1;
        return 2;
      }

      final byScore = score(a).compareTo(score(b));
      if (byScore != 0) return byScore;
      return _createdAt(b).compareTo(_createdAt(a));
    });
    return items.take(4).toList();
  }

  /// Mark a single notification as read and remove from dashboard list.
  Future<void> _dismissNotification(Map<String, dynamic> item) async {
    final id = mapStr(item, ['id', 'notification_id']);
    try {
      await context.read<GymiesApi>().markNotificationsRead(
        notificationId: id.isNotEmpty ? id : null,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recentNotifications.removeWhere((n) =>
        mapStr(n, ['id', 'notification_id']) == id);
    });
  }

  /// Mark ALL dashboard notifications as read.
  Future<void> _dismissAllNotifications() async {
    Haptics.selection();
    try {
      // Mark each notification individually for precise backend tracking
      final api = context.read<GymiesApi>();
      for (final n in _recentNotifications) {
        final id = mapStr(n, ['id', 'notification_id']);
        if (id.isNotEmpty) {
          await api.markNotificationsRead(notificationId: id);
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _recentNotifications.clear());
  }

  @override
  Widget build(BuildContext context) {
    final liveUnread = _realtime(listen: true)?.unreadCount ?? 0;
    final effectiveUnread = liveUnread;
    final s = _summary;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          color: GymiesColors.darkBlue,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // ── Avatar met 2 initialen ──
                  GestureDetector(
                    onTap: widget.onAvatarTap,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: GymiesColors.primary,
                      ),
                      child: Center(
                        child: Text(
                          _avatarInitials(),
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_timeGreeting()}, ${_userDisplayName()}',
                          style: GoogleFonts.sora(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE d MMMM', 'nl_NL').format(DateTime.now()),
                          style: GoogleFonts.sora(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasSessionInCheckInWindow())
                    GestureDetector(
                      onTap: _openCheckInScanner,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.qr_code_scanner_rounded, color: Colors.white.withValues(alpha: 0.7), size: 22),
                      ),
                    ),
                  // ── Notification bell with dot ──
                  GestureDetector(
                    onTap: _openNotifications,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(Icons.notifications_outlined, color: Colors.white.withValues(alpha: 0.7), size: 22),
                        if (effectiveUnread > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.red.shade600,
                                shape: BoxShape.circle,
                                border: Border.all(color: GymiesColors.darkBlue, width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: GymiesColors.primary,
        child: CustomScrollView(
          slivers: [
            // ── Onboarding banner ──────────────────────────────────────
            if (!_onboardingCompleted && !_onboardingBannerDismissed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GestureDetector(
                    onTap: _openOnboarding,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.rocket_launch_rounded, color: Colors.amber.shade800, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Activeer je account',
                                      style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Voltooi je onboarding om sessies aan te bieden.',
                                      style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => setState(() => _onboardingBannerDismissed = true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.grey.shade500,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                child: Text('Later', style: GoogleFonts.sora(fontSize: 13)),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _openOnboarding,
                                style: FilledButton.styleFrom(
                                  backgroundColor: GymiesColors.primary,
                                  foregroundColor: GymiesColors.darkBlue,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text('Nu activeren', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Header met stats ───────────────────────────────────────
            SliverToBoxAdapter(
              child: _TrainerHeaderSection(
                summary: s,
                loading: _loading,
                staggerController: _staggerController,
                onTapPending: () => _pushScreen(const TrainerSessionsScreen(initialTabIndex: 0)),
                onTapThisWeek: () => _pushScreen(const TrainerSessionsScreen(initialTabIndex: 1)),
                onTapRevenue: () => _pushScreen(const TrainerFinanceScreen()),
                onNextSessionTap: _openMySessions,
              ),
            ),

            // ── Error state ────────────────────────────────────────────
            if (_error != null)
              SliverToBoxAdapter(
                child: TrainerErrorView(
                  message: _error!,
                  onRetry: _load,
                  onLogout: (_error!.toLowerCase().contains('sessie') ||
                          _error!.toLowerCase().contains('verlopen'))
                      ? _logout
                      : null,
                ),
              )
            else ...[
              // ── Snelle acties ─────────────────────────────────────
              SliverToBoxAdapter(
                child: _FadeSlide(
                  animation: _staggerAnimation(1),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SNELLE ACTIES',
                          style: GoogleFonts.sora(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _QuickAction(
                              icon: Icons.add_rounded,
                              label: 'Nieuwe\nsessie',
                              highlight: true,
                              onTap: () => _pushScreen(const TrainerSessionsScreen()),
                            ),
                            const SizedBox(width: 8),
                            _QuickAction(
                              icon: Icons.inventory_2_outlined,
                              label: 'Pakket\nmaken',
                              onTap: () => _pushScreen(const TrainerPackagesScreen()),
                            ),
                            const SizedBox(width: 8),
                            _QuickAction(
                              icon: Icons.share_outlined,
                              label: 'Deel\nlink',
                              onTap: () => _pushScreen(const TrainerWidgetQrScreen()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Komende sessies header ───────────────────────────────
              SliverToBoxAdapter(
                child: _FadeSlide(
                  animation: _staggerAnimation(2),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                    child: Row(
                      children: [
                        Text(
                          'Vandaag${s != null && s.upcomingBookings.isNotEmpty ? ' · ${s.upcomingBookings.length} sessie${s.upcomingBookings.length == 1 ? '' : 's'}' : ''}',
                          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _openMySessions,
                          child: Text(
                            'Alles bekijken',
                            style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Sessie lijst ─────────────────────────────────────────
              if (_loading && s == null)
                const SliverToBoxAdapter(child: TrainerLoadingView())
              else if (s == null || s.upcomingBookings.isEmpty)
                SliverToBoxAdapter(
                  child: _FadeSlide(
                    animation: _staggerAnimation(3),
                    child: TrainerEmptyState(
                      icon: Icons.event_available,
                      title: 'Geen komende sessies',
                      subtitle: 'Nieuwe boekingen verschijnen automatisch zodra een klant boekt.',
                      actionLabel: 'Open mijn sessies',
                      actionIcon: Icons.event_note_rounded,
                      onAction: _openMySessions,
                      padding: const EdgeInsets.all(24),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    final b = s.upcomingBookings[i];
                    return _FadeSlide(
                      animation: _staggerAnimation(3 + i, total: 3 + s.upcomingBookings.length + 3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                        child: _BookingCard(booking: b, onTap: _openMySessions),
                      ),
                    );
                  }, childCount: s.upcomingBookings.length),
                ),

              // ── Actie nodig header ──────────────────────────────────
              SliverToBoxAdapter(
                child: _FadeSlide(
                  animation: _staggerAnimation(4),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          'Actie nodig',
                          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
                        ),
                        if (_recentNotifications.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_recentNotifications.length}',
                              style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red.shade700),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (_recentNotifications.isNotEmpty)
                          GestureDetector(
                            onTap: _dismissAllNotifications,
                            child: Text(
                              'Wis alles',
                              style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Actie-nodig lijst (CTA-cards) ──────────────────────────
              if (_recentNotifications.isEmpty)
                SliverToBoxAdapter(
                  child: _FadeSlide(
                    animation: _staggerAnimation(5),
                    child: const TrainerEmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Alles bij',
                      subtitle: 'Geen openstaande acties — goed bezig!',
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    final n = _recentNotifications[i];
                    final nId = mapStr(n, ['id', 'notification_id']);
                    final title = NotificationDisplayHelper.displayTitle(n);
                    final body = NotificationDisplayHelper.displayBody(n);
                    final category = _notificationCategory(n);
                    final catIcon = _categoryIcon(category);
                    final catColor = _categoryColor(category);
                    final action = _requiresAction(n);
                    final createdAt = _createdAt(n);
                    final now = DateTime.now();
                    final diff = now.difference(createdAt);
                    String timeLabel;
                    if (diff.inMinutes < 60) {
                      timeLabel = '${diff.inMinutes} min geleden';
                    } else if (diff.inHours < 24) {
                      timeLabel = '${diff.inHours} uur geleden';
                    } else {
                      timeLabel = diff.inDays == 1 ? 'gisteren' : '${diff.inDays} dagen geleden';
                    }
                    return _FadeSlide(
                      animation: _staggerAnimation(5 + i, total: 5 + _recentNotifications.length),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Dismissible(
                          key: ValueKey('notif_$nId\_$i'),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => _dismissNotification(n),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.visibility_off_rounded, color: Colors.grey.shade500, size: 20),
                          ),
                          child: GestureDetector(
                            onTap: () {
                              Haptics.selection();
                              _openNotifications();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade100),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: action
                                          ? Colors.red.shade50
                                          : catColor.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      action ? Icons.priority_high_rounded : catIcon,
                                      color: action ? Colors.red.shade700 : catColor,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$body · $timeLabel',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // ── Inline CTA buttons ──
                                  if (action && category == 'Boeking')
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Bevestig',
                                            style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Afwijs',
                                            style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                                          ),
                                        ),
                                      ],
                                    )
                                  else if (category == 'Bericht')
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Reageer',
                                        style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                                      ),
                                    )
                                  else
                                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }, childCount: _recentNotifications.length),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _TrainerHeaderSection extends StatelessWidget {
  const _TrainerHeaderSection({
    required this.summary,
    required this.loading,
    required this.staggerController,
    this.onTapPending,
    this.onTapThisWeek,
    this.onTapRevenue,
    this.onNextSessionTap,
  });

  final TrainerSummary? summary;
  final bool loading;
  final AnimationController staggerController;
  final VoidCallback? onTapPending;
  final VoidCallback? onTapThisWeek;
  final VoidCallback? onTapRevenue;
  final VoidCallback? onNextSessionTap;

  String _formatRevenue(int cents) {
    final euros = cents / 100;
    if (euros >= 1000) {
      return '€${(euros / 1000).toStringAsFixed(1)}k';
    }
    return '€${euros.toStringAsFixed(euros.truncateToDouble() == euros ? 0 : 2)}';
  }

  Animation<double> _stagger(int index, {int total = 6}) {
    final start = (index / total).clamp(0.0, 1.0);
    final end = ((index + 1.5) / total).clamp(0.0, 1.0);
    return CurvedAnimation(parent: staggerController, curve: Interval(start, end, curve: Curves.easeOut));
  }

  /// Find the next upcoming booking and return live countdown info.
  ({Booking? booking, String timer, String label, double progress}) _nextSession() {
    final bookings = summary?.upcomingBookings ?? [];
    if (bookings.isEmpty) return (booking: null, timer: '', label: '', progress: 0);
    final now = DateTime.now();
    Booking? next;
    for (final b in bookings) {
      if (b.scheduledAt.isAfter(now)) {
        next = b;
        break;
      }
    }
    next ??= bookings.first;
    final diff = next.scheduledAt.difference(now);

    // Live timer string — alleen tonen bij < 24 uur
    String timer;
    if (diff.isNegative) {
      timer = 'Nu';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      final s = diff.inSeconds % 60;
      timer = h > 0
          ? '${h}:' + '${m.toString().padLeft(2, '0')}:' + '${s.toString().padLeft(2, '0')}'
          : '${m}:' + '${s.toString().padLeft(2, '0')}';
    } else {
      timer = 'over ${diff.inDays} dag' + (diff.inDays == 1 ? '' : 'en');
    }

    String label;
    if (diff.isNegative) {
      label = 'Nu bezig';
    } else if (diff.inMinutes < 60) {
      label = 'over ${diff.inMinutes} min';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      label = m > 0 ? 'over ${h}u ${m}min' : 'over ${h} uur';
    } else {
      label = 'over ${diff.inDays} dag${diff.inDays == 1 ? '' : 'en'}';
    }

    // Progress: assume we start tracking from 2 hours before
    const trackWindow = 2 * 60 * 60; // 2 uur in seconden
    final secsLeft = diff.inSeconds.clamp(0, trackWindow);
    final progress = 1.0 - (secsLeft / trackWindow);

    return (booking: next, timer: timer, label: label, progress: progress.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final ns = _nextSession();
    final nextBooking = ns.booking;
    final weekGoal = summary?.weekGoal ?? 10; // Falls back to 10 if API doesn't provide it yet
    final weekCount = summary?.thisWeekCount ?? 0;
    final weekProgress = (weekCount / weekGoal).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: GymiesColors.darkBlue,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Next session banner (live countdown) ──
          if (nextBooking != null) ...[
            _FadeSlide(
              animation: _stagger(0),
              child: GestureDetector(
                onTap: onNextSessionTap,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        GymiesColors.primary.withValues(alpha: 0.14),
                        GymiesColors.primary.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: GymiesColors.primary.withValues(alpha: 0.18)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 14, color: GymiesColors.primary.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Text(
                            'VOLGENDE SESSIE',
                            style: GoogleFonts.sora(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: GymiesColors.primary),
                          ),
                          const Spacer(),
                          Text(
                            ns.timer,
                            style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, height: 1.0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nextBooking.clientName?.isNotEmpty == true ? nextBooking.clientName! : 'Klant',
                              style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.7)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${nextBooking.scheduledAt.hour.toString().padLeft(2, '0')}:${nextBooking.scheduledAt.minute.toString().padLeft(2, '0')}',
                            style: GoogleFonts.sora(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: ns.progress,
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          color: GymiesColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── 2-kolom stats + full-width weekdoel ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: loading && summary == null
                ? Center(
                    key: const ValueKey('loading'),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: GymiesColors.primary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  )
                : _FadeSlide(
                    key: const ValueKey('stats'),
                    animation: _stagger(1),
                    child: Column(
                      children: [
                        // ── Top row: 2 stat cards ──
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () { Haptics.selection(); onTapPending?.call(); },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TE BEVESTIGEN',
                                        style: GoogleFonts.sora(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: Colors.white.withValues(alpha: 0.4)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${summary?.pendingCount ?? 0}',
                                        style: GoogleFonts.sora(fontSize: 26, fontWeight: FontWeight.w700, color: GymiesColors.primary, height: 1.0),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () { Haptics.selection(); onTapRevenue?.call(); },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'OMZET DEZE MAAND',
                                        style: GoogleFonts.sora(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: Colors.white.withValues(alpha: 0.4)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatRevenue(summary?.revenueCents ?? 0),
                                        style: GoogleFonts.sora(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, height: 1.0),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // ── Full-width weekdoel card ──
                        GestureDetector(
                          onTap: () { Haptics.selection(); onTapThisWeek?.call(); },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'WEEKDOEL',
                                      style: GoogleFonts.sora(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: Colors.white.withValues(alpha: 0.4)),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$weekCount / $weekGoal sessies',
                                      style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: weekProgress,
                                    minHeight: 6,
                                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                                    color: GymiesColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, this.onTap});

  final Booking booking;
  final VoidCallback? onTap;

  static const _weekDays = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
  static const _months = [
    'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
    'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
  ];

  String _formatSessionType(String? type) {
    if (type == null || type.isEmpty) return 'Sessie';
    switch (type.toLowerCase()) {
      case 'duo':
        return 'Duo';
      case 'groepsles':
      case 'group':
        return 'Groep';
      case '1-op-1':
      case '1op1':
      case 'personal':
        return 'PT';
      default:
        return '${type[0].toUpperCase()}${type.substring(1)}';
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool _isTomorrow(DateTime date) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day;
  }

  String _dayLabel(DateTime date) {
    if (_isToday(date)) return 'vandaag';
    if (_isTomorrow(date)) return 'morgen';
    return '${_weekDays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final date = booking.scheduledAt;
    final resolvedName = booking.clientName?.isNotEmpty == true
        ? booking.clientName!
        : booking.trainerName;
    final displayName = resolvedName.isNotEmpty ? resolvedName : 'Klant';
    final today = _isToday(date);
    final statusColor = _statusColor(booking.status);
    final typeLabel = _formatSessionType(booking.sessionType);
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap?.call();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: today
                ? GymiesColors.primary.withValues(alpha: 0.5)
                : Colors.grey.shade100,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // ── Tijd badge ──
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: today
                    ? GymiesColors.primary.withValues(alpha: 0.12)
                    : const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    timeStr,
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue, height: 1.1),
                  ),
                  Text(
                    _dayLabel(date),
                    style: GoogleFonts.sora(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: today ? GymiesColors.darkBlue : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Info ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$typeLabel · ${booking.durationMinutes} min',
                    style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Status badge ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusLabel(booking.status),
                style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green.shade700;
      case 'pending':
        return Colors.orange.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      case 'checked_in':
        return Colors.blue.shade700;
      default:
        return GymiesColors.darkBlue;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return 'Bevestigd';
      case 'pending':
        return 'Wachtend';
      case 'cancelled':
        return 'Geannuleerd';
      case 'checked_in':
        return 'Ingecheckt';
      default:
        return status;
    }
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, this.onTap, this.highlight = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Haptics.selection();
          onTap?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: highlight ? GymiesColors.primary.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlight ? GymiesColors.primary.withValues(alpha: 0.3) : Colors.grey.shade200,
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: highlight ? GymiesColors.primary : GymiesColors.darkBlue),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade + slide-up animation wrapper for staggered entrance effects.
class _FadeSlide extends StatelessWidget {
  const _FadeSlide({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
