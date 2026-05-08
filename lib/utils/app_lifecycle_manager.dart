import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_realtime_service.dart';

/// Mixin voor Shell-schermen (trainer_shell, client_shell, gym_shell).
/// Handelt app lifecycle events centraal af:
///
/// - **resumed**: refresh auth, reconnect WebSocket, check connectivity
/// - **paused**: cleanup timers, disconnect WebSocket gracefully
/// - **inactive**: (iOS) blur gevoelige data
///
/// Gebruik:
/// ```dart
/// class _TrainerShellState extends State<TrainerShell>
///     with AppLifecycleManager {
///   @override
///   void initState() {
///     super.initState();
///     initLifecycle();
///   }
///
///   @override
///   void dispose() {
///     disposeLifecycle();
///     super.dispose();
///   }
/// }
/// ```
mixin AppLifecycleManager<T extends StatefulWidget> on State<T>
    implements WidgetsBindingObserver {

  DateTime? _pausedAt;

  /// Tijd waarna we data refreshen bij resume (5 minuten).
  static const _refreshThreshold = Duration(minutes: 5);

  void initLifecycle() {
    WidgetsBinding.instance.addObserver(this);
  }

  void disposeLifecycle() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onResumed();
        break;
      case AppLifecycleState.paused:
        _pausedAt = DateTime.now();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _onResumed() async {
    if (!mounted) return;

    // Check connectivity
    try {
      final connectivity = context.read<ConnectivityService>();
      await connectivity.checkNow();
    } catch (e) {
      // Fail-open: Connectivity check optional, continue anyway
      if (kDebugMode) debugPrint('[Lifecycle] Connectivity check failed: $e');
    }

    // Reconnect WebSocket als nodig
    try {
      // ignore: use_build_context_synchronously
      final realtime = context.read<NotificationRealtimeService>();
      if (!realtime.isConnected) {
        if (kDebugMode) debugPrint('[Lifecycle] WebSocket reconnect na resume');
        await realtime.start();
      }
    } catch (e) {
      // Fail-open: WebSocket reconnect optional
      if (kDebugMode) debugPrint('[Lifecycle] WebSocket reconnect failed: $e');
    }

    // Als app langer dan 5 min in background was: refresh auth data
    if (_pausedAt != null &&
        DateTime.now().difference(_pausedAt!) > _refreshThreshold) {
      if (kDebugMode) debugPrint('[Lifecycle] App was >5min in background — refresh data');
      try {
        // ignore: use_build_context_synchronously
        final auth = context.read<AuthService>();
        if (auth.isLoggedIn) {
          onDataRefreshNeeded();
        }
      } catch (e) {
        // Fail-open: Background refresh optional
        if (kDebugMode) debugPrint('[Lifecycle] Background refresh failed: $e');
      }
    }

    _pausedAt = null;
  }

  /// Override dit in je Shell om specifieke data te refreshen na lang in background.
  /// Wordt alleen aangeroepen als app >5min in background was en user is ingelogd.
  void onDataRefreshNeeded() {
    // Default: niets. Override in subclass.
    if (kDebugMode) debugPrint('[Lifecycle] onDataRefreshNeeded (override in shell)');
  }

  // ── WidgetsBindingObserver stubs ────────────────────────────────
  @override
  void didChangeMetrics() {}
  @override
  void didChangeTextScaleFactor() {}
  @override
  void didChangePlatformBrightness() {}
  @override
  void didChangeLocales(List<Locale>? locales) {}
  @override
  void didHaveMemoryPressure() {
    if (kDebugMode) debugPrint('[Lifecycle] Memory pressure — clear image cache');
    PaintingBinding.instance.imageCache.clear();
  }
  @override
  void didChangeAccessibilityFeatures() {}
  @override
  Future<bool> didPopRoute() async => false;
  @override
  Future<bool> didPushRoute(String route) async => false;
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async => false;
  // didRequestAppExit wordt niet geoverride — standaard Flutter gedrag.
}
