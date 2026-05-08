import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/timing_constants.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/booking.dart';
import '../models/trainer_models.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/reschedule_card_widget.dart';
import 'widgets/trainer_state_views.dart';

class TrainerChatScreen extends StatefulWidget {
  const TrainerChatScreen({super.key, required this.conversation});

  final TrainerConversation conversation;

  @override
  State<TrainerChatScreen> createState() => _TrainerChatScreenState();
}

class _TrainerChatScreenState extends State<TrainerChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<TrainerMessage> _messages = [];

  // ── Reschedule ─────────────────────────────────────────────
  final Set<String> _rescheduleBusyIds = {};

  // ── WebSocket ──────────────────────────────────────────────
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _pollTimer;
  bool _wsConnected = false;
  bool _connectingWs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startPollingFallback();
      if (mounted) _refreshSilently();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _wsSubscription?.cancel();
    try {
      _wsChannel?.sink.close();
    } catch (e) {
      // WebSocket may already be closed
      if (kDebugMode) debugPrint('[TrainerChat] WebSocket close error: $e');
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Data laden ─────────────────────────────────────────────

  Future<void> _load({bool background = false}) async {
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (_error != null) {
      setState(() => _error = null);
    }
    try {
      final api = context.read<GymiesApi>();
      final messages = await api.getTrainerConversationMessages(
        widget.conversation.id,
      );
      await api.markTrainerConversationAsRead(widget.conversation.id);
      if (!mounted) return;
      final sorted = messages
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final previousLength = _messages.length;
      setState(() {
        _messages = sorted;
        _loading = false;
      });
      if (!background) {
        _startRealtime();
      }
      if (!background || sorted.length != previousLength) {
        _jumpToBottom();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'load'}));
      if (!mounted) return;
      setState(() {
        _error = S.of(context).konChatNietLaden;
        _loading = false;
      });
    }
  }

  // ── Deduplicatie & merge ───────────────────────────────────

  String _messageKey(TrainerMessage m) {
    if (m.id.isNotEmpty) return 'id:${m.id}';
    return 'fallback:${m.senderType}:${m.createdAt.toIso8601String()}:${m.body}';
  }

  void _mergeMessages(List<TrainerMessage> incoming) {
    final combined = [..._messages, ...incoming];
    final seen = <String>{};
    final unique = <TrainerMessage>[];
    for (final m in combined) {
      final key = _messageKey(m);
      if (seen.contains(key)) continue;
      seen.add(key);
      unique.add(m);
    }
    unique.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messages = unique;
  }

  // ── Realtime: WebSocket + polling fallback ─────────────────

  void _startRealtime() {
    _startPollingFallback();
    _connectWebSocket();
  }

  void _startPollingFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(TimingConstants.messagePollInterval, (_) {
      if (!mounted || _sending) return;
      _refreshSilently();
    });
  }

  Future<void> _refreshSilently() async {
    try {
      final api = context.read<GymiesApi>();
      final messages = await api.getTrainerConversationMessages(
        widget.conversation.id,
      );
      if (!mounted) return;
      final previousLength = _messages.length;
      setState(() {
        _mergeMessages(messages);
      });
      if (_messages.length != previousLength) {
        _jumpToBottom();
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[TrainerChat] Silent refresh fout: $e');
      Sentry.addBreadcrumb(Breadcrumb(message: 'TrainerChat silent refresh failed: $e', category: 'chat'));
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'refreshSilently'}));
    }
  }

  // ── WebSocket verbinding ───────────────────────────────────

  List<Uri> _wsCandidates() {
    final token = context.read<AuthService>().token ?? '';
    final conversationId = widget.conversation.id;
    final template = gymiesWsChatUrlTemplate;
    final urls = <String>[];
    if (template.isNotEmpty) {
      urls.add(
        template
            .replaceAll('{conversationId}', conversationId)
            .replaceAll('{token}', Uri.encodeComponent(token))
            .replaceAll('?token=', '?access_token=')
            .replaceAll('&token=', '&access_token='),
      );
    } else {
      final base = gymiesWsBaseUrl;
      urls.add(
        '$base/conversations/$conversationId/ws?access_token=${Uri.encodeComponent(token)}',
      );
      urls.add(
        '$base/ws/conversations/$conversationId?access_token=${Uri.encodeComponent(token)}',
      );
      urls.add(
        '$base/chat/$conversationId?access_token=${Uri.encodeComponent(token)}',
      );
    }
    return urls
        .map(Uri.tryParse)
        .whereType<Uri>()
        .where((u) => u.scheme == 'ws' || u.scheme == 'wss')
        .map(ensureWsPort)
        .toList();
  }

  int _wsReconnectAttempts = 0;

  void _connectWebSocket() {
    if (!gymiesWsEnabled || _connectingWs || _wsConnected) return;
    final candidates = _wsCandidates();
    if (candidates.isEmpty) return;
    _connectingWs = true;
    // Cache localization strings to avoid context issues in callbacks
    final wsConnectedMsg = '[TrainerChat] WebSocket connected';
    final wsClosedMsg = '[TrainerChat] WebSocket connection closed';
    for (final uri in candidates) {
      try {
        final channel = WebSocketChannel.connect(uri);
        final sub = channel.stream.listen(
          (event) {
            if (!mounted) return;
            if (!_wsConnected) {
              _wsConnected = true;
              _wsReconnectAttempts = 0;
              if (kDebugMode) debugPrint(wsConnectedMsg);
            }
            final parsed = _parseIncomingWsMessage(event);
            if (parsed == null) return;
            setState(() {
              _mergeMessages([parsed]);
            });
            _jumpToBottom();
          },
          onError: (error, [StackTrace? stackTrace]) {
            if (kDebugMode) debugPrint('[TrainerChat] WebSocket error: $error');
            Sentry.addBreadcrumb(Breadcrumb(message: 'TrainerChat WS error: $error', category: 'websocket', level: SentryLevel.warning));
            _wsConnected = false;
            _scheduleReconnect();
          },
          onDone: () {
            _wsConnected = false;
            if (kDebugMode) debugPrint(wsClosedMsg);
            _scheduleReconnect();
          },
          cancelOnError: false,
        );
        _wsChannel = channel;
        _wsSubscription = sub;
        _connectingWs = false;
        return;
      } catch (e, st) {
        if (kDebugMode) debugPrint('[TrainerChat] WebSocket verbinding poging fout: $e');
        Sentry.addBreadcrumb(Breadcrumb(message: 'TrainerChat WS connect attempt failed: $e', category: 'websocket'));
        Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'wsConnect', 'uri': uri.toString()}));
      }
    }
    _connectingWs = false;
    _scheduleReconnect();
  }

  /// Exponential backoff reconnect: 2s → 3s → 4.5s → ... max 30s
  void _scheduleReconnect() {
    if (!mounted) return;
    _wsReconnectAttempts++;
    final baseMs = TimingConstants.wsReconnectDelay.inMilliseconds;
    final maxMs = TimingConstants.wsReconnectDelayMax.inMilliseconds;
    final multiplier = TimingConstants.wsReconnectBackoffMultiplier;
    var delayMs = baseMs;
    for (int i = 1; i < _wsReconnectAttempts; i++) {
      delayMs = (delayMs * multiplier).toInt();
    }
    if (delayMs > maxMs) delayMs = maxMs;
    if (kDebugMode) debugPrint('[TrainerChat] Reconnect poging $_wsReconnectAttempts over ${delayMs}ms');
    Future<void>.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _connectWebSocket();
    });
  }

  TrainerMessage? _parseIncomingWsMessage(dynamic rawEvent) {
    dynamic decoded = rawEvent;
    if (rawEvent is String) {
      try {
        decoded = jsonDecode(rawEvent);
      } catch (e, st) {
        if (kDebugMode) debugPrint('[TrainerChat] JSON decode websocket fout: $e');
        Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'wsJsonDecode'}));
        // Platte tekst → behandel als berichtbody
        return TrainerMessage(
          id: '',
          conversationId: widget.conversation.id,
          senderType: 'client',
          body: rawEvent,
          createdAt: DateTime.now(),
        );
      }
    }
    Map<String, dynamic>? json;
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        json = data;
      } else {
        final message = decoded['message'];
        if (message is Map<String, dynamic>) {
          json = message;
        } else {
          json = decoded;
        }
      }
    } else if (decoded is Map) {
      json = Map<String, dynamic>.from(decoded);
    }
    if (json == null) return null;
    try {
      return TrainerMessage.fromJson(json);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[TrainerChat] WS message parse fout: $e');
      final jsonStr = json.toString(); Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'wsMessageParse', 'json': jsonStr.length > 200 ? jsonStr.substring(0, 200) : jsonStr}));
      return null;
    }
  }

  // ── Bericht sturen (optimistic UI) ──────────────────────────

  /// Lijst van pending/failed berichten die nog niet door de server bevestigd zijn.
  /// We houden deze apart bij zodat ze in de UI gemixed kunnen worden met TrainerMessage.
  final List<Map<String, dynamic>> _pendingMessages = [];

  Future<void> _send([String? quickReplyText]) async {
    final text = (quickReplyText ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;

    final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    _pendingMessages.add({
      'id': tempId,
      'body': text,
      'status': 'pending',
    });

    setState(() => _sending = true);
    if (quickReplyText == null) _controller.clear();
    _jumpToBottom();
    Haptics.light();

    try {
      final api = context.read<GymiesApi>();
      final created = await api.sendTrainerMessage(
        widget.conversation.id,
        text,
      );
      if (!mounted) return;
      // Verwijder pending, voeg server-bericht toe
      _pendingMessages.removeWhere((p) => p['id'] == tempId);
      if (created != null) {
        setState(() => _mergeMessages([created]));
      } else {
        await _load(background: true);
      }
      _jumpToBottom();
      Haptics.success();
    } on ApiException catch (e) {
      if (!mounted) return;
      final idx = _pendingMessages.indexWhere((p) => p['id'] == tempId);
      if (idx >= 0) {
        _pendingMessages[idx]['status'] = 'failed';
        _pendingMessages[idx]['error'] = e.message;
      }
      setState(() {});
      Haptics.error();
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'sendMessage'}));
      if (!mounted) return;
      final idx = _pendingMessages.indexWhere((p) => p['id'] == tempId);
      if (idx >= 0) {
        _pendingMessages[idx]['status'] = 'failed';
        _pendingMessages[idx]['error'] = S.of(context).errorSendFailed;
      }
      setState(() {});
      Haptics.error();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Retry een mislukt pending bericht
  Future<void> _retryPending(Map<String, dynamic> pending) async {
    final body = pending['body']?.toString() ?? '';
    final tempId = pending['id']?.toString() ?? '';
    if (body.isEmpty) return;

    // Reset naar pending
    final idx = _pendingMessages.indexWhere((p) => p['id'] == tempId);
    if (idx >= 0) {
      _pendingMessages[idx]['status'] = 'pending';
      _pendingMessages[idx].remove('error');
    }
    setState(() {});

    try {
      final created = await context.read<GymiesApi>().sendTrainerMessage(
        widget.conversation.id,
        body,
      );
      if (!mounted) return;
      _pendingMessages.removeWhere((p) => p['id'] == tempId);
      if (created != null) {
        setState(() => _mergeMessages([created]));
      } else {
        await _load(background: true);
      }
      Haptics.success();
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'retryPending'}));
      if (!mounted) return;
      final i = _pendingMessages.indexWhere((p) => p['id'] == tempId);
      if (i >= 0) {
        _pendingMessages[i]['status'] = 'failed';
        _pendingMessages[i]['error'] = S.of(context).errorSendFailed;
      }
      setState(() {});
    }
  }

  // ── Verplaats sessie flow ───────────────────────────────────

  /// Opent de "Verplaats sessie" bottom sheet:
  /// 1. Haal openstaande boekingen op voor deze klant
  /// 2. Toon lijst → kies boeking
  /// 3. Datum/tijd picker → bevestig
  /// 4. Stuur reschedule request via API
  /// 5. Toon kaart in chat
  Future<void> _openRescheduleFlow() async {
    Haptics.selection();
    final api = context.read<GymiesApi>();

    // ── 1. Laad boekingen ──
    List<Booking> bookings;
    try {
      final all = await api.getTrainerBookings();
      // Filter: upcoming, niet gecanceld/ingecheckt/afgerond, geen active safe session
      bookings = all.where((b) {
        final matchesClient = b.clientName?.toLowerCase() ==
            widget.conversation.clientName.toLowerCase();
        final isValid = b.isUpcoming &&
            b.status != 'cancelled' &&
            b.status != 'checked_in' &&
            b.status != 'completed' &&
            !b.safeSessionActive;
        return matchesClient && isValid;
      }).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'loadBookingsForReschedule'}));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(S.of(context).konBoekingenNietLaden),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    if (!mounted) return;

    if (bookings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).geenVerplaatsbareSessiesMet(widget.conversation.clientName)),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      return;
    }

    // ── 2. Selectie: 1 sessie → direct, 2+ → bottom sheet ──
    Booking selected;
    if (bookings.length == 1) {
      selected = bookings.first;
    } else {
      final picked = await showDialog<Booking>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: _RescheduleBookingPicker(
            bookings: bookings,
            clientName: widget.conversation.clientName,
          ),
        ),
      );
      if (picked == null || !mounted) return;
      selected = picked;
    }

    // ── 3. Edge case: sessie binnen 2 uur → waarschuwing ──
    final now = DateTime.now();
    final hoursUntil = selected.scheduledAt.difference(now).inHours;
    if (hoursUntil < 2 && selected.scheduledAt.isAfter(now)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.of(context).sessieBegintZo,
                  style: GoogleFonts.sora(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: Text(
            hoursUntil < 1
                ? S.of(context).dezeSessieBegintOverMinderDan
                : S.of(context).dezeSessieIsVandaagWeetJe,
            style: GoogleFonts.sora(fontSize: 14, color: Colors.grey.shade700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(S.of(context).annuleren),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text(S.of(context).tochVerplaatsen),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    // ── 4. Datum/tijd picker ──
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selected.scheduledAt.add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: S.of(context).kiesEenNieuweDatum,
      cancelText: S.of(context).annuleren,
      confirmText: 'Verder',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selected.scheduledAt),
      helpText: S.of(context).kiesEenNieuwTijdstip,
      cancelText: S.of(context).annuleren,
      confirmText: 'Verplaatsen',
    );
    if (pickedTime == null || !mounted) return;

    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    // ── 4. Verstuur reschedule via API ──
    Haptics.light();
    try {
      await api.rescheduleTrainerBooking(selected.id, newDateTime);
      if (!mounted) return;
      Haptics.success();

      // Voeg een reschedule-kaart bericht toe aan de chat
      final rescheduleMsg = TrainerMessage(
        id: 'reschedule_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: widget.conversation.id,
        senderType: 'trainer',
        body: jsonEncode({
          'type': 'reschedule_request',
          'booking_id': selected.id,
          'scheduled_at': selected.scheduledAt.toIso8601String(),
          'requested_at': newDateTime.toIso8601String(),
          S.of(context).trainername: selected.trainerName,
          'client_name': selected.clientName ?? widget.conversation.clientName,
          'session_type': selected.sessionType,
          'duration_minutes': selected.durationMinutes,
          'status': 'pending',
        }),
        createdAt: DateTime.now(),
      );
      setState(() {
        _mergeMessages([rescheduleMsg]);
      });
      _jumpToBottom();

      // Auto-sync: voeg de nieuwe datum alvast toe aan trainer-kalender
      try {
        final enabled = await CalendarService.instance.isTrainerAutoSyncEnabled();
        if (enabled) {
          final updatedBooking = Booking(
            id: selected.id,
            trainerName: selected.trainerName,
            clientName: selected.clientName,
            scheduledAt: newDateTime,
            durationMinutes: selected.durationMinutes,
            status: 'confirmed',
            sessionType: selected.sessionType,
            packageName: selected.packageName,
          );
          await CalendarService.instance.addBookingToTrainerCalendar(updatedBooking);
        }
      } catch (e) {
        // Kalender sync mag nooit de flow breken
        Sentry.addBreadcrumb(Breadcrumb(message: 'Calendar sync failed (non-blocking): $e', category: 'chat'));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(S.of(context).verplaatsingsverzoekVerstuurd),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': S.of(context).trainerchat, 'action': 'rescheduleFlow'}));
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(S.of(context).verplaatsenMisluktProbeerHetOpnieuw),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  // ── Reschedule card detectie voor TrainerMessage ───────────

  /// Probeert een reschedule-kaart te renderen voor een TrainerMessage.
  /// Retourneert null als het geen reschedule-bericht is.
  Widget? _buildRescheduleCard(TrainerMessage message) {
    // Probeer body als JSON te parsen
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(message.body);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // Geen JSON → geen kaart
    }
    if (json == null) return null;
    if (!RescheduleCardWidget.isRescheduleCard(json)) return null;

    final bookingId = RescheduleCardWidget.getBookingIdFromMessage(json);
    final isBusy = _rescheduleBusyIds.contains(bookingId);

    // Trainer is de afzender → geen actieknoppen, alleen status tonen
    if (message.isFromTrainer) {
      return RescheduleCardWidget.fromMessage(
        json,
        busy: isBusy,
        // Geen callbacks → kaart toont alleen info + status
      );
    }

    // Klant is de afzender → trainer kan reageren
    return RescheduleCardWidget.fromMessage(
      json,
      busy: isBusy,
      onAccept: () => _respondToReschedule(json!, bookingId, 'accept'),
      onReject: () => _respondToReschedule(json!, bookingId, 'reject'),
      onCounterPropose: () => _respondToReschedule(json!, bookingId, 'counter'),
    );
  }

  /// Reageer op een reschedule-verzoek van de klant.
  Future<void> _respondToReschedule(
    Map<String, dynamic> messageData,
    String bookingId,
    String action,
  ) async {
    if (bookingId.isEmpty) return;
    setState(() => _rescheduleBusyIds.add(bookingId));

    try {
      if (action == 'counter') {
        // Tegenvoorstel: datum/tijd picker
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now().add(const Duration(days: 1)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !mounted) {
          setState(() => _rescheduleBusyIds.remove(bookingId));
          return;
        }
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );
        if (time == null || !mounted) {
          setState(() => _rescheduleBusyIds.remove(bookingId));
          return;
        }
        final requestedAt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute,
        );
        await context.read<GymiesApi>().respondToRescheduleRequest(
          bookingId: bookingId,
          action: 'counter',
          requestedAt: requestedAt,
        );
      } else {
        await context.read<GymiesApi>().respondToRescheduleRequest(
          bookingId: bookingId,
          action: action,
        );
      }

      if (!mounted) return;

      // Bij accept: sync met kalender
      if (action == 'accept') {
        try {
          final enabled = await CalendarService.instance.isTrainerAutoSyncEnabled();
          if (enabled) {
            final requestedAt = DateTime.tryParse(
              mapStr(messageData, ['requested_at', 'requestedAt']) ,
            );
            if (requestedAt != null) {
              final booking = Booking(
                id: bookingId,
                trainerName: '',
                clientName: widget.conversation.clientName,
                scheduledAt: requestedAt,
                durationMinutes: int.tryParse(
                  mapStr(messageData, ['duration_minutes', 'durationMinutes']),
                ) ?? 60,
                status: 'confirmed',
                sessionType: mapStr(messageData, ['session_type', 'sessionType']).isEmpty
                    ? null
                    : mapStr(messageData, ['session_type', 'sessionType']),
              );
              await CalendarService.instance.addBookingToTrainerCalendar(booking);
            }
          }
        } catch (e) {
          // Fail-open: Calendar sync optional, rescheduling completes anyway
          if (kDebugMode) debugPrint('[TrainerChat] Add to calendar failed: $e');
          Sentry.addBreadcrumb(Breadcrumb(message: 'Calendar sync after reschedule failed: $e', category: 'chat'));
        }
      }

      await _load(background: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'accept'
                  ? 'Verplaatsing geaccepteerd'
                  : action == 'reject'
                      ? S.of(context).verzoekAfgewezen
                      : S.of(context).tegenvoorstelVerstuurd,
            ),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _rescheduleBusyIds.remove(bookingId));
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  // ── UI ─────────────────────────────────────────────────────

  // ── Slimme quick replies voor trainers ──────────────────────

  /// Analyseert het laatste klant-bericht + context om relevante
  /// trainer-snelantwoorden te tonen.
  List<Widget> _buildSmartTrainerReplies() {
    final chips = <Widget>[];
    final now = DateTime.now();
    final hour = now.hour;
    final clientName = widget.conversation.clientName;
    final firstName = clientName.split(' ').first;

    // Zoek het laatste bericht van de klant (niet van trainer)
    TrainerMessage? lastClientMsg;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (!_messages[i].isFromTrainer) {
        lastClientMsg = _messages[i];
        break;
      }
    }

    final clientText = lastClientMsg?.body.toLowerCase() ?? '';

    // ── 1. Reactief: reageer op wat de klant zei ──

    if (clientText.contains('afzeg') || clientText.contains(S.of(context).kanNiet) ||
        clientText.contains('lukt niet') || clientText.contains('annul')) {
      chips.add(_TrainerQuickReplyChip(label: S.of(context).geenProbleem, icon: Icons.check_rounded, onTap: () => _send(S.of(context).geenProbleemLaatMeWetenWanneer)));
      chips.add(_TrainerQuickReplyChip(label: S.of(context).verplaatsSessie, icon: Icons.event_repeat_rounded, onTap: _openRescheduleFlow));
    }
    else if (clientText.contains('verplaats') || clientText.contains('verzet') ||
             clientText.contains('ander tijdstip') || clientText.contains('andere dag')) {
      chips.add(_TrainerQuickReplyChip(label: S.of(context).verplaatsSessie, icon: Icons.event_repeat_rounded, onTap: _openRescheduleFlow));
      chips.add(_TrainerQuickReplyChip(label: 'Kan!', icon: Icons.check_circle_outline_rounded, onTap: () => _send(S.of(context).kanIkStuurJeEenVerplaatsingsverzoek)));
    }
    else if (clientText.contains('bedankt') || clientText.contains('dankje') ||
             clientText.contains('thanks') || clientText.contains('top')) {
      chips.add(_TrainerQuickReplyChip(label: S.of(context).graagGedaan, icon: Icons.favorite_outline_rounded, onTap: () => _send('Graag gedaan!')));
      chips.add(_TrainerQuickReplyChip(label: S.of(context).goedBezig, icon: Icons.thumb_up_outlined, onTap: () => _send('Goed bezig $firstName! Ga zo door 💪')));
    }
    else if (clientText.contains('super') || clientText.contains('geweldig') ||
             clientText.contains('goed') && clientText.contains('les')) {
      chips.add(_TrainerQuickReplyChip(label: S.of(context).blijTeHoren, icon: Icons.star_rounded, onTap: () => _send(S.of(context).blijDatTeHorenJeMaakt)));
      chips.add(_TrainerQuickReplyChip(label: 'Volgende keer', icon: Icons.trending_up_rounded, onTap: () => _send(S.of(context).mooiVolgendeKeerGaanWeEen)));
    }
    else if (clientText.contains('pittig') || clientText.contains('zwaar') ||
             clientText.contains('moeilijk') || clientText.contains('pijn')) {
      chips.add(_TrainerQuickReplyChip(label: 'Goed gedaan!', icon: Icons.emoji_events_outlined, onTap: () => _send(S.of(context).goedGedaanDatJeHebtDoorgezet)));
      chips.add(_TrainerQuickReplyChip(label: 'Neem rust', icon: Icons.self_improvement_rounded, onTap: () => _send(S.of(context).neemVoldoendeRustJeLichaamHeeft)));
    }
    else if (clientText.contains('vraag') || clientText.contains('hoe') ||
             clientText.contains(S.of(context).watMoet) || clientText.contains('uitleg')) {
      chips.add(_TrainerQuickReplyChip(label: 'Goeie vraag!', icon: Icons.lightbulb_outline_rounded, onTap: () => _send(S.of(context).goeieVraagIkLegHetEven)));
      chips.add(_TrainerQuickReplyChip(label: 'Even bellen?', icon: Icons.phone_outlined, onTap: () => _send(S.of(context).zalIkHetEvenTelefonischUitleggen)));
    }
    else if (clientText.contains('ik ben er') || clientText.contains('onderweg') ||
             clientText.contains('tot zo') || clientText.contains('kom eraan')) {
      chips.add(_TrainerQuickReplyChip(label: S.of(context).totZoChat, icon: Icons.waving_hand_outlined, onTap: () => _send('Top, tot zo!')));
      chips.add(_TrainerQuickReplyChip(label: S.of(context).ikStaKlaar, icon: Icons.check_circle_outline_rounded, onTap: () => _send('Mooi, ik sta klaar!')));
    }
    else if (clientText.contains(S.of(context).factuur) || clientText.contains('betaal') ||
             clientText.contains('prijs') || clientText.contains('kosten')) {
      chips.add(_TrainerQuickReplyChip(label: 'Ik check het', icon: Icons.search_rounded, onTap: () => _send(S.of(context).ikCheckHetEvenVoorJe)));
      chips.add(_TrainerQuickReplyChip(label: S.of(context).factuurVerstuurd, icon: Icons.receipt_long_rounded, onTap: () => _send(S.of(context).deFactuurIsVerstuurdNaarJe)));
    }

    // ── 2. Tijdsgebonden chips (als er geen reactieve match was) ──

    if (chips.isEmpty) {
      if (hour >= 6 && hour < 12) {
        chips.add(_TrainerQuickReplyChip(label: S.of(context).reminderSessie, icon: Icons.alarm_outlined, onTap: () => _send(S.of(context).vergeetJeSessieNietVandaagTot)));
        chips.add(_TrainerQuickReplyChip(label: S.of(context).hoeGaatHet, icon: Icons.waving_hand_outlined, onTap: () => _send('Goedemorgen $firstName! Hoe gaat het?')));
      } else if (hour >= 12 && hour < 18) {
        chips.add(_TrainerQuickReplyChip(label: S.of(context).hoeWasDeLes, icon: Icons.star_outline_rounded, onTap: () => _send(S.of(context).hoeWasDeLesVandaag)));
        chips.add(_TrainerQuickReplyChip(label: 'Schema klaar', icon: Icons.assignment_outlined, onTap: () => _send(S.of(context).jeNieuweTrainingsschemaIsKlaar)));
      } else {
        chips.add(_TrainerQuickReplyChip(label: S.of(context).goedBezig, icon: Icons.thumb_up_outlined, onTap: () => _send('Goed bezig $firstName! Ga zo door 💪')));
        chips.add(_TrainerQuickReplyChip(label: S.of(context).totMorgen, icon: Icons.nightlight_outlined, onTap: () => _send('Goed getraind vandaag. Tot de volgende!')));
      }
    }

    // ── 3. Universele trainer-chips achteraan ──
    final existingLabels = chips.whereType<_TrainerQuickReplyChip>().map((c) => c.label).toSet();
    // Voeg "Verplaats sessie" toe als universele chip (opent flow, stuurt geen tekst)
    if (!existingLabels.contains(S.of(context).verplaatsSessie)) {
      chips.add(_TrainerQuickReplyChip(
        label: S.of(context).verplaatsSessie,
        icon: Icons.event_repeat_rounded,
        onTap: _openRescheduleFlow,
      ));
    }
    // Nog max 1 universele tekst-chip
    final afterLabels = chips.whereType<_TrainerQuickReplyChip>().map((c) => c.label).toSet();
    final textUniversals = <List<dynamic>>[
      ['Goed bezig!', Icons.thumb_up_outlined, 'Goed bezig $firstName! 💪'],
      ['Tot zo!', Icons.waving_hand_outlined, 'Tot zo!'],
    ];
    for (final u in textUniversals) {
      if (afterLabels.contains(u[0])) continue;
      chips.add(_TrainerQuickReplyChip(
        label: u[0] as String,
        icon: u[1] as IconData,
        onTap: () => _send(u[2] as String),
      ));
      break; // max 1
    }

    return chips;
  }

  /// Toon naam-label boven de bubbel als de afzender wisselt t.o.v. vorig bericht.
  bool _showSenderLabel(int index) {
    if (index == 0) return true;
    final current = _messages[index].isFromTrainer;
    final previous = _messages[index - 1].isFromTrainer;
    return current != previous;
  }

  /// Controleert of bericht op index i op een andere dag valt dan het vorige bericht.
  bool _isDifferentDay(int index) {
    if (index <= 0 || index >= _messages.length) return false;
    final current = _messages[index].createdAt;
    final previous = _messages[index - 1].createdAt;
    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  /// Formatteer datum als "Vandaag", "Gisteren", of "dd MMM yyyy".
  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return S.of(context).vandaag;
    if (dateOnly == today.subtract(const Duration(days: 1))) return S.of(context).gisteren;
    const months = [
      'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
      'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  /// Totale items in de chat list: server-berichten + pending berichten.
  int get _totalItemCount => _messages.length + _pendingMessages.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: widget.conversation.clientName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: _openRescheduleFlow,
              icon: const Icon(Icons.event_repeat_rounded, size: 16),
              label: Text(
                S.of(context).verplaats,
                style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: GymiesColors.darkBlue,
                backgroundColor: GymiesColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GymiesListBody(
            loading: _loading,
            error: _error,
            onRefresh: _load,
            child: _messages.isEmpty && _pendingMessages.isEmpty && !_loading
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const SizedBox(height: 72),
                            const Icon(Icons.chat_bubble_outline,
                                size: 56, color: Colors.grey),
                            const SizedBox(height: 10),
                            Text(
                              S.of(context).nogGeenBerichten,
                              style: GoogleFonts.sora(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Stuur ${widget.conversation.clientName} een bericht om het gesprek te starten.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: _totalItemCount,
                      itemBuilder: (_, i) {
                        // ── Pending berichten na de server-berichten ──
                        if (i >= _messages.length) {
                          final pending = _pendingMessages[i - _messages.length];
                          final isFailed = pending['status'] == 'failed';
                          final isPending = pending['status'] == 'pending';
                          final body = pending['body']?.toString() ?? '';
                          return _buildBubble(
                            body: body,
                            mine: true,
                            ts: '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                            isPending: isPending,
                            isFailed: isFailed,
                            showLabel: i == _messages.length || (i > _messages.length),
                            showDateSeparator: false,
                            dateLabel: '',
                            index: i,
                            onRetry: isFailed ? () => _retryPending(pending) : null,
                          );
                        }

                        final m = _messages[i];

                        // ── Reschedule card detectie ──
                        final rescheduleCard = _buildRescheduleCard(m);
                        if (rescheduleCard != null) {
                          final showDateSep = i == 0 || _isDifferentDay(i);
                          final dateLabel = _formatDateLabel(m.createdAt);
                          return Column(
                            crossAxisAlignment: m.isFromTrainer
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (showDateSep)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        dateLabel,
                                        style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ),
                                ),
                              Align(
                                alignment: m.isFromTrainer
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: rescheduleCard,
                              ),
                            ],
                          );
                        }

                        // Verberg lege berichten (body is leeg of alleen whitespace/dash)
                        final bodyText = m.body.trim();
                        if (bodyText.isEmpty || bodyText == '-' || bodyText == '–') {
                          return const SizedBox.shrink();
                        }

                        final mine = m.isFromTrainer;
                        final ts =
                            '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';
                        final showLabel = _showSenderLabel(i);
                        final showDateSep = i == 0 || _isDifferentDay(i);
                        final dateLabel = _formatDateLabel(m.createdAt);

                        return _buildBubble(
                          body: m.body,
                          mine: mine,
                          ts: ts,
                          isPending: false,
                          isFailed: false,
                          showLabel: showLabel,
                          showDateSeparator: showDateSep,
                          dateLabel: dateLabel,
                          index: i,
                          senderName: mine ? 'Jij' : widget.conversation.clientName,
                        );
                      },
                    ),
                  ),
          ),
          // ── Slimme quick reply chips ──────────────────
          Builder(builder: (_) {
            final chips = _buildSmartTrainerReplies();
            if (chips.isEmpty) return const SizedBox.shrink();
            return Container(
              color: const Color(0xFFF7F8FA),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: chips),
              ),
            );
          }),
          // ── Text input ──────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: S.of(context).typEenBericht,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_sending || _controller.text.trim().isEmpty) ? null : () => _send(),
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bouwt een enkele chat-bubbel (herbruikbaar voor server + pending berichten).
  Widget _buildBubble({
    required String body,
    required bool mine,
    required String ts,
    required bool isPending,
    required bool isFailed,
    required bool showLabel,
    required bool showDateSeparator,
    required String dateLabel,
    required int index,
    String? senderName,
    VoidCallback? onRetry,
  }) {
    Widget? dateSeparator;
    if (showDateSeparator && dateLabel.isNotEmpty) {
      dateSeparator = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              dateLabel,
              style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (dateSeparator != null) dateSeparator,
        if (showLabel && senderName != null)
          Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : 14,
              bottom: 4,
              left: mine ? 0 : 4,
              right: mine ? 4 : 0,
            ),
            child: Text(
              senderName,
              style: GoogleFonts.sora(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ),
        GestureDetector(
          onTap: isFailed ? onRetry : null,
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isFailed
                    ? Colors.red.shade50
                    : mine
                        ? GymiesColors.darkBlue
                        : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine ? null : Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      body,
                      style: GoogleFonts.sora(
                        color: isFailed
                            ? Colors.red.shade700
                            : mine
                                ? Colors.white
                                : GymiesColors.darkBlue,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ts.isNotEmpty)
                        Text(
                          ts,
                          style: GoogleFonts.sora(
                            color: isFailed
                                ? Colors.red.shade400
                                : mine
                                    ? Colors.white54
                                    : Colors.grey.shade400,
                            fontSize: 10,
                          ),
                        ),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        if (isPending)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white54,
                            ),
                          )
                        else if (isFailed)
                          Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade400)
                        else
                          Icon(Icons.done_rounded, size: 14, color: Colors.white54),
                      ],
                    ],
                  ),
                  if (isFailed) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 12, color: Colors.red.shade500),
                        const SizedBox(width: 4),
                        Text(
                          S.of(context).tikOmOpnieuwTeVersturen,
                          style: GoogleFonts.sora(fontSize: 10, color: Colors.red.shade500, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Trainer Quick Reply Chip ──────────────────────────────────

// ── Booking Picker Bottom Sheet ───────────────────────────────

/// Bottom sheet waarmee de trainer een openstaande boeking kiest
/// om te verplaatsen.
class _RescheduleBookingPicker extends StatelessWidget {
  const _RescheduleBookingPicker({
    required this.bookings,
    required this.clientName,
  });

  final List<Booking> bookings;
  final String clientName;

  String _formatDate(DateTime d) {
    const days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
    const months = [
      'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
      'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatSessionType(String? type, BuildContext ctx) {
    if (type == null || type.isEmpty) return S.of(ctx).sessionSingle;
    switch (type.toLowerCase()) {
      case 'duo':
        return S.of(ctx).duoSessie;
      case 'groepsles':
      case 'group':
        return S.of(ctx).groepsles;
      case '1-op-1':
      case '1op1':
      case 'personal':
        return 'Personal Training';
      default:
        return '${type[0].toUpperCase()}${type.substring(1)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header with close button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.event_repeat_rounded,
                    color: GymiesColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.of(context).sessieVerplaatsen,
                        style: GoogleFonts.sora(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      Text(
                        'Kies een sessie met $clientName',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.grey.shade600,
                    iconSize: 20,
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          // ── Booking lijst ──
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: bookings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final b = bookings[i];
                final typeLabel = _formatSessionType(b.sessionType, ctx);
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(ctx).pop(b),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          // Datum badge
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: GymiesColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${b.scheduledAt.day}',
                                  style: GoogleFonts.sora(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                                Text(
                                  [
                                    'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
                                    'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
                                  ][b.scheduledAt.month - 1],
                                  style: GoogleFonts.sora(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDate(b.scheduledAt),
                                  style: GoogleFonts.sora(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$typeLabel · ${b.durationMinutes} min',
                                  style: GoogleFonts.sora(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainerQuickReplyChip extends StatelessWidget {
  const _TrainerQuickReplyChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: GymiesColors.primary.withOpacity(0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: GymiesColors.darkBlue),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
