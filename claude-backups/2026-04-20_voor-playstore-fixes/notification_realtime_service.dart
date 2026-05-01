import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';
import 'auth_service.dart';
import 'local_push_service.dart';
import '../utils/notification_display_helper.dart';

class NotificationRealtimeService extends ChangeNotifier {
  NotificationRealtimeService({
    required AuthService auth,
    required LocalPushService push,
  }) : _auth = auth,
       _push = push {
    _auth.addListener(_handleAuthChanged);
  }

  final AuthService _auth;
  final LocalPushService _push;

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
    if (gymiesWsEnabled) _connectIfPossible();
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
    if (gymiesWsEnabled) _connectIfPossible();
  }

  /// WebSocket host – www.gymies.nl per deploy docs (nginx /ws proxy). Geen :0.
  static const String _wsHost = 'www.gymies.nl';

  List<Uri> _candidates() {
    if (!_auth.isLoggedIn) return const [];
    final token = _auth.token ?? '';
    final role = (_auth.isTrainer ? 'trainer' : 'client').replaceAll('#', '').trim();
    final template = gymiesWsNotificationsUrlTemplate;
    if (template.isNotEmpty) {
      final s = template
          .replaceAll('{token}', Uri.encodeComponent(token))
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
        return [Uri(scheme: 'wss', host: _wsHost, port: 443, path: '/ws/notifications', queryParameters: {'access_token': token, 'role': role})];
      }
    }
    // Backend verwacht access_token (zoals REST API). Expliciet port 443, geen fragment.
    return [
      Uri(scheme: 'wss', host: _wsHost, port: 443, path: '/ws/notifications', queryParameters: {'access_token': token, 'role': role}),
      Uri(scheme: 'wss', host: _wsHost, port: 443, path: '/notifications/ws', queryParameters: {'access_token': token, 'role': role}),
    ];
  }

  /// Verwijdert het access_token uit een WebSocket URI voor gebruik in logs.
  /// Het token blijft intact in de eigenlijke verbinding — alleen debug-output is gesanitized.
  /// TODO: Migreer naar ticket-based WS authenticatie (kortstondig token via /api/gymies/ws-ticket).
  static String _sanitizeWsUri(Uri uri) {
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('access_token')
      ..remove('token');
    return uri.replace(queryParameters: params.isEmpty ? null : params).toString();
  }

  void _connectIfPossible() {
    if (_connecting || _connected || !_auth.isLoggedIn) return;
    final candidates = _candidates();
    if (candidates.isEmpty) return;
    _connecting = true;

    for (final uri in candidates) {
      if (kDebugMode) debugPrint('[WS] Verbinden met ${_sanitizeWsUri(uri)}');
      try {
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
    _reconnectTimer = Timer(const Duration(seconds: 4), _connectIfPossible);
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
