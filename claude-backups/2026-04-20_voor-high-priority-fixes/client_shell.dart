import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/notification_realtime_service.dart';
import '../../theme/gymies_theme.dart';
import '../../utils/haptics.dart';
import '../widgets/offline_banner.dart';
import '../client_home_screen.dart';
import '../client_messages_screen.dart';
import '../client_profile_hub_screen.dart';
import '../client_sessions_screen.dart';
import '../dashboard_screen.dart';

/// Shell voor de client-rol: vijf tabs onderaan via Material 3 NavigationBar.
///
/// Tabs:
///   0 Home        – ClientHomeScreen (welkom-dashboard)
///   1 Ontdekken   – DashboardScreen (trainer-discovery)
///   2 Training    – ClientSessionsScreen (sessie-overzicht)
///   3 Inbox       – ClientMessagesScreen (berichten + meldingen)
///   4 Me          – ClientProfileHubScreen (profiel & instellingen)
class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => ClientShellState();
}

class ClientShellState extends State<ClientShell> {
  int _currentIndex = 0;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const List<Widget> _screens = [
    ClientHomeScreen(),
    DashboardScreen(),
    ClientSessionsScreen(),
    ClientMessagesScreen(),
    ClientProfileHubScreen(),
  ];

  /// Navigeer naar een specifieke tab vanuit andere schermen.
  void jumpToTab(int index) {
    if (index >= 0 && index < 5) {
      setState(() => _currentIndex = index);
    }
  }

  void _onTabTapped(int index) {
    Haptics.selection(); // Subtiele tik bij tab-wissel
    if (index == _currentIndex) {
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
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Lees unread count vanuit user data of realtime service
    final user = context.watch<AuthService>().user;
    int unread = (user?['unread_messages_count'] as int?) ?? 0;
    try {
      final realtime =
          Provider.of<NotificationRealtimeService>(context, listen: true);
      unread = realtime.unreadCount > 0 ? realtime.unreadCount : unread;
    } catch (_) {}

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
                        onGenerateRoute: (_) => MaterialPageRoute(
                          builder: (_) => _screens[i],
                        ),
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
          indicatorColor: GymiesColors.primary.withValues(alpha: 0.2),
          animationDuration: const Duration(milliseconds: 400),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Ontdekken',
            ),
            const NavigationDestination(
              icon: Icon(Icons.fitness_center),
              selectedIcon: Icon(Icons.fitness_center_rounded),
              label: 'Training',
            ),
            NavigationDestination(
              icon: unread > 0
                  ? Badge.count(
                      count: unread,
                      child: const Icon(Icons.inbox_outlined),
                    )
                  : const Icon(Icons.inbox_outlined),
              selectedIcon: unread > 0
                  ? Badge.count(
                      count: unread,
                      child: const Icon(Icons.inbox_rounded),
                    )
                  : const Icon(Icons.inbox_rounded),
              label: 'Inbox',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Me',
            ),
          ],
        ),
      ),
    );
  }
}

/// Navigeer naar een specifieke tab vanuit buiten de shell.
/// Gebruik: ClientShell.of(context)?.jumpToTab(1);
extension ClientShellExtension on BuildContext {
  ClientShellState? get clientShell =>
      findAncestorStateOfType<ClientShellState>();
}
