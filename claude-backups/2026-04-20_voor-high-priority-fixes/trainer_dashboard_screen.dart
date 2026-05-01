import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../config/timing_constants.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
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
import 'trainer_agenda_screen.dart';
import 'trainer_income_screen.dart';
import 'trainer_messages_screen.dart';
import 'trainer_notifications_screen.dart';
import 'trainer_profile_screen.dart';
import 'trainer_subscription_screen.dart';
import 'trainer_onboarding_screen.dart';
import 'client_support_screen.dart';
import 'trainer_settings_screen.dart';
import 'trainer_clients_screen.dart';
import 'trainer_packages_screen.dart';
import 'trainer_group_sessions_screen.dart';
import 'trainer_check_in_scanner_screen.dart';
import 'gym_dashboard_screen.dart';
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
    with WidgetsBindingObserver {
  TrainerSummary? _summary;
  List<Map<String, dynamic>> _recentNotifications = [];
  bool _loading = true;
  String? _error;
  bool _onboardingCompleted = true; // Default true zodat we geen banner tonen bij fout
  int _queuePendingCount = 0;
  int _queueFailedCount = 0;
  int _queueHighRetryCount = 0;
  bool _queueFlushing = false;
  Timer? _checkInWindowTimer;
  bool _hasGymAccess = false;

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
    _load();
    _startCheckInTimer();
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
    } else if (state == AppLifecycleState.resumed) {
      _startCheckInTimer();
      if (mounted) _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkInWindowTimer?.cancel();
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
      bool hasGymAccess = tier == 'studio' || tier == 'elite'; // Studio (voorheen Elite) heeft gym dashboard
      if (!hasGymAccess) {
        try {
          await api.getGymMembership();
          hasGymAccess = true;
        } on ApiException catch (e) {
          if (e.statusCode == 401) rethrow;
        } catch (_) {}
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
      } catch (_) {
        unread = 0;
      }
      try {
        notifications = await api.getNotifications();
      } on ApiException catch (e) {
        if (e.statusCode == 401) rethrow;
        notifications = const [];
      } catch (_) {
        notifications = const [];
      }
      bool onboardingCompleted = true;
      try {
        final onboarding = await api.getOnboardingStatus();
        final step = onboarding['current_step'] as String? ?? '';
        onboardingCompleted = step == 'completed';
      } on ApiException catch (e) {
        if (e.statusCode == 401) rethrow;
        onboardingCompleted = true;
      } catch (_) {
        onboardingCompleted = true;
      }
      if (kDebugMode) {
        try {
          final stats = await ActionRetryQueueService.getQueueStats();
          queuePending = stats['pending'] ?? 0;
          queueFailed = stats['failed'] ?? 0;
          queueHighRetry = stats['high_retry'] ?? 0;
        } catch (_) {
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

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
        (route) => false,
      );
    }
  }

  void _navigateTo(Widget screen) {
    Navigator.of(context).pop(); // Sluit drawer
    Navigator.of(context)
        .push(CupertinoPageRoute(builder: (_) => screen))
        .then((_) => _load()); // Herlaad na terugkomen
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

  void _openSubscription() {
    Navigator.of(context).push(
      CupertinoPageRoute(
          builder: (_) => const TrainerSubscriptionScreen()),
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

  List<Map<String, dynamic>> _prioritizedNotifications(
    List<Map<String, dynamic>> source,
  ) {
    final items = [...source];
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

  @override
  Widget build(BuildContext context) {
    final liveUnread = _realtime(listen: true)?.unreadCount ?? 0;
    // Realtime is bron van waarheid: bij mark-read wordt die direct bijgewerkt
    final effectiveUnread = liveUnread;
    final s = _summary;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      drawer: Builder(
        builder: (ctx) {
          final entitlements = context.watch<SubscriptionEntitlementsService>();
          final hasSuite = entitlements.suiteEnabled;
          final tierLabel = TrainerSubscriptionScreen.tierDisplayLabel(entitlements.tier);
          return _TrainerDrawer(
            userDisplayName: _userDisplayName(),
            pendingCount: s?.pendingCount ?? 0,
            hasSuite: hasSuite,
            tierLabel: tierLabel,
            onSubscription: _openSubscription,
            onMySessions: () => _navigateTo(const TrainerSessionsScreen()),
            onMessages: () => _navigateTo(const TrainerMessagesScreen()),
            onNotifications: () => _navigateTo(const TrainerNotificationsScreen()),
            onAgenda: () => _navigateTo(const TrainerAgendaScreen()),
            onIncome: () => _navigateTo(const TrainerIncomeScreen()),
            onClients: () => _navigateTo(const TrainerClientsScreen()),
            onPackages: () => _navigateTo(const TrainerPackagesScreen()),
            onGroupSessions: () => _navigateTo(const TrainerGroupSessionsScreen()),
            onProfile: () => _navigateTo(const TrainerProfileScreen()),
            onSupport: () => _navigateTo(const ClientSupportScreen()),
            onSettings: () => _navigateTo(const TrainerSettingsScreen()),
            hasGymAccess: _hasGymAccess,
            onGymDashboard: () => _navigateTo(const GymDashboardScreen()),
            onLogout: _logout,
          );
        },
      ),
      appBar: GymiesAppBar(
        title: 'GYMIES Trainer',
        actions: [
          if (_hasSessionInCheckInWindow())
            IconButton(
              tooltip: 'Scan check-in QR',
              onPressed: _openCheckInScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (effectiveUnread > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        effectiveUnread > 99 ? '99+' : '$effectiveUnread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Meldingen',
            onPressed: _openNotifications,
          ),
        ],
        onAvatarTap: widget.onAvatarTap,
        avatarLabel: widget.avatarLabel,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: GymiesColors.primary,
        child: CustomScrollView(
          slivers: [
            if (!_onboardingCompleted)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Material(
                    color: Colors.amber.shade50,
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _openOnboarding,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.amber.shade800),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Activeer je account',
                                    style: GoogleFonts.fjallaOne(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: GymiesColors.darkBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Volledig je onboarding om sessies aan te kunnen bieden.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios, size: 16, color: GymiesColors.darkBlue),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: _TrainerHeaderSection(
                userDisplayName: _userDisplayName(),
                summary: s,
                loading: _loading,
                onTapPending: () => _navigateTo(const TrainerSessionsScreen(initialTabIndex: 0)),
                onTapThisWeek: () => _navigateTo(const TrainerSessionsScreen(initialTabIndex: 1)),
                onTapCompleted: () => _navigateTo(const TrainerSessionsScreen(initialTabIndex: 2)),
                onTapRevenue: () => _navigateTo(const TrainerIncomeScreen()),
              ),
            ),
            if (kDebugMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Card(
                    color: (_queueFailedCount > 0 || _queueHighRetryCount > 0)
                        ? Colors.orange.shade50
                        : Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                (_queueFailedCount > 0 ||
                                        _queueHighRetryCount > 0)
                                    ? Icons.warning_amber_rounded
                                    : Icons.cloud_done_rounded,
                                color:
                                    (_queueFailedCount > 0 ||
                                        _queueHighRetryCount > 0)
                                    ? Colors.orange.shade800
                                    : Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text('Operationele status'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(_queueHealthLabel()),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: _queueFlushing
                                    ? null
                                    : _flushQueueNow,
                                child: Text(
                                  _queueFlushing ? 'Bezig...' : 'Retry nu',
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_queueFailedCount >= 3 ||
                                  _queueHighRetryCount > 0)
                                FilledButton(
                                  onPressed: _openIncidentSupport,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.orange.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Meld incident'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Komende sessies',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openMySessions,
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        label: const Text('Facturen opstellen'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'Via Mijn sessies > Voltooid > Factuur opstellen',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ),
              if (_loading && s == null)
                const SliverToBoxAdapter(child: TrainerLoadingView())
              else if (s == null || s.upcomingBookings.isEmpty)
                SliverToBoxAdapter(
                  child: TrainerEmptyState(
                    icon: Icons.event_available,
                    title: 'Geen komende sessies',
                    subtitle:
                        'Nieuwe boekingen verschijnen automatisch zodra een klant boekt.',
                    actionLabel: 'Open mijn sessies',
                    actionIcon: Icons.event_note_rounded,
                    onAction: _openMySessions,
                    padding: const EdgeInsets.all(24),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    final upcoming = s.upcomingBookings;
                    final b = upcoming[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: _BookingCard(booking: b),
                    );
                  }, childCount: s.upcomingBookings.length),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Prioriteit meldingen',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _openNotifications,
                        child: const Text('Alles bekijken'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_recentNotifications.isEmpty)
                const SliverToBoxAdapter(
                  child: TrainerEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Geen prioriteit meldingen',
                    subtitle: 'Nieuwe belangrijke updates verschijnen hier.',
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    final n = _recentNotifications[i];
                    final title = mapStr(n, ['title', 'subject']).isNotEmpty
                        ? mapStr(n, ['title', 'subject'])
                        : 'Melding';
                    final body = mapStr(n, ['body', 'message', 'text']).isNotEmpty
                        ? mapStr(n, ['body', 'message', 'text'])
                        : '-';
                    final category = _notificationCategory(n);
                    final unread = _isUnread(n);
                    final action = _requiresAction(n);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: Card(
                        child: ListTile(
                          onTap: _openNotifications,
                          leading: Icon(
                            action
                                ? Icons.priority_high_rounded
                                : (unread
                                      ? Icons.notifications_active_outlined
                                      : Icons.notifications_none_outlined),
                            color: action ? Colors.red.shade700 : null,
                          ),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$category · $body',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: unread
                              ? const Icon(Icons.brightness_1, size: 10)
                              : const Icon(Icons.chevron_right),
                        ),
                      ),
                    );
                  }, childCount: _recentNotifications.length),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _TrainerDrawer extends StatelessWidget {
  const _TrainerDrawer({
    required this.userDisplayName,
    required this.pendingCount,
    required this.hasSuite,
    required this.tierLabel,
    required this.onSubscription,
    required this.onMySessions,
    required this.onMessages,
    required this.onNotifications,
    required this.onAgenda,
    required this.onIncome,
    required this.onClients,
    required this.onPackages,
    required this.onGroupSessions,
    required this.onProfile,
    required this.onSupport,
    required this.onSettings,
    this.hasGymAccess = false,
    this.onGymDashboard,
    required this.onLogout,
  });

  final String userDisplayName;
  final int pendingCount;
  final bool hasSuite;
  final String tierLabel;
  final VoidCallback onSubscription;
  final VoidCallback onMySessions;
  final VoidCallback onMessages;
  final VoidCallback onNotifications;
  final VoidCallback onAgenda;
  final VoidCallback onIncome;
  final VoidCallback onClients;
  final VoidCallback onPackages;
  final VoidCallback onGroupSessions;
  final VoidCallback onProfile;
  final VoidCallback onSupport;
  final VoidCallback onSettings;
  final bool hasGymAccess;
  final VoidCallback? onGymDashboard;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(
                        AppConfig.appName,
                        style: GoogleFonts.fjallaOne(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: GymiesColors.primary,
                        ),
                      ),
                      if (tierLabel != 'Starter') ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: onSubscription,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: GymiesColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: GymiesColors.primary.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Text(
                              tierLabel,
                              style: GoogleFonts.fjallaOne(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: onProfile,
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: GymiesColors.primary
                              .withValues(alpha: 0.3),
                          child: Text(
                            userDisplayName.isNotEmpty
                                ? userDisplayName[0].toUpperCase()
                                : 'T',
                            style: GoogleFonts.fjallaOne(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userDisplayName,
                                style: GoogleFonts.fjallaOne(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: GymiesColors.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Profiel bekijken',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: GymiesColors.primary
                                      .withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: GymiesColors.primary.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerTile(
                  icon: Icons.event_available_rounded,
                  label: 'Mijn sessies',
                  trailing: pendingCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: GymiesColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$pendingCount',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                        )
                      : null,
                  onTap: onMySessions,
                ),
                _DrawerTile(
                  icon: Icons.calendar_month_rounded,
                  label: 'Agenda',
                  onTap: onAgenda,
                ),
                _DrawerTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Berichten',
                  onTap: onMessages,
                ),
                _DrawerTile(
                  icon: Icons.notifications_outlined,
                  label: 'Meldingen',
                  onTap: onNotifications,
                ),
                _DrawerTile(
                  icon: Icons.euro_rounded,
                  label: 'Inkomsten',
                  onTap: onIncome,
                ),
                if (hasSuite) ...[
                  _DrawerTile(
                    icon: Icons.people_alt_outlined,
                    label: 'Klanten',
                    onTap: onClients,
                  ),
                  _DrawerTile(
                    icon: Icons.inventory_2_outlined,
                    label: 'Pakketten',
                    onTap: onPackages,
                  ),
                  _DrawerTile(
                    icon: Icons.groups_rounded,
                    label: 'Groepslessen',
                    onTap: onGroupSessions,
                  ),
                ],
                _DrawerTile(
                  icon: Icons.support_agent_rounded,
                  label: 'Support',
                  onTap: onSupport,
                ),
                if (hasGymAccess && onGymDashboard != null)
                  _DrawerTile(
                    icon: Icons.business_rounded,
                    label: 'Gym Dashboard',
                    onTap: onGymDashboard!,
                  ),
                const Divider(height: 24, indent: 16, endIndent: 16),
                _DrawerTile(
                  icon: Icons.settings_rounded,
                  label: 'Instellingen',
                  onTap: onSettings,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Builder(
            builder: (context) {
              final isAndroid = defaultTargetPlatform == TargetPlatform.android;
              final logoutButton = Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onLogout,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 21),
                  label: Text(
                    'Uitloggen',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
              if (isAndroid) {
                return SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                  child: logoutButton,
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                child: logoutButton,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: false,
      minVerticalPadding: 8,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: GymiesColors.darkBlue),
      title: Text(
        label,
        style: GoogleFonts.fjallaOne(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: GymiesColors.darkBlue,
        ),
      ),
      trailing:
          trailing ??
          const Icon(Icons.chevron_right, color: GymiesColors.darkBlue),
      onTap: onTap,
    );
  }
}

class _TrainerHeaderSection extends StatelessWidget {
  const _TrainerHeaderSection({
    required this.userDisplayName,
    required this.summary,
    required this.loading,
    this.onTapPending,
    this.onTapThisWeek,
    this.onTapCompleted,
    this.onTapRevenue,
  });

  final String userDisplayName;
  final TrainerSummary? summary;
  final bool loading;
  final VoidCallback? onTapPending;
  final VoidCallback? onTapThisWeek;
  final VoidCallback? onTapCompleted;
  final VoidCallback? onTapRevenue;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: GymiesColors.darkBlue,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hallo, $userDisplayName',
            style: GoogleFonts.fjallaOne(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: GymiesColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: loading && summary == null
                ? const Center(
                    key: ValueKey('loading'),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: GymiesColors.primary,
                        ),
                      ),
                    ),
                  )
                : GridView.count(
                    key: const ValueKey('stats'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.0,
                    children: [
                      _StatCard(
                        icon: Icons.pending_actions_rounded,
                        label: 'Te bevestigen',
                        subtitle: '${summary?.pendingCount ?? 0}',
                        onTap: onTapPending,
                      ),
                      _StatCard(
                        icon: Icons.today_rounded,
                        label: 'Deze week',
                        subtitle: '${summary?.thisWeekCount ?? 0}',
                        onTap: onTapThisWeek,
                      ),
                      _StatCard(
                        icon: Icons.check_circle_rounded,
                        label: 'Voltooid',
                        subtitle: '${summary?.completedCount ?? 0}',
                        onTap: onTapCompleted,
                      ),
                      _StatCard(
                        icon: Icons.euro_rounded,
                        label: 'Omzet',
                        subtitle: summary != null
                            ? '€${(summary!.revenueCents / 100).toStringAsFixed(0)}'
                            : '€0',
                        onTap: onTapRevenue,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: GymiesColors.darkBlue.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: GymiesColors.primary, width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
          children: [
            Icon(icon, color: GymiesColors.primary, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.fjallaOne(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final date = booking.scheduledAt;
    final resolvedName = booking.clientName?.isNotEmpty == true
        ? booking.clientName!
        : booking.trainerName;
    final displayName = resolvedName.isNotEmpty ? resolvedName : 'Klant';
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: GymiesColors.darkBlue.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: GymiesColors.primary.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: GymiesColors.primary.withValues(alpha: 0.3),
          child: Text(
            displayName[0].toUpperCase(),
            style: const TextStyle(
              color: GymiesColors.darkBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} · ${booking.durationMinutes} min',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(booking.status).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _statusLabel(booking.status),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _statusColor(booking.status),
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return Colors.green.shade700;
      case 'pending':
        return Colors.orange.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return GymiesColors.darkBlue;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Bevestigd';
      case 'pending':
        return 'Te bevestigen';
      case 'cancelled':
        return 'Geannuleerd';
      default:
        return status;
    }
  }
}
