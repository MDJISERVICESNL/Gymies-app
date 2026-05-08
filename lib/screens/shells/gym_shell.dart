import 'package:flutter/material.dart';

import '../../theme/gymies_theme.dart';
import '../../utils/haptics.dart';
import '../widgets/offline_banner.dart';
import '../gym_bookings_screen.dart';
import '../gym_clients_screen.dart';
import '../gym_dashboard_screen.dart';
import '../gym_settings_screen.dart';
import '../gym_trainers_screen.dart';
import '../../l10n/generated/app_localizations.dart';

/// Shell voor de gym-rol: vijf tabs onderaan via Material 3 NavigationBar.
///
/// Tabs:
///   0 Dashboard  – GymDashboardScreen
///   1 Trainers   – GymTrainersScreen
///   2 Boekingen  – GymBookingsScreen
///   3 Klanten    – GymClientsScreen
///   4 Instellingen – GymSettingsScreen
class GymShell extends StatefulWidget {
  const GymShell({super.key});

  @override
  State<GymShell> createState() => _GymShellState();
}

class _GymShellState extends State<GymShell> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );

  @override
  void initState() {
    super.initState();
    _screens = [
      GymDashboardScreen(
        onTrainersTap: () => jumpToTab(1),
        onBookingsTap: () => jumpToTab(2),
        onClientsTap: () => jumpToTab(3),
      ),
      const GymTrainersScreen(),
      const GymBookingsScreen(),
      const GymClientsScreen(),
      const GymSettingsScreen(),
    ];
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: Column(
          children: [
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
                            builder: (_) => _screens[i],
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
          indicatorColor: GymiesColors.primary.withOpacity(0.2),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard_rounded),
              label: S.of(context).dashboard,
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_outline_rounded),
              selectedIcon: const Icon(Icons.people_rounded),
              label: S.of(context).trainers,
            ),
            NavigationDestination(
              icon: const Icon(Icons.event_available_outlined),
              selectedIcon: const Icon(Icons.event_available_rounded),
              label: S.of(context).bookings,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: S.of(context).klanten,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: S.of(context).instellingen,
            ),
          ],
        ),
      ),
    );
  }
}

/// Navigeer naar een specifieke tab vanuit buiten de shell.
/// Gebruik: GymShell.of(context)?.jumpToTab(1);
extension GymShellExtension on BuildContext {
  _GymShellState? get gymShell =>
      findAncestorStateOfType<_GymShellState>();
}
