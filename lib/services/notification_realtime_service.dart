import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import '../config/timing_constants.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'gymies_api.dart';
import 'local_push_service.dart';
import '../utils/notification_display_helper.dart';

class NotificationRealtimeService extends ChangeNotifier {
  NotificationRealtimeService({
    required AuthService auth,
    required LocalPushService push,
    GymiesApi? api,
  }) : _auth = auth,
       _push = push,
       _api = api {
    _auth.addListener(_handleAuthChanged);
  }

  final AuthService _auth;
  final LocalPushService _push;
  final GymiesApi? _api;

  final StreamController<Map<String, dynamic>> _eventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _connecting = false;
  bool _connected = false;
  int _unreadCount = 0;

  int get unreadCount => _unreadCount;
  bool get isConnected => _connected;
  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  Future<void> start() async {
    await _push.init();
    if (gymiesWsEnabled) await _connectIfPossible();
  }

  void markOneRead() {
    if (_unreadCount == 0) return;
    _unreadCount -= 1;
    notifyListeners();
  }

  void markAllRead() {
    if (_unreadCount == 0) return;
    _unreadCount = 0;
    notifyListeners();
  }

  void setUnreadCount(int count) {
    _unreadCount = count < 0 ? 0 : count;
    notifyListeners();
  }

  void _handleAuthChanged() {
    if (!_auth.isLoggedIn) {
      _disconnect();
      _unreadCount = 0;
      notifyListeners();
      return;
    }
    if (gymiesWsEnabled) _connectIfPossible(); // fire-and-forget
  }

  /// WebSocket host – per deploy docs (nginx /ws proxy). Geen :0.
  static const String _wsHost = AppConfig.wsHost;

  /// Bouwt WebSocket URI's met het meegegeven auth token (ticket of access_token).
  List<Uri> _candidates(String authToken) {
    if (!_auth.isLoggedIn) return const [];
    final role = (_auth.isTrainer ? 'trainer' : 'client').replaceAll('#', '').trim();
    final template = gymiesWsNotificationsUrlTemplate;
    if (template.isNotEmpty) {
      final s = template
          .replaceAll('{token}', Uri.encodeComponent(authToken))
          .replaceAll('{role}', role)
          .replaceAll('?token=', '?access_token=')
          .replaceAll('&token=', '&access_token=')
          .replaceAll(':0/', '/')
          .replaceAll(RegExp(r':0(?=[?#/]|$)'), '');
      if (s.startsWith('wss://') || s.startsWith('ws://')) {
        final u = Uri.tryParse(s);
        if (u != null && u.host.isNotEmpty) {
          return [ensureWsPort(u).replace(fragment: '')];
        }
        return [Uri(scheme: 'wss', host: _wsHost, port: 443, path: '/ws/notifications', queryParameters: {'access_token': authToken, 'role': role})];
      }
    }
    // Backend verwacht access_token (zoals REST API). Expliciet port 443, geen fragment.
    return [
      Uri(scheme: 'wss', host: _wsHost, port: 443, path: '/ws/notifications', queryParameters: {'access_token': authToken, 'role': role}),
      Uri(scheme: 'wss', host: _wsHost, port: 443, path: '/notifications/ws', queryParameters: {'access_token': authToken, 'role': role}),
    ];
  }

  /// Verwijdert auth tokens uit een WebSocket URI voor gebruik in logs.
  static String _sanitizeWsUri(Uri uri) {
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('access_token')
      ..remove('token')
      ..remove('ticket');
    return uri.replace(queryParameters: params.isEmpty ? null : params).toString();
  }

  /// Verbindt met WebSocket. Probeert eerst een kortstondig ticket te gebruiken
  /// (via /api/gymies/ws-ticket) zodat het lange-termijn access token niet in
  /// de query string belandt. Fallback naar access_token als ticket niet beschikbaar.
  Future<void> _connectIfPossible() async {
    if (_connecting || _connected || !_auth.isLoggedIn) return;
    _connecting = true;

    // Probeer ticket-based auth (kortstondig, veiliger)
    String authToken = _auth.token ?? '';
    if (_api != null) {
      try {
        final ticket = await _api.getWsTicket();
        if (ticket != null && ticket.isNotEmpty) {
          authToken = ticket;
          if (kDebugMode) debugPrint('[WS] Ticket-based auth verkregen');
        }
      } catch (_) {
        // Fallback naar access_token
        if (kDebugMode) debugPrint('[WS] Ticket niet beschikbaar, fallback naar access_token');
      }
    }

    final candidates = _candidates(authToken);
    if (candidates.isEmpty) {
      _connecting = false;
      return;
    }

    for (final uri in candidates) {
      if (kDebugMode) debugPrint('[WS] Verbinden met ${_sanitizeWsUri(uri)}');
      try {
        // Cancel any existing subscription before creating a new one (BUG FIX: prevent memory leak)
        _subscription?.cancel();

        final channel = WebSocketChannel.connect(uri);
        final sub = channel.stream.listen(
          (event) => _onEvent(event),
          onError: (_) => _onDisconnected(),
          onDone: _onDisconnected,
          cancelOnError: false,
        );
        _channel = channel;
        _subscription = sub;
        _connected = true;
        _connecting = false;
        notifyListeners();
        return;
      } catch (_) {
        // probeer volgende kandidaat
      }
    }

    _connecting = false;
    _scheduleReconnect();
  }

  void _onDisconnected() {
    _connected = false;
    _connecting = false;
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (!_auth.isLoggedIn) return;
    _reconnectTimer = Timer(TimingConstants.wsReconnectDelay, () => _connectIfPossible()); // fire-and-forget
  }

  Map<String, dynamic>? _parse(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return {'title': 'Melding', 'body': raw.toString()};
      }
    }
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      final notification = decoded['notification'];
      if (notification is Map<String, dynamic>) return notification;
      final message = decoded['message'];
      if (message is Map<String, dynamic>) return message;
      return decoded;
    }
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<void> _onEvent(dynamic raw) async {
    final map = _parse(raw);
    if (map == null) return;
    final isRead =
        map['read_at'] != null ||
        map['readAt'] != null ||
        map['unread'] == false ||
        map['is_unread'] == false;
    if (!isRead) {
      _unreadCount += 1;
      notifyListeners();
    }
    _eventsController.add(map);
    final title = NotificationDisplayHelper.displayTitle(map);
    final body = NotificationDisplayHelper.displayBody(map);
    await _push.show(title: title, body: body);
  }

  void _disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _connected = false;
    _connecting = false;
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChanged);
    _disconnect();
    _eventsController.close();
    super.dispose();
  }
}
