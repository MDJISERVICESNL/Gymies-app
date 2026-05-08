import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/booking.dart';
import '../../services/auth_service.dart';
import '../../services/calendar_service.dart';
import '../../services/gymies_api.dart';
import '../../services/notification_realtime_service.dart';
import '../../theme/gymies_theme.dart';
import '../../utils/app_lifecycle_manager.dart';
import '../../utils/haptics.dart';
import '../widgets/offline_banner.dart';
import '../trainer_more_screen.dart';
import '../trainer_clients_screen.dart';
import '../trainer_dashboard_screen.dart';
import '../trainer_inbox_screen.dart';
import '../trainer_profile_screen.dart';
import '../trainer_sessions_screen.dart';

/// Shell voor de trainer-rol: vijf tabs onderaan via Material 3 NavigationBar.
///
/// Tabs:
///   0 Home       – TrainerDashboardScreen
///   1 Sessies    – TrainerSessionsScreen (+ agenda-toggle in eigen AppBar)
///   2 Inbox      – TrainerInboxScreen (Gesprekken + Meldingen)
///   3 Klanten    – TrainerClientsScreen
///   4 Meer       – TrainerMoreScreen
///
/// Profiel + Uitloggen: avatar-knop in elke tab-AppBar opent TrainerProfileScreen.
class TrainerShell extends StatefulWidget {
  const TrainerShell({super.key});

  @override
  State<TrainerShell> createState() => TrainerShellState();
}

class TrainerShellState extends State<TrainerShell>
    with AppLifecycleManager<TrainerShell> {
  int _currentIndex = 0;
  int _unreadCount = 0;
  StreamSubscription? _realtimeSub;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );

  @override
  void initState() {
    super.initState();
    initLifecycle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final realtime = context.read<NotificationRealtimeService>();
        _unreadCount = realtime.unreadCount;
        _realtimeSub = realtime.events.listen((event) {
          if (mounted) setState(() => _unreadCount = realtime.unreadCount);
          // ── Auto kalender sync voor nieuwe boekingen ──
          _handleBookingAutoSync(event);
        });
        realtime.addListener(_onRealtimeChanged);
      } catch (e) {
        // Fail-open: Realtime init optional
        if (kDebugMode) debugPrint('[TrainerShell] Realtime init failed: $e');
      }
    });
  }

  void _onRealtimeChanged() {
    if (!mounted) return;
    try {
      final count = context.read<NotificationRealtimeService>().unreadCount;
      setState(() => _unreadCount = count);
    } catch (e) {
      // Fail-open: Unread count update optional
      if (kDebugMode) debugPrint('[TrainerShell] Update unread count failed: $e');
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    try {
      context
          .read<NotificationRealtimeService>()
          .removeListener(_onRealtimeChanged);
    } catch (e) {
      // Fail-open: Listener removal can fail if service unavailable
      if (kDebugMode) debugPrint('[TrainerShell] Remove listener failed: $e');
    }
    disposeLifecycle();
    super.dispose();
  }

  @override
  void onDataRefreshNeeded() {
    // Called when app returns from background after >5min
    // Refresh bookings, clients, and session data
    if (kDebugMode) {
      debugPrint('[TrainerShell] Refreshing data after long background period');
    }
    try {
      final api = context.read<GymiesApi>();
      // Trigger refresh of bookings list (non-blocking)
      api.getBookings().catchError((_) {
        if (kDebugMode) debugPrint('[TrainerShell] Booking refresh failed');
      });
    } catch (_) {
      // Fail-open: refresh is optional
    }
  }

  /// Auto-sync: als een nieuwe boeking binnenkomt via realtime en de trainer
  /// heeft auto-sync ingeschakeld, voeg het event toe aan de device-kalender.
  Future<void> _handleBookingAutoSync(Map<String, dynamic> event) async {
    try {
      // Controleer of het een booking-gerelateerd event is
      final type = (event['type'] ?? event['notification_type'] ?? event['event'] ?? '')
          .toString()
          .toLowerCase();
      if (!type.contains('booking') && !type.contains(S.of(context).boeking) && !type.contains('session')) {
        return;
      }

      // Controleer of auto-sync is ingeschakeld
      final enabled = await CalendarService.instance.isTrainerAutoSyncEnabled();
      if (!enabled) return;

      // Probeer booking data te extraheren uit het event
      final bookingData = event['booking'] ?? event['booking_data'] ?? event['data'];
      if (bookingData is! Map<String, dynamic>) return;

      // Parse naar Booking model en voeg toe aan kalender
      final booking = Booking.fromJson(bookingData);
      if (booking.id.isEmpty || !booking.isUpcoming) return;

      await CalendarService.instance.addBookingToTrainerCalendar(booking);
      if (kDebugMode) debugPrint('[TrainerAutoSync] Boeking ${booking.id} toegevoegd aan kalender');
    } catch (e) {
      // Auto-sync mag nooit de app-flow verstoren
      if (kDebugMode) debugPrint('[TrainerAutoSync] Fout: $e');
    }
  }

  /// Public: navigeer naar een specifieke tab vanuit child widgets.
  void jumpToTab(int index) {
    if (index >= 0 && index < 5 && index != _currentIndex) {
      Haptics.selection();
      setState(() => _currentIndex = index);
    }
  }

  void _onTabTapped(int index) {
    Haptics.selection(); // Subtiele tik bij tab-wissel
    if (index == _currentIndex) {
      // Dubbele tik → pop naar root van de huidige tab
      _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _currentIndex = index);
    }
  }

  bool _handleBack() {
    final canPop =
        _navigatorKeys[_currentIndex].currentState?.canPop() ?? false;
    if (canPop) {
      _navigatorKeys[_currentIndex].currentState?.pop();
      return false;
    }
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false;
    }
    return true; // sluit app
  }

  String _avatarLabel() {
    try {
      final user = context.read<AuthService>().user;
      final name = user?['display_name']?.toString() ??
          user?['name']?.toString() ??
          '';
      return name.isNotEmpty ? name : '?';
    } catch (_) {
      return '?';
    }
  }

  void _openProfile() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const TrainerProfileScreen()),
    );
  }

  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return TrainerDashboardScreen(
          onAvatarTap: _openProfile,
          avatarLabel: _avatarLabel(),
        );
      case 1:
        return const TrainerSessionsScreen();
      case 2:
        return const TrainerInboxScreen();
      case 3:
        return const TrainerClientsScreen();
      case 4:
        return const TrainerMoreScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: Column(
          children: [
            // Offline banner: schuift in wanneer er geen internet is
            const OfflineBanner(),
            Expanded(
              child: Stack(
                children: [
                  for (int i = 0; i < 5; i++)
                    Offstage(
                      offstage: i != _currentIndex,
                      child: Navigator(
                        key: _navigatorKeys[i],
                        initialRoute: '/',
                        onGenerateRoute: (settings) {
                          return MaterialPageRoute(
                            settings: settings,
                            builder: (_) => _buildTab(i),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabTapped,
          backgroundColor: Colors.white,
          indicatorColor: GymiesColors.darkBlue.withOpacity(0.12),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: S.of(context).navHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.calendar_today_outlined),
              selectedIcon: const Icon(Icons.calendar_today_rounded),
              label: S.of(context).navSessions,
            ),
            NavigationDestination(
              icon: _unreadCount > 0
                  ? Badge.count(
                      count: _unreadCount,
                      child: const Icon(Icons.chat_bubble_outline_rounded),
                    )
                  : const Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: _unreadCount > 0
                  ? Badge.count(
                      count: _unreadCount,
                      child: const Icon(Icons.chat_bubble_rounded),
                    )
                  : const Icon(Icons.chat_bubble_rounded),
              label: S.of(context).navInbox,
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_alt_outlined),
              selectedIcon: const Icon(Icons.people_alt_rounded),
              label: S.of(context).navClients,
            ),
            NavigationDestination(
              icon: const Icon(Icons.menu_rounded),
              selectedIcon: const Icon(Icons.menu_open_rounded),
              label: S.of(context).navMore,
            ),
          ],
        ),
      ),
    );
  }
}

/// Navigeer naar een specifieke tab vanuit buiten de shell.
/// Gebruik: TrainerShell.of(context)?.jumpToTab(2);
extension TrainerShellExtension on BuildContext {
  TrainerShellState? get trainerShell =>
      findAncestorStateOfType<TrainerShellState>();
}
