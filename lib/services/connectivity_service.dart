import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Realtime netwerk connectiviteit monitoring.
/// Geeft instant feedback wanneer de gebruiker offline/online gaat.
///
/// Gebruik:
/// ```dart
/// final connectivity = context.watch<ConnectivityService>();
/// if (!connectivity.isOnline) showOfflineBanner();
/// ```
class ConnectivityService extends ChangeNotifier {
  ConnectivityService() {
    _init();
  }

  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _subscription;
  bool _isOnline = true;
  List<ConnectivityResult> _currentResults = [];

  bool get isOnline => _isOnline;
  bool get isWifi => _currentResults.contains(ConnectivityResult.wifi);
  bool get isMobile => _currentResults.contains(ConnectivityResult.mobile);
  List<ConnectivityResult> get currentResults => _currentResults;

  Future<void> _init() async {
    try {
      _currentResults = await _connectivity.checkConnectivity();
      _isOnline = _hasConnection(_currentResults);
    } catch (_) {
      _isOnline = true; // Assume online bij fout
    }

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _currentResults = results;
      _isOnline = _hasConnection(results);

      if (wasOnline != _isOnline) {
        if (kDebugMode) {
          debugPrint('[Connectivity] ${_isOnline ? "ONLINE" : "OFFLINE"} — $results');
        }
        notifyListeners();
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
  }

  /// Check of we nu online zijn (one-shot, handig voor retry logic).
  Future<bool> checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _currentResults = results;
      _isOnline = _hasConnection(results);
      notifyListeners();
      return _isOnline;
    } catch (_) {
      return _isOnline;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
