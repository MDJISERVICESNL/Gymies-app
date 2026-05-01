import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
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
      // Meldingen op 0 zetten bij openen (gezien = gelezen)
      if (unread > 0) {
        try {
          await api.markNotificationsRead();
          _realtime()?.markAllRead();
          if (!mounted) return;
          final now = DateTime.now().toIso8601String();
          setState(() {
            for (final n in _notifications) {
              n['read_at'] = now;
              n['readAt'] = now;
              n['unread'] = false;
              n['is_unread'] = false;
            }
          });
        } catch (_) {
          // Stil: badge blijft staan bij fout
        }
      }
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

  /// Format a notification's created_at timestamp as relative time (human-friendly)
  String _formatRelativeTime(Map<String, dynamic> notification) {
    final createdAt = mapStr(notification, ['created_at', 'createdAt', 'date']);
    if (createdAt.isEmpty) return '';

    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return createdAt; // Fallback to raw if unparseable

    final now = DateTime.now();
    final diff = now.difference(parsed);

    // Less than 1 minute
    if (diff.inSeconds < 60) {
      return 'Zojuist';
    }

    // Less than 1 hour
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return '${mins == 1 ? '1 minuut' : '$mins minuten'} geleden';
    }

    // Less than 24 hours
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return '${hours} uur geleden';
    }

    // Yesterday
    if (diff.inDays == 1 && parsed.day == now.subtract(const Duration(days: 1)).day) {
      return 'Gisteren';
    }

    // Less than 7 days
    if (diff.inDays < 7) {
      final days = diff.inDays;
      return '${days} dag${days != 1 ? 'en' : ''} geleden';
    }

    // Older: return formatted date
    return '${parsed.day.toString().padLeft(2, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.year}';
  }

  /// Get icon for notification type
  IconData _getNotificationIcon(Map<String, dynamic> notification) {
    final type = _notificationType(notification).toLowerCase();

    if (type.contains('message') || type.contains('chat')) {
      return Icons.chat_bubble_outlined;
    } else if (type.contains('booking') || type.contains('session')) {
      return Icons.calendar_today_outlined;
    } else if (type.contains('invoice') || type.contains('payment')) {
      return Icons.receipt_outlined;
    } else if (type.contains('waitlist') || type.contains('standby')) {
      return Icons.hourglass_bottom_outlined;
    } else if (type.contains('reminder')) {
      return Icons.notifications_outlined;
    }

    return Icons.info_outlined;
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
    return mapStr(item, ['type', 'notification_type', 'category']).toLowerCase();
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
    final text =
        '${mapStr(item, ['title', 'subject'])} ${mapStr(item, ['body', 'message', 'text'])}'
            .toLowerCase();
    return type.contains('waitlist') ||
        type.contains('standby') ||
        text.contains('wachtlijst') ||
        text.contains('standby');
  }

  bool _hasDeepLinkTarget(Map<String, dynamic> item) {
    final type = _notificationType(item);
    return _conversationIdFromNotification(item).isNotEmpty ||
        _bookingIdFromNotification(item).isNotEmpty ||
        _invoiceIdFromNotification(item).isNotEmpty ||
        _trainerUserIdFromNotification(item).isNotEmpty ||
        _actionUrl(item).isNotEmpty ||
        type.contains('message') ||
        type.contains('chat') ||
        type.contains('booking') ||
        type.contains('session') ||
        _isStandbyNotification(item) ||
        type.contains('invoice') ||
        type.contains('payment');
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
          return AlertDialog(
            title: const Text('Standby plek beschikbaar'),
            content: Text(
              'Er is een plek vrijgekomen op ${slot.day.toString().padLeft(2, '0')}-${slot.month.toString().padLeft(2, '0')} om ${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}.\n\nNu 1-tap boeken?${expiresAt == null ? '' : '\n\nVerloopt over: $countdown'}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: expired
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                ),
                child: const Text('Boek nu'),
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

    if (bookingId.isNotEmpty ||
        type.contains('booking') ||
        type.contains('session')) {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ClientSessionsScreen()));
      return;
    }

    if (invoiceId.isNotEmpty ||
        type.contains('invoice') ||
        type.contains('payment')) {
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

    _showError('Geen gekoppelde actie voor deze melding.');
  }

  Future<void> _showNotificationDetail(Map<String, dynamic> item) async {
    final title = NotificationDisplayHelper.displayTitle(item);
    final body = NotificationDisplayHelper.displayBody(item);
    final type = mapStr(item, ['type', 'notification_type']);
    final createdAt = mapStr(item, ['created_at', 'createdAt', 'date']);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.fjallaOne(
                    fontSize: 20,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                if (type.isNotEmpty) Text('Type: $type'),
                if (createdAt.isNotEmpty) Text('Ontvangen: $createdAt'),
                const SizedBox(height: 10),
                Text(body),
                if (_hasDeepLinkTarget(item)) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _openNotificationTarget(item);
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open gerelateerde pagina'),
                    ),
                  ),
                ],
              ],
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
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Melding voorkeuren',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 20,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Slimme reminders: T-24u, T-2u, check-in venster open en gemiste check-in.',
                            style: TextStyle(color: Colors.blue.shade900),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...boolKeys.map((key) {
                          final value = _asBool(draft[key]);
                          return SwitchListTile(
                            value: value,
                            title: Text(_labelFromKey(key)),
                            onChanged: (v) {
                              setModalState(() => draft[key] = v);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredNotifications();
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Meldingen',
        actions: [
          IconButton(
            tooltip: 'Voorkeuren',
            onPressed: _savingPreferences ? null : _openPreferencesSheet,
            icon: const Icon(Icons.tune_rounded),
          ),
          TextButton(
            onPressed: _busy ? null : _markAllRead,
            child: Text(
              'Alles gelezen',
              style: GoogleFonts.fjallaOne(
                color: GymiesColors.primary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
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
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _NotificationStat(
                                    label: 'Totaal',
                                    value: '${_notifications.length}',
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _NotificationStat(
                                    label: 'Ongelezen',
                                    value: '${_unreadCount()}',
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('Alles')),
                            ButtonSegment(
                              value: 'unread',
                              label: Text('Ongelezen'),
                            ),
                          ],
                          selected: {_filter},
                          onSelectionChanged: (v) {
                            setState(() => _filter = v.first);
                          },
                        ),
                        const SizedBox(height: 10),
                        if (visible.isEmpty)
                          const _EmptyView(
                            title: 'Geen meldingen in dit filter',
                            subtitle: 'Probeer filter "Alles".',
                          )
                        else
                          ...visible.map((n) {
                            final title = NotificationDisplayHelper.displayTitle(n);
                            final body = NotificationDisplayHelper.displayBody(n);
                            final relativeTime = _formatRelativeTime(n);
                            final unread = _isUnread(n);
                            final typeIcon = _getNotificationIcon(n);
                            return Card(
                              color: unread
                                  ? GymiesColors.primary.withValues(alpha: 0.16)
                                  : Colors.white,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: unread
                                          ? GymiesColors.primary
                                          : GymiesColors.darkBlue.withValues(alpha: 0.3),
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: unread
                                          ? GymiesColors.primary.withValues(alpha: 0.25)
                                          : GymiesColors.darkBlue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      typeIcon,
                                      color: unread
                                          ? GymiesColors.primary
                                          : GymiesColors.darkBlue.withValues(alpha: 0.7),
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    relativeTime.isNotEmpty
                                        ? '$body\n$relativeTime'
                                        : body,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  isThreeLine: true,
                                  trailing: unread
                                      ? Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: GymiesColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : null,
                                  onTap: () => _onNotificationTap(n),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
        ),
    );
  }
}

class _NotificationStat extends StatelessWidget {
  const _NotificationStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.fjallaOne(fontSize: 20, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color)),
        ],
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
          const Icon(
            Icons.notifications_none_rounded,
            size: 56,
            color: Colors.grey,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.fjallaOne(
              fontSize: 20,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
