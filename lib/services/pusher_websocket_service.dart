import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/timing_constants.dart';

/// Connection states voor de Pusher-protocol WebSocket (gebruikt door Laravel Reverb).
enum PusherConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Event dat binnenkomt via een Pusher channel.
class PusherEvent {
  const PusherEvent({
    required this.event,
    required this.channel,
    required this.data,
  });

  final String event;
  final String channel;
  final Map<String, dynamic> data;

  @override
  String toString() => 'PusherEvent($event on $channel)';
}

/// Callback types
typedef PusherAuthCallback = Future<String?> Function(
  String socketId,
  String channelName,
);

/// WebSocket service — gebruikt het Pusher protocol (v7) met Laravel Reverb.
///
/// Reverb is de enige WebSocket provider (gratis, self-hosted).
/// Naam "Pusher" in de klasse verwijst naar het protocol, niet de dienst.
///
/// Flow:
/// 1. Connect naar wss://gymies.nl/app/{key}?protocol=7
/// 2. Ontvang `pusher:connection_established` met socket_id
/// 3. Subscribe op private channels via auth callback
/// 4. Ontvang events op gesubscribede channels
/// 5. Ping/pong keepalive
/// 6. Auto-reconnect met exponential backoff
class PusherWebSocketService extends ChangeNotifier {
  PusherWebSocketService({
    required PusherAuthCallback authCallback,
  }) : _authCallback = authCallback;

  final PusherAuthCallback _authCallback;

  // ── Connection state ──────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _pongTimer;
  Timer? _reconnectTimer;

  PusherConnectionState _state = PusherConnectionState.disconnected;
  PusherConnectionState get state => _state;
  bool get isConnected => _state == PusherConnectionState.connected;

  String? _socketId;
  String? get socketId => _socketId;

  // ── Config (gezet door connect()) ─────────────────────────────
  String _appKey = '';
  String _host = '';
  int _port = 443;
  String _scheme = 'wss';

  // ── Channels ──────────────────────────────────────────────────
  final Set<String> _subscribedChannels = {};
  final Set<String> _pendingChannels = {};

  // ── Event stream ──────────────────────────────────────────────
  final StreamController<PusherEvent> _eventController =
      StreamController<PusherEvent>.broadcast();
  Stream<PusherEvent> get events => _eventController.stream;

  // ── Reconnect backoff ─────────────────────────────────────────
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 15;

  // ── Activity timeout (van server) ─────────────────────────────
  int _activityTimeoutSec = 120; // default, server kan overriden

  // ══════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════

  /// Verbind met de Pusher-compatible WebSocket server.
  ///
  /// [appKey] - de Reverb/Pusher app key (niet geheim)
  /// [host] - hostname, bijv. "www.gymies.nl"
  /// [port] - poort, bijv. 443
  /// [scheme] - "wss" of "ws"
  Future<void> connect({
    required String appKey,
    required String host,
    int port = 443,
    String scheme = 'wss',
  }) async {
    if (_state == PusherConnectionState.connecting) return;

    _appKey = appKey;
    _host = host;
    _port = port;
    _scheme = scheme;

    await _doConnect();
  }

  /// Subscribe op een private channel.
  /// Auth wordt automatisch afgehandeld via de authCallback.
  Future<void> subscribe(String channelName) async {
    if (_subscribedChannels.contains(channelName)) return;
    _pendingChannels.add(channelName);

    if (_state == PusherConnectionState.connected && _socketId != null) {
      await _authenticateAndSubscribe(channelName);
    }
    // Anders wordt het gesubscribed zodra de verbinding staat
  }

  /// Unsubscribe van een channel.
  void unsubscribe(String channelName) {
    _subscribedChannels.remove(channelName);
    _pendingChannels.remove(channelName);

    if (_state == PusherConnectionState.connected) {
      _sendJson({
        'event': 'pusher:unsubscribe',
        'data': {'channel': channelName},
      });
    }
  }

  /// Stuur een client event op een channel (bijv. typing indicator).
  /// Let op: client events beginnen altijd met "client-".
  void triggerClientEvent(String channelName, String eventName, Map<String, dynamic> data) {
    if (!_subscribedChannels.contains(channelName)) return;
    if (!eventName.startsWith('client-')) {
      eventName = 'client-$eventName';
    }
    _sendJson({
      'event': eventName,
      'channel': channelName,
      'data': data,
    });
  }

  /// Verbreek de verbinding.
  void disconnect() {
    _state = PusherConnectionState.disconnected;
    _cleanup();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    // BUG FIX: Ensure event controller is properly closed
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // CONNECTION LOGIC
  // ══════════════════════════════════════════════════════════════

  Future<void> _doConnect() async {
    _cleanup();

    final wasReconnecting = _state == PusherConnectionState.reconnecting;
    _state = wasReconnecting
        ? PusherConnectionState.reconnecting
        : PusherConnectionState.connecting;
    notifyListeners();

    // Bouw Pusher protocol URL: /app/{key}?protocol=7
    // Standaard Reverb poort is 443 achter nginx, of 8080 direct
    final portSuffix = (_scheme == 'wss' && _port == 443) ||
            (_scheme == 'ws' && _port == 80)
        ? ''
        : ':$_port';
    final url = '$_scheme://$_host$portSuffix/app/$_appKey?protocol=7';

    if (kDebugMode) debugPrint('[Pusher] Verbinden met $url');

    try {
      final uri = Uri.parse(url);
      // BUG FIX: Cancel old subscription before creating new one to prevent memory leak
      _subscription?.cancel();

      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Pusher] Connect fout: $e');
      _scheduleReconnect();
    }
  }

  // ══════════════════════════════════════════════════════════════
  // MESSAGE HANDLING (Pusher protocol)
  // ══════════════════════════════════════════════════════════════

  void _onMessage(dynamic raw) {
    Map<String, dynamic> frame;
    try {
      frame = raw is String ? jsonDecode(raw) as Map<String, dynamic> : raw as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) debugPrint('[Pusher] JSON parse fout: $e');
      return;
    }

    final event = (frame['event'] ?? '').toString();
    final channel = (frame['channel'] ?? '').toString();

    // Parse data — kan string (JSON) of al een map zijn
    Map<String, dynamic> data = {};
    final rawData = frame['data'];
    if (rawData is String) {
      try {
        final parsed = jsonDecode(rawData);
        if (parsed is Map<String, dynamic>) data = parsed;
      } catch (_) {
        data = {'raw': rawData};
      }
    } else if (rawData is Map<String, dynamic>) {
      data = rawData;
    }

    switch (event) {
      case 'pusher:connection_established':
        _handleConnectionEstablished(data);
        break;

      case 'pusher:ping':
        _sendJson({'event': 'pusher:pong', 'data': {}});
        _resetActivityTimer();
        break;

      case 'pusher:pong':
        _resetActivityTimer();
        break;

      case 'pusher:error':
        _handlePusherError(data);
        break;

      case 'pusher_internal:subscription_succeeded':
        if (kDebugMode) debugPrint('[Pusher] Subscribed op $channel');
        _pendingChannels.remove(channel);
        _subscribedChannels.add(channel);
        break;

      default:
        // App event — doorsturen naar listeners
        if (event.isNotEmpty && !event.startsWith('pusher:')) {
          _eventController.add(PusherEvent(
            event: event,
            channel: channel,
            data: data,
          ));
        }
        _resetActivityTimer();
        break;
    }
  }

  void _handleConnectionEstablished(Map<String, dynamic> data) {
    _socketId = data['socket_id']?.toString();
    _reconnectAttempts = 0;

    // Server kan een activity_timeout meegeven
    final timeout = data['activity_timeout'];
    if (timeout is num && timeout > 0) {
      _activityTimeoutSec = timeout.toInt();
    }

    if (kDebugMode) debugPrint('[Pusher] Verbonden! socket_id=$_socketId, timeout=${_activityTimeoutSec}s');

    _state = PusherConnectionState.connected;
    notifyListeners();

    // Start ping/pong keepalive
    _startPingTimer();

    // Subscribe alle pending channels
    _subscribePendingChannels();
  }

  void _handlePusherError(Map<String, dynamic> data) {
    final code = data['code'];
    final message = data['message'] ?? 'Unknown error';
    if (kDebugMode) debugPrint('[Pusher] Server error: code=$code message=$message');

    // Code 4000-4099: connectie moet niet opnieuw geprobeerd worden
    if (code is int && code >= 4000 && code < 4100) {
      if (kDebugMode) debugPrint('[Pusher] Fatal error, geen reconnect');
      _state = PusherConnectionState.disconnected;
      notifyListeners();
      return;
    }

    // Andere errors: probeer opnieuw
    _scheduleReconnect();
  }

  // ══════════════════════════════════════════════════════════════
  // CHANNEL AUTH & SUBSCRIBE
  // ══════════════════════════════════════════════════════════════

  Future<void> _subscribePendingChannels() async {
    final channels = List<String>.from(_pendingChannels);
    for (final ch in channels) {
      await _authenticateAndSubscribe(ch);
    }
  }

  Future<void> _authenticateAndSubscribe(String channelName) async {
    if (_socketId == null) return;

    // Public channels hoeven geen auth
    if (!channelName.startsWith('private-') &&
        !channelName.startsWith('presence-')) {
      _sendJson({
        'event': 'pusher:subscribe',
        'data': {'channel': channelName},
      });
      return;
    }

    // Private/presence channel: auth via backend
    try {
      final auth = await _authCallback(_socketId!, channelName);
      if (auth == null || auth.isEmpty) {
        if (kDebugMode) debugPrint('[Pusher] Auth gefaald voor $channelName');
        return;
      }

      _sendJson({
        'event': 'pusher:subscribe',
        'data': {
          'channel': channelName,
          'auth': auth,
        },
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Pusher] Auth error voor $channelName: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PING / PONG KEEPALIVE
  // ══════════════════════════════════════════════════════════════

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pongTimer?.cancel();

    // Stuur een ping na activity_timeout - 10 seconden
    final pingInterval = Duration(
      seconds: (_activityTimeoutSec > 20) ? _activityTimeoutSec - 10 : _activityTimeoutSec,
    );

    _pingTimer = Timer.periodic(pingInterval, (_) {
      if (_state != PusherConnectionState.connected) return;

      _sendJson({'event': 'pusher:ping', 'data': {}});

      // Wacht max 10 seconden op pong
      _pongTimer?.cancel();
      _pongTimer = Timer(const Duration(seconds: 10), () {
        if (kDebugMode) debugPrint('[Pusher] Pong timeout — reconnecting');
        _scheduleReconnect();
      });
    });
  }

  void _resetActivityTimer() {
    // Bij elke activiteit: reset de pong timer (server is alive)
    _pongTimer?.cancel();
  }

  // ══════════════════════════════════════════════════════════════
  // RECONNECT
  // ══════════════════════════════════════════════════════════════

  void _onError(dynamic error) {
    if (kDebugMode) debugPrint('[Pusher] WebSocket error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    if (kDebugMode) debugPrint('[Pusher] WebSocket verbinding gesloten');
    if (_state != PusherConnectionState.disconnected) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_state == PusherConnectionState.disconnected) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) debugPrint('[Pusher] Max reconnect pogingen bereikt ($_maxReconnectAttempts)');
      _state = PusherConnectionState.disconnected;
      notifyListeners();
      return;
    }

    _cleanup(keepPending: true);
    _state = PusherConnectionState.reconnecting;
    notifyListeners();

    _reconnectAttempts++;
    final baseMs = TimingConstants.wsReconnectDelay.inMilliseconds;
    final maxMs = TimingConstants.wsReconnectDelayMax.inMilliseconds;
    final multiplier = TimingConstants.wsReconnectBackoffMultiplier;
    var delayMs = baseMs;
    for (int i = 1; i < _reconnectAttempts; i++) {
      delayMs = (delayMs * multiplier).toInt();
    }
    if (delayMs > maxMs) delayMs = maxMs;

    if (kDebugMode) debugPrint('[Pusher] Reconnect poging $_reconnectAttempts over ${delayMs}ms');
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_state == PusherConnectionState.disconnected) return;
      _doConnect();
    });
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════

  void _sendJson(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) debugPrint('[Pusher] Send fout: $e');
    }
  }

  void _cleanup({bool keepPending = false}) {
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    try {
      _channel?.sink.close();
    } catch (e) {
      // Fail-open: WebSocket close can fail if already closed
      if (kDebugMode) debugPrint('[PusherWebSocketService] Cleanup error: $e');
    }
    _channel = null;
    _subscription = null;
    _socketId = null;

    if (!keepPending) {
      // Bewaar channels voor re-subscribe bij reconnect
      _pendingChannels.addAll(_subscribedChannels);
    }
    _subscribedChannels.clear();
  }
}
