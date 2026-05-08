import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/notification_realtime_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/notification_display_helper.dart';
import '../utils/url_launcher_utils.dart';
import 'trainer_finance_screen.dart';
import 'trainer_messages_screen.dart';
import 'trainer_sessions_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';
import '../utils/haptics.dart';

class TrainerNotificationsScreen extends StatefulWidget {
  const TrainerNotificationsScreen({super.key});

  @override
  State<TrainerNotificationsScreen> createState() =>
      _TrainerNotificationsScreenState();
}

class _TrainerNotificationsScreenState
    extends State<TrainerNotificationsScreen> {
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
      final items = await api.getNotifications();
      final prefs = await api.getNotificationPreferences();
      final unread = items.where(_isUnread).length;
      if (!mounted) return;
      _realtime()?.setUnreadCount(unread);
      setState(() {
        _notifications = items;
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
        _error = S.of(context).konMeldingenNietLaden;
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

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'on';
  }

  bool _isUnread(Map<String, dynamic> item) {
    final unread = mapPick(item, ['unread', 'is_unread']);
    if (unread is bool) return unread;
    if (unread is num) return unread.toInt() == 1;
    return mapStr(item, ['read_at', 'readAt']).isEmpty;
  }

  String _type(Map<String, dynamic> item) {
    return mapStr(item, ['type', 'notification_type', 'category']).toLowerCase();
  }

  String _category(Map<String, dynamic> item) {
    final type = _type(item);
    final title = mapStr(item, ['title', 'subject']).toLowerCase();
    final body = mapStr(item, ['body', 'message', 'text']).toLowerCase();
    final all = '$type $title $body';
    if (all.contains('booking') ||
        all.contains(S.of(context).boeking) ||
        all.contains('session') ||
        all.contains(S.of(context).sessie3)) {
      return 'bookings';
    }
    if (all.contains('message') ||
        all.contains('bericht') ||
        all.contains('chat')) {
      return 'messages';
    }
    if (all.contains('invoice') ||
        all.contains(S.of(context).factuur) ||
        all.contains('payment') ||
        all.contains('payout') ||
        all.contains('revenue') ||
        all.contains('omzet')) {
      return 'financial';
    }
    if (all.contains('required') ||
        all.contains('pending') ||
        all.contains('urgent') ||
        all.contains('actie')) {
      return 'action';
    }
    return 'other';
  }

  bool _requiresAction(Map<String, dynamic> item) {
    final status = mapStr(item, ['status']).toLowerCase();
    if (status == 'requires_action' || status == 'pending') return true;
    return _category(item) == 'action' ||
        (_category(item) == 'bookings' && _isUnread(item));
  }

  List<Map<String, dynamic>> _visible() {
    return _notifications.where((n) {
      switch (_filter) {
        case 'action':
          return _requiresAction(n);
        case 'bookings':
          return _category(n) == 'bookings';
        case 'messages':
          return _category(n) == 'messages';
        case 'financial':
          return _category(n) == 'financial';
        default:
          return true;
      }
    }).toList();
  }

  int _countBy(String key) {
    if (key == 'action') return _notifications.where(_requiresAction).length;
    return _notifications.where((n) => _category(n) == key).length;
  }

  String _labelFromKey(String key) {
    final normalized = key.toLowerCase();
    if (normalized == 'reminder_t24h_push') return S.of(context).reminder24UurVooraf;
    if (normalized == 'reminder_t2h_push') return S.of(context).reminder2UurVooraf;
    if (normalized == 'reminder_check_in_window_push') {
      return 'Reminder check-in venster open';
    }
    if (normalized == 'reminder_missed_check_in_push') {
      return 'Reminder gemiste check-in';
    }
    final spaced = key.replaceAll('_', ' ').replaceAll('-', ' ');
    if (spaced.isEmpty) return key;
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
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
      _showSuccess(S.of(context).meldingenGemarkeerdAlsGelezen);
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markOneRead(Map<String, dynamic> item) async {
    final id = mapStr(item, ['id', 'notification_id', 'notificationId']);
    if (id.isEmpty) return;
    final api = context.read<GymiesApi>();
    final realtime = _realtime();
    try {
      realtime?.markOneRead(); // Badge -1 direct (optimistisch)
      await api.markNotificationsRead(notificationId: id);
      if (!mounted) return;
      await _load();
    } catch (_) {
      // Stil falen.
    }
  }

  /// Slimme tap: markeer gelezen (badge -1) en ga naar target of detail.
  Future<void> _onNotificationTap(Map<String, dynamic> item) async {
    Haptics.selection();
    if (_isUnread(item)) await _markOneRead(item);
    if (!mounted) return;
    if (_hasTarget(item)) {
      await _openTarget(item);
    } else {
      await _openDetail(item);
    }
  }

  bool _hasTarget(Map<String, dynamic> item) {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    final conversationId =
        mapStr(item, ['conversation_id', 'conversationId']).isNotEmpty
        ? mapStr(item, ['conversation_id', 'conversationId'])
        : mapStr(data, ['conversation_id', 'conversationId']);
    final bookingId =
        mapStr(item, ['booking_id', 'bookingId', 'session_id']).isNotEmpty
        ? mapStr(item, ['booking_id', 'bookingId', 'session_id'])
        : mapStr(data, ['booking_id', 'bookingId', 'session_id']);
    final invoiceId = mapStr(item, ['invoice_id', 'invoiceId']).isNotEmpty
        ? mapStr(item, ['invoice_id', 'invoiceId'])
        : mapStr(data, ['invoice_id', 'invoiceId']);
    final actionUrl = mapStr(item, ['action_url', 'url', 'link']).isNotEmpty
        ? mapStr(item, ['action_url', 'url', 'link'])
        : mapStr(data, ['action_url', 'url', 'link']);
    final category = _category(item);
    return conversationId.isNotEmpty ||
        bookingId.isNotEmpty ||
        invoiceId.isNotEmpty ||
        actionUrl.isNotEmpty ||
        category == 'bookings' ||
        category == 'messages' ||
        category == 'financial';
  }

  Future<void> _openTarget(Map<String, dynamic> item) async {
    final data = _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
    final conversationId =
        mapStr(item, ['conversation_id', 'conversationId']).isNotEmpty
        ? mapStr(item, ['conversation_id', 'conversationId'])
        : mapStr(data, ['conversation_id', 'conversationId']);
    final bookingId =
        mapStr(item, ['booking_id', 'bookingId', 'session_id']).isNotEmpty
        ? mapStr(item, ['booking_id', 'bookingId', 'session_id'])
        : mapStr(data, ['booking_id', 'bookingId', 'session_id']);
    final invoiceId = mapStr(item, ['invoice_id', 'invoiceId']).isNotEmpty
        ? mapStr(item, ['invoice_id', 'invoiceId'])
        : mapStr(data, ['invoice_id', 'invoiceId']);
    final actionUrl = mapStr(item, ['action_url', 'url', 'link']).isNotEmpty
        ? mapStr(item, ['action_url', 'url', 'link'])
        : mapStr(data, ['action_url', 'url', 'link']);
    if (conversationId.isNotEmpty) {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TrainerMessagesScreen()));
      return;
    }
    if (bookingId.isNotEmpty) {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TrainerSessionsScreen()));
      return;
    }
    if (invoiceId.isNotEmpty) {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TrainerFinanceScreen()));
      return;
    }
    final category = _category(item);
    if (category == 'bookings') {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TrainerSessionsScreen()));
      return;
    }
    if (category == 'messages') {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TrainerMessagesScreen()));
      return;
    }
    if (category == 'financial') {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TrainerFinanceScreen()));
      return;
    }
    if (actionUrl.isNotEmpty) {
      final uri = Uri.tryParse(actionUrl);
      final path = (uri?.path ?? '').toLowerCase();
      final all = '$path ${(uri?.query ?? '').toLowerCase()}';
      if (all.contains('conversation') || all.contains('chat')) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TrainerMessagesScreen()),
        );
        return;
      }
      if (all.contains('booking') || all.contains('session')) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TrainerSessionsScreen()),
        );
        return;
      }
      if (all.contains('invoice') ||
          all.contains('payment') ||
          all.contains('payout')) {
        if (!mounted) return;
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TrainerFinanceScreen()));
        return;
      }
      if (uri == null) {
        _showError(S.of(context).linkInMeldingIsOngeldig);
        return;
      }
      // Valideer domein en schema vóór openen (voorkomt open-redirect via server-gecontroleerde URLs).
      final opened = await safeLaunchUrl(actionUrl);
      if (!opened) _showError(S.of(context).meldingslinkKanNietWordenGeopendOnbekend2);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'bookings':
        return Icons.event_rounded;
      case 'messages':
        return Icons.chat_bubble_outline_rounded;
      case 'financial':
        return Icons.euro_rounded;
      case 'action':
        return Icons.priority_high_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'bookings':
        return Colors.blue.shade700;
      case 'messages':
        return Colors.teal.shade700;
      case 'financial':
        return Colors.green.shade700;
      case 'action':
        return Colors.red.shade700;
      default:
        return GymiesColors.darkBlue;
    }
  }

  Future<void> _openPreferencesSheet() async {
    Haptics.selection();
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
      _showError(S.of(context).geenWijzigbareVoorkeurveldenGevonden);
      return;
    }

    final draft = <String, dynamic>{...seededPrefs};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: GymiesColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        S.of(context).meldingVoorkeuren,
                        style: GoogleFonts.sora(
                          fontSize: 18,
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
                const SizedBox(height: 16),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          S.of(context).slimmeRemindersT24uT2uCheckinVensterOpenEnGemisteCheckin,
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
                            style: GoogleFonts.sora(fontSize: 14),
                          ),
                          onChanged: (v) {
                            setModalState(() => draft[key] = v);
                          },
                        );
                      }),
                    ],
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
                              _showSuccess(S.of(context).voorkeurenOpgeslagen);
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(S.of(context).opslaan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final title = NotificationDisplayHelper.displayTitle(item);
    final body = NotificationDisplayHelper.displayBody(item);
    final type = _type(item);
    final createdAt = mapStr(item, ['created_at', 'createdAt', 'date']);
    final hasTarget = _hasTarget(item);

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.notifications_rounded,
                      color: GymiesColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.sora(
                        fontSize: 18,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (type.isNotEmpty)
                Text(
                  'Type: $type',
                  style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                ),
              if (createdAt.isNotEmpty)
                Text(
                  'Ontvangen: $createdAt',
                  style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                ),
              const SizedBox(height: 14),
              Text(
                body,
                style: GoogleFonts.sora(fontSize: 14),
              ),
              if (hasTarget) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _openTarget(item);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text(S.of(context).openGerelateerdePagina),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterPill(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        setState(() => _filter = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? GymiesColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? GymiesColors.darkBlue : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: S.of(context).meldingen,
        actions: [
          GestureDetector(
            onTap: _savingPreferences ? null : _openPreferencesSheet,
            child: Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.tune_rounded, size: 18, color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _markAllRead,
            child: Text(
              S.of(context).allesGelezen,
              style: GoogleFonts.sora(
                color: GymiesColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
                      padding: EdgeInsets.zero,
                      children: const [
                        TrainerEmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: S.of(context).noNotifications,
                          subtitle: S.of(context).nieuweUpdatesVerschijnenHier,
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                          ),
                          child: Row(
                              children: [
                                Expanded(
                                  child: _StatTile(
                                    label: S.of(context).actieVereist,
                                    value: '${_countBy('action')}',
                                    color: Colors.red.shade600,
                                    icon: Icons.warning_amber_rounded,
                                  ),
                                ),
                                Expanded(
                                  child: _StatTile(
                                    label: S.of(context).bookings,
                                    value: '${_countBy('bookings')}',
                                    color: GymiesColors.primary,
                                    icon: Icons.calendar_today_rounded,
                                  ),
                                ),
                                Expanded(
                                  child: _StatTile(
                                    label: S.of(context).messages,
                                    value: '${_countBy('messages')}',
                                    color: GymiesColors.darkBlue,
                                    icon: Icons.chat_bubble_outline_rounded,
                                  ),
                                ),
                                Expanded(
                                  child: _StatTile(
                                    label: 'Financieel',
                                    value: '${_countBy('financial')}',
                                    color: Colors.green.shade700,
                                    icon: Icons.account_balance_wallet_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _filterPill(S.of(context).allLabel, 'all'),
                                _filterPill('Actie vereist', 'action'),
                                _filterPill(S.of(context).bookings, 'bookings'),
                                _filterPill(S.of(context).messages, 'messages'),
                                _filterPill('Financieel', 'financial'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (visible.isEmpty)
                          const TrainerEmptyState(
                            icon: Icons.filter_alt_off_outlined,
                            title: S.of(context).geenMeldingenInDitFilter,
                            subtitle: S.of(context).probeerEenAndereCategorie,
                            padding: EdgeInsets.symmetric(vertical: 36),
                          )
                        else
                          ...visible.map((n) {
                            final title = NotificationDisplayHelper.displayTitle(n);
                            final body = NotificationDisplayHelper.displayBody(n);
                            final createdAt = NotificationDisplayHelper.formatDate(n);
                            final unread = _isUnread(n);
                            final cat = _category(n);
                            final catColor = _categoryColor(cat);
                            final catIcon = _categoryIcon(cat);
                            final actionRequired = _requiresAction(n);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: unread
                                    ? GymiesColors.primary.withOpacity(0.06)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: actionRequired
                                      ? Colors.red.shade300
                                      : unread
                                          ? GymiesColors.primary.withOpacity(0.4)
                                          : Colors.grey.shade200,
                                  width: actionRequired ? 1.5 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: GymiesColors.darkBlue.withOpacity(0.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _onNotificationTap(n),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: catColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(catIcon, color: catColor, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: GoogleFonts.sora(
                                                fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              body,
                                              style: GoogleFonts.sora(
                                                fontSize: 13,
                                                color: Colors.grey.shade700,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (createdAt.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                createdAt,
                                                style: GoogleFonts.sora(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (unread)
                                        Container(
                                          width: 10,
                                          height: 10,
                                          margin: const EdgeInsets.only(top: 4),
                                          decoration: const BoxDecoration(
                                            color: GymiesColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
