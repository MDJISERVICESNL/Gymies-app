import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../utils/haptics.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/notification_realtime_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/notification_display_helper.dart';
import '../utils/url_launcher_utils.dart';
import 'client_invoices_screen.dart';
import 'client_messages_screen.dart' show ClientMessagesScreen, ClientChatScreen;
import 'client_sessions_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';
import 'widgets/gymies_dialog.dart';

class ClientNotificationsScreen extends StatefulWidget {
  const ClientNotificationsScreen({super.key});

  @override
  State<ClientNotificationsScreen> createState() =>
      _ClientNotificationsScreenState();
}

class _ClientNotificationsScreenState extends State<ClientNotificationsScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _savingPreferences = false;
  String? _error;
  List<Map<String, dynamic>> _notifications = [];
  Map<String, dynamic> _preferences = {};
  String _filter = 'all';
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _realtimeSub = _realtime()?.events.listen((event) {
        if (!mounted) return;
        setState(() {
          _notifications = [event, ..._notifications];
        });
      });
    });
    _loadOnOpen();
  }

  Future<void> _loadOnOpen() async {
    await _load();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final list = await api.getNotifications();
      final prefs = await api.getNotificationPreferences();
      final unread = list.where(_isUnread).length;
      if (!mounted) return;
      _realtime()?.setUnreadCount(unread);
      setState(() {
        _notifications = list;
        _preferences = prefs;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon meldingen niet laden.';
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _map(Map<String, dynamic> map, List<String> keys) {
    final v = mapPick(map, keys);
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  bool _isUnread(Map<String, dynamic> item) {
    final unread = mapPick(item, ['unread', 'is_unread']);
    if (unread is bool) return unread;
    if (unread is num) return unread.toInt() == 1;
    final readAt = mapStr(item, ['read_at', 'readAt']);
    return readAt.isEmpty;
  }

  List<Map<String, dynamic>> _filteredNotifications() {
    if (_filter == 'all') return _notifications;
    return _notifications.where(_isUnread).toList();
  }

  int _unreadCount() => _notifications.where(_isUnread).length;


  /// Notificatie-type info: icoon, kleur, label — doorzoekt type + tekst.
  ({IconData icon, Color color, Color bgColor, String label}) _getNotificationMeta(Map<String, dynamic> notification) {
    final type = _notificationType(notification);
    final data = _map(notification, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    final fullText = '$type ${mapStr(notification, ['title', 'subject'])} ${mapStr(notification, ['body', 'message', 'text'])} ${mapStr(notification, ['event_type', 'eventType', 'channel'])} ${mapStr(data, ['title', 'subject'])} ${mapStr(data, ['body', 'message', 'text'])}'.toLowerCase().replaceAll('_', ' ');

    if (fullText.contains('annulering') || fullText.contains('geannuleerd') || fullText.contains('cancel')) {
      return (icon: Icons.event_busy_rounded, color: const Color(0xFFD32F2F), bgColor: const Color(0xFFFCEBEB), label: 'Annulering');
    }
    if (fullText.contains('bevestig') || fullText.contains('confirmed') || fullText.contains('goedgekeurd')) {
      return (icon: Icons.check_circle_outlined, color: const Color(0xFF2E7D32), bgColor: const Color(0xFFE8F5E9), label: 'Bevestigd');
    }
    if (fullText.contains('message') || fullText.contains('chat') || fullText.contains('bericht')) {
      return (icon: Icons.chat_bubble_outline_rounded, color: const Color(0xFF1565C0), bgColor: const Color(0xFFE3F2FD), label: 'Bericht');
    }
    if (fullText.contains('booking') || fullText.contains('session') || fullText.contains('sessie') || fullText.contains('boeking')) {
      return (icon: Icons.calendar_today_rounded, color: GymiesColors.darkBlue, bgColor: const Color(0xFFFFF3D6), label: 'Boeking');
    }
    if (fullText.contains('invoice') || fullText.contains('payment') || fullText.contains('factuur') || fullText.contains('betaling')) {
      return (icon: Icons.receipt_long_rounded, color: const Color(0xFF6A1B9A), bgColor: const Color(0xFFF3E5F5), label: 'Betaling');
    }
    if (fullText.contains('waitlist') || fullText.contains('standby') || fullText.contains('wachtlijst')) {
      return (icon: Icons.event_available_rounded, color: const Color(0xFF00695C), bgColor: const Color(0xFFE0F2F1), label: 'Wachtlijst');
    }
    if (fullText.contains('reminder') || fullText.contains('herinnering')) {
      return (icon: Icons.alarm_rounded, color: const Color(0xFFE65100), bgColor: const Color(0xFFFFF3E0), label: 'Herinnering');
    }
    if (fullText.contains('check-in') || fullText.contains('checkin')) {
      return (icon: Icons.where_to_vote_rounded, color: const Color(0xFF00838F), bgColor: const Color(0xFFE0F7FA), label: 'Check-in');
    }
    if (fullText.contains('review') || fullText.contains('beoordeling')) {
      return (icon: Icons.star_outline_rounded, color: const Color(0xFFF9A825), bgColor: const Color(0xFFFFF8E1), label: 'Review');
    }
    if (fullText.contains('welkom') || fullText.contains('welcome')) {
      return (icon: Icons.waving_hand_rounded, color: const Color(0xFF0F6E56), bgColor: const Color(0xFFE1F5EE), label: 'Welkom');
    }
    if (fullText.contains('reschedule') || fullText.contains('verplaats') || fullText.contains('verzet')) {
      return (icon: Icons.update_rounded, color: const Color(0xFF4527A0), bgColor: const Color(0xFFEDE7F6), label: 'Verplaatst');
    }
    if (fullText.contains('ticket') || fullText.contains('support')) {
      return (icon: Icons.support_agent_rounded, color: const Color(0xFF37474F), bgColor: const Color(0xFFECEFF1), label: 'Support');
    }
    if (fullText.contains('promo') || fullText.contains('aanbieding') || fullText.contains('korting')) {
      return (icon: Icons.local_offer_rounded, color: const Color(0xFFC62828), bgColor: const Color(0xFFFCE4EC), label: 'Actie');
    }

    return (icon: Icons.notifications_outlined, color: GymiesColors.darkBlue, bgColor: const Color(0xFFE8EAF0), label: 'Systeem');
  }

  /// Compacte datum: "17 mrt" of "3 apr 14:30"
  String _formatShortDate(Map<String, dynamic> notification) {
    final raw = mapStr(notification, ['created_at', 'createdAt', 'date']);
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} uur';
    if (diff.inDays == 1) return 'Gisteren';
    if (diff.inDays < 7) return '${diff.inDays} dagen';
    if (dt.year == now.year) return '${dt.day} ${months[dt.month - 1]}';
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  /// Tijdsrelatieve groepering: Vandaag, Gisteren, Deze week, Vorige week, Eerder
  String _timeGroup(Map<String, dynamic> notification) {
    final raw = mapStr(notification, ['created_at', 'createdAt', 'date']);
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final notifDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(notifDay).inDays;
    if (diff == 0) return 'Vandaag';
    if (diff == 1) return 'Gisteren';
    if (diff <= 7) return 'Deze week';
    if (diff <= 14) return 'Vorige week';
    return 'Eerder';
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    final s = (v ?? '').toString().toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'yes' || s == 'on';
  }

  String _labelFromKey(String key) {
    final normalized = key.toLowerCase();
    if (normalized == 'reminder_t24h_push') return 'Reminder 24 uur vooraf';
    if (normalized == 'reminder_t2h_push') return 'Reminder 2 uur vooraf';
    if (normalized == 'reminder_check_in_window_push') {
      return 'Reminder check-in venster open';
    }
    if (normalized == 'reminder_missed_check_in_push') {
      return 'Reminder gemiste check-in';
    }
    final spaced = key.replaceAll('_', ' ').replaceAll('-', ' ');
    return spaced.isEmpty
        ? key
        : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  Future<void> _markAllRead() async {
    if (_busy) return;
    Haptics.light();
    final api = context.read<GymiesApi>();
    final realtime = _realtime();
    setState(() => _busy = true);
    try {
      await api.markNotificationsRead();
      realtime?.markAllRead();
      realtime?.setUnreadCount(0);
      if (!mounted) return;
      // Update lokale state; niet _load() - die kan cached API data teruggeven en badge overschrijven
      final now = DateTime.now().toIso8601String();
      setState(() {
        for (final n in _notifications) {
          n['read_at'] = now;
          n['readAt'] = now;
          n['unread'] = false;
          n['is_unread'] = false;
        }
        _filter = 'all';
      });
      _showSuccess('Meldingen gemarkeerd als gelezen');
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markSingleRead(Map<String, dynamic> item) async {
    final id = mapStr(item, ['id', 'notification_id', 'notificationId']);
    if (id.isEmpty) return;
    final api = context.read<GymiesApi>();
    final realtime = _realtime();
    try {
      realtime?.markOneRead(); // Badge -1 direct
      await api.markNotificationsRead(notificationId: id);
      if (!mounted) return;
      await _load();
    } catch (_) {
      // Stil falen; lijst blijft bruikbaar.
    }
  }

  /// Slimme tap: markeer gelezen (badge -1) en ga naar target of detail.
  Future<void> _onNotificationTap(Map<String, dynamic> item) async {
    if (_isUnread(item)) await _markSingleRead(item);
    if (!mounted) return;
    if (_hasDeepLinkTarget(item)) {
      await _openNotificationTarget(item);
    } else {
      await _showNotificationDetail(item);
    }
  }

  String _notificationType(Map<String, dynamic> item) {
    var raw = mapStr(item, ['type', 'notification_type', 'category', 'event_type', 'eventType']);
    // Laravel class name → pak alleen de slug
    if (raw.contains('\\')) raw = raw.split('\\').last;
    raw = raw.toLowerCase().replaceAll('_', ' ');
    // Ook payload doorzoeken voor een concreter type
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    final payloadType = mapStr(data, ['type', 'notification_type', 'category', 'event', 'action', 'event_type']).toLowerCase().replaceAll('_', ' ');
    final channel = mapStr(item, ['channel']).toLowerCase();
    // Combineer voor bredere keyword-matching
    return '$raw $payloadType $channel'.trim();
  }

  String _conversationIdFromNotification(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    return mapStr(item, ['conversation_id', 'conversationId']).isNotEmpty
        ? mapStr(item, ['conversation_id', 'conversationId'])
        : mapStr(data, ['conversation_id', 'conversationId']);
  }

  String _invoiceIdFromNotification(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    return mapStr(item, ['invoice_id', 'invoiceId']).isNotEmpty
        ? mapStr(item, ['invoice_id', 'invoiceId'])
        : mapStr(data, ['invoice_id', 'invoiceId']);
  }

  String _bookingIdFromNotification(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    return mapStr(item, ['booking_id', 'bookingId', 'session_id']).isNotEmpty
        ? mapStr(item, ['booking_id', 'bookingId', 'session_id'])
        : mapStr(data, ['booking_id', 'bookingId', 'session_id']);
  }

  String _actionUrl(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    return mapStr(item, ['action_url', 'url', 'link']).isNotEmpty
        ? mapStr(item, ['action_url', 'url', 'link'])
        : mapStr(data, ['action_url', 'url', 'link']);
  }

  String _trainerUserIdFromNotification(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    return mapStr(item, [
          'trainer_user_id',
          'trainerUserId',
          'trainer_id',
        ]).isNotEmpty
        ? mapStr(item, ['trainer_user_id', 'trainerUserId', 'trainer_id'])
        : mapStr(data, ['trainer_user_id', 'trainerUserId', 'trainer_id']);
  }

  DateTime? _standbyScheduledAtFromNotification(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    final raw = mapStr(item, ['scheduled_at', 'slot_at', 'starts_at']).isNotEmpty
        ? mapStr(item, ['scheduled_at', 'slot_at', 'starts_at'])
        : mapStr(data, ['scheduled_at', 'slot_at', 'starts_at']);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  DateTime? _standbyExpiresAtFromNotification(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    final raw = mapStr(item, ['expires_at', 'offer_expires_at']).isNotEmpty
        ? mapStr(item, ['expires_at', 'offer_expires_at'])
        : mapStr(data, ['expires_at', 'offer_expires_at']);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _standbyOfferIdFromNotification(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    return mapStr(item, [
          'offer_id',
          'waitlist_offer_id',
          'standby_offer_id',
        ]).isNotEmpty
        ? mapStr(item, ['offer_id', 'waitlist_offer_id', 'standby_offer_id'])
        : mapStr(data, ['offer_id', 'waitlist_offer_id', 'standby_offer_id']);
  }

  bool _isStandbyNotification(Map<String, dynamic> item) {
    final type = _notificationType(item);
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    final text =
        '${mapStr(item, ['title', 'subject'])} ${mapStr(item, ['body', 'message', 'text'])} ${mapStr(data, ['title', 'subject'])} ${mapStr(data, ['body', 'message', 'text'])}'
            .toLowerCase();
    return type.contains('waitlist') ||
        type.contains('standby') ||
        text.contains('wachtlijst') ||
        text.contains('standby');
  }

  bool _hasDeepLinkTarget(Map<String, dynamic> item) {
    // Gebruik de verbeterde helper die ook payload doorzoekt
    return NotificationDisplayHelper.hasActionableTarget(item);
  }

  Future<bool> _openByActionUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    final all = '$path ${uri.query.toLowerCase()}';
    if (all.contains('conversation') || all.contains('chat')) {
      if (!mounted) return true;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientMessagesScreen()));
      return true;
    }
    if (all.contains('booking') || all.contains('session')) {
      if (!mounted) return true;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientSessionsScreen()));
      return true;
    }
    if (all.contains('invoice') || all.contains('payment')) {
      if (!mounted) return true;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientInvoicesScreen()));
      return true;
    }
    return false;
  }

  Future<void> _openStandbyQuickBook(Map<String, dynamic> item) async {
    final api = context.read<GymiesApi>();
    final trainerUserId = _trainerUserIdFromNotification(item);
    final slot = _standbyScheduledAtFromNotification(item);
    final offerId = _standbyOfferIdFromNotification(item);
    final expiresAt = _standbyExpiresAtFromNotification(item);
    if (trainerUserId.isEmpty || slot == null) {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientSessionsScreen()));
      return;
    }
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      _showError('Deze standby-aanbieding is verlopen.');
      return;
    }
    String timerLabel() {
      if (expiresAt == null) return '';
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining.inSeconds <= 0) return '00:00';
      final m = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    var countdown = timerLabel();
    Timer? ticker;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
            final next = timerLabel();
            if (next != countdown) {
              setDialogState(() => countdown = next);
            }
            if (next == '00:00') {
              Navigator.of(dialogContext).pop(false);
            }
          });
          final expired = expiresAt != null && countdown == '00:00';
          return GymiesDialog(
            title: 'Standby plek beschikbaar',
            headerIcon: Icons.event_available_rounded,
            content: Text(
              'Er is een plek vrijgekomen op ${slot.day.toString().padLeft(2, '0')}-${slot.month.toString().padLeft(2, '0')} om ${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}.\n\nNu 1-tap boeken?${expiresAt == null ? '' : '\n\nVerloopt over: $countdown'}',
            ),
            actions: [
              GymiesDialogAction(
                label: 'Later',
                returnValue: false,
              ),
              GymiesDialogAction(
                label: 'Boek nu',
                isPrimary: true,
                returnValue: true,
                onPressed: expired ? null : () {},
              ),
            ],
          );
        },
      ),
    );
    ticker?.cancel();
    if (confirm != true) return;
    try {
      if (offerId.isNotEmpty) {
        await api.acceptWaitlistOffer(offerId);
      } else {
        await api.createDirectBooking(
          trainerUserId: trainerUserId,
          scheduledAt: slot,
          note: 'Booked via standby notification',
        );
      }
      if (!mounted) return;
      _showSuccess('Standby sessie geboekt');
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientSessionsScreen()));
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Boeken via standby mislukt.');
    }
  }

  Future<void> _openNotificationTarget(Map<String, dynamic> item) async {
    final type = _notificationType(item);
    final conversationId = _conversationIdFromNotification(item);
    final bookingId = _bookingIdFromNotification(item);
    final invoiceId = _invoiceIdFromNotification(item);
    final url = _actionUrl(item);
    final title =
        mapStr(item, ['trainer_name', 'trainerName', 'title']).isNotEmpty
        ? mapStr(item, ['trainer_name', 'trainerName', 'title'])
        : 'Chat';

    if (conversationId.isNotEmpty) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ClientChatScreen(conversationId: conversationId, title: title),
        ),
      );
      return;
    }

    if (type.contains('message') || type.contains('chat')) {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientMessagesScreen()));
      return;
    }

    if (_isStandbyNotification(item)) {
      await _openStandbyQuickBook(item);
      return;
    }

    // Bouw fullText op voor bredere keyword-matching (vangnet als type kaal is)
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    final fullText = '$type ${mapStr(item, ['title', 'subject'])} ${mapStr(item, ['body', 'message', 'text'])} ${mapStr(data, ['title', 'subject'])} ${mapStr(data, ['body', 'message', 'text'])}'.toLowerCase();

    if (bookingId.isNotEmpty ||
        fullText.contains('booking') || fullText.contains('boeking') ||
        fullText.contains('session') || fullText.contains('sessie') ||
        fullText.contains('annulering') || fullText.contains('bevestig') ||
        fullText.contains('herinnering') || fullText.contains('reminder') ||
        fullText.contains('check-in') || fullText.contains('checkin')) {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientSessionsScreen()));
      return;
    }

    if (invoiceId.isNotEmpty ||
        fullText.contains('invoice') || fullText.contains('factuur') ||
        fullText.contains('payment') || fullText.contains('betaling')) {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientInvoicesScreen()));
      return;
    }

    if (url.isNotEmpty) {
      if (await _openByActionUrl(url)) return;
      final uri = Uri.tryParse(url);
      if (uri == null) {
        _showError('Link in melding is ongeldig.');
        return;
      }
      // Valideer domein en schema vóór openen (voorkomt open-redirect via server-gecontroleerde URLs).
      final opened = await safeLaunchUrl(url);
      if (!opened) _showError('Meldingslink kan niet worden geopend (onbekend domein of ongeldige URL).');
      return;
    }

    // Fallback: toon het detail-dialoog met alle info die we hebben
    await _showNotificationDetail(item);
  }

  Future<void> _showNotificationDetail(Map<String, dynamic> item) async {
    final title = NotificationDisplayHelper.displayTitle(item);
    final body = NotificationDisplayHelper.displayBody(item);
    final type = mapStr(item, ['type', 'notification_type']);
    final createdAt = mapStr(item, ['created_at', 'createdAt', 'date']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: GymiesColors.darkBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.notifications_outlined, color: GymiesColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (type.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.sora(color: Colors.grey.shade700, fontSize: 13),
                          children: [
                            TextSpan(text: 'Type: ', style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                            TextSpan(text: type),
                          ],
                        ),
                      ),
                    ),
                  if (createdAt.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.sora(color: Colors.grey.shade700, fontSize: 13),
                          children: [
                            TextSpan(text: 'Ontvangen: ', style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                            TextSpan(text: createdAt),
                          ],
                        ),
                      ),
                    ),
                  Text(
                    body,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      color: Colors.grey.shade800,
                      height: 1.6,
                    ),
                  ),
                  if (_hasDeepLinkTarget(item)) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _openNotificationTarget(item);
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open gerelateerde pagina'),
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.darkBlue,
                          foregroundColor: GymiesColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPreferencesSheet() async {
    const smartReminderDefaults = <String, bool>{
      'reminder_t24h_push': true,
      'reminder_t2h_push': true,
      'reminder_check_in_window_push': true,
      'reminder_missed_check_in_push': true,
    };
    final seededPrefs = <String, dynamic>{
      ...smartReminderDefaults,
      ..._preferences,
    };
    final boolKeys =
        seededPrefs.entries
            .where(
              (e) => e.value is bool || e.value is num || e.value is String,
            )
            .where((e) {
              final key = e.key.toLowerCase();
              return key.contains('push') ||
                  key.contains('reminder') ||
                  key.contains('email') ||
                  key.contains('sms') ||
                  key.contains('booking') ||
                  key.contains('message') ||
                  key.contains('invoice') ||
                  key.contains('promo') ||
                  key.contains('marketing') ||
                  key.contains('notification') ||
                  key.contains('enabled') ||
                  key.contains('alerts');
            })
            .map((e) => e.key)
            .toList()
          ..sort();
    if (boolKeys.isEmpty) {
      _showError(
        'Geen wijzigbare voorkeurvelden gevonden in notifications/preferences.',
      );
      return;
    }
    final draft = <String, dynamic>{...seededPrefs};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: GymiesColors.darkBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.tune_rounded, color: GymiesColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Melding voorkeuren',
                        style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Text(
                            'Slimme reminders: T-24u, T-2u, check-in venster open en gemiste check-in.',
                            style: GoogleFonts.sora(color: Colors.blue.shade900, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...boolKeys.map((key) {
                          final value = _asBool(draft[key]);
                          return SwitchListTile(
                            value: value,
                            title: Text(
                              _labelFromKey(key),
                              style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            onChanged: (v) {
                              setModalState(() => draft[key] = v);
                            },
                            contentPadding: EdgeInsets.zero,
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _savingPreferences
                        ? null
                        : () async {
                            final navigator = Navigator.of(ctx);
                            setState(() => _savingPreferences = true);
                            try {
                              final updated = await context
                                  .read<GymiesApi>()
                                  .updateNotificationPreferences(draft);
                              if (!mounted) return;
                              setState(() {
                                _preferences = updated.isEmpty
                                    ? draft
                                    : updated;
                              });
                              if (!mounted) return;
                              navigator.pop();
                              _showSuccess('Voorkeuren opgeslagen');
                            } on ApiException catch (e) {
                              _showError(e.message);
                            } finally {
                              if (mounted) {
                                setState(() => _savingPreferences = false);
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                    child: const Text('Opslaan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Bouw de lijst met maand-groepering
  List<Widget> _buildGroupedNotifications(List<Map<String, dynamic>> visible) {
    final widgets = <Widget>[];
    String? lastGroup;

    for (var i = 0; i < visible.length; i++) {
      final n = visible[i];
      final group = _timeGroup(n);

      // Maand-header toevoegen als het een nieuwe groep is
      if (group.isNotEmpty && group != lastGroup) {
        lastGroup = group;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 4 : 16,
              bottom: 8,
              left: 4,
            ),
            child: Text(
              group.toUpperCase(),
              style: GoogleFonts.sora(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 0.8,
              ),
            ),
          ),
        );
      }

      final title = NotificationDisplayHelper.displayTitle(n);
      final body = NotificationDisplayHelper.displayBody(n);
      final shortDate = _formatShortDate(n);
      final unread = _isUnread(n);
      final meta = _getNotificationMeta(n);
      final hasAction = _hasDeepLinkTarget(n);

      widgets.add(
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 350 + (i.clamp(0, 8) * 50)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - value)),
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                Haptics.light();
                _onNotificationTap(n);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        // Gekleurde linkerbalk
                        Container(width: 4, color: meta.color),
                      // Content
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Type icoon
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: meta.bgColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(meta.icon, color: meta.color, size: 20),
                              ),
                              const SizedBox(width: 12),
                              // Tekst content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Titel + datum
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: GoogleFonts.sora(
                                              fontSize: 14,
                                              fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                                              color: GymiesColors.darkBlue,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (unread)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: const EdgeInsets.only(left: 6, right: 6),
                                            decoration: BoxDecoration(
                                              color: meta.color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        Text(
                                          shortDate,
                                          style: GoogleFonts.sora(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Body
                                    Text(
                                      body,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.sora(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Type badge + pijl
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: meta.bgColor,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            meta.label,
                                            style: GoogleFonts.sora(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: meta.color,
                                            ),
                                          ),
                                        ),
                                        if (hasAction) ...[
                                          const Spacer(),
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 12,
                                            color: GymiesColors.darkBlue.withValues(alpha: 0.35),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredNotifications();
    final unreadCount = _unreadCount();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            backgroundColor: GymiesColors.darkBlue,
            foregroundColor: Colors.white,
            pinned: true,
            expandedHeight: 140,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: () {
                Haptics.selection();
                Navigator.of(context).pop();
              },
            ),
            title: Text('Meldingen', style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                tooltip: 'Voorkeuren',
                onPressed: _savingPreferences ? null : () {
                  Haptics.selection();
                  _openPreferencesSheet();
                },
                icon: const Icon(Icons.tune_rounded, size: 22),
              ),
              TextButton(
                onPressed: (_busy || unreadCount == 0) ? null : () {
                  Haptics.light();
                  _markAllRead();
                },
                child: Text(
                  unreadCount > 0 ? 'Alles gelezen' : 'Gelezen',
                  style: GoogleFonts.sora(
                    color: unreadCount > 0
                        ? GymiesColors.primary
                        : Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: Container(
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildFilterTab('all', 'Alles (${_notifications.length})', _filter == 'all'),
                    _buildFilterTab('unread', 'Ongelezen ($unreadCount)', _filter == 'unread'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: GymiesListBody(
          loading: _loading,
          error: _error,
          onRefresh: _load,
          child: _notifications.isEmpty
              ? ListView(
                  children: const [
                    _EmptyView(
                      title: 'Geen meldingen',
                      subtitle: 'Nieuwe updates verschijnen hier.',
                    ),
                  ],
                )
              : visible.isEmpty
                  ? ListView(
                      children: const [
                        _EmptyView(
                          title: 'Geen ongelezen meldingen',
                          subtitle: 'Alle meldingen zijn gelezen.',
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: _buildGroupedNotifications(visible),
                    ),
        ),
      ),
    );
  }

  Widget _buildFilterTab(String value, String label, bool isActive) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Haptics.light();
          setState(() => _filter = value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isActive ? GymiesColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive ? GymiesColors.darkBlue : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}


class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 72),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 32,
              color: GymiesColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 20,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
