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
import 'trainer_income_screen.dart';
import 'trainer_messages_screen.dart';
import 'trainer_sessions_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

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
        all.contains('boeking') ||
        all.contains('session') ||
        all.contains('sessie')) {
      return 'bookings';
    }
    if (all.contains('message') ||
        all.contains('bericht') ||
        all.contains('chat')) {
      return 'messages';
    }
    if (all.contains('invoice') ||
        all.contains('factuur') ||
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
    if (normalized == 'reminder_t24h_push') return 'Reminder 24 uur vooraf';
    if (normalized == 'reminder_t2h_push') return 'Reminder 2 uur vooraf';
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
      _showSuccess('Meldingen gemarkeerd als gelezen');
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
      ).push(MaterialPageRoute(builder: (_) => const TrainerIncomeScreen()));
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
      ).push(MaterialPageRoute(builder: (_) => const TrainerIncomeScreen()));
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
        ).push(MaterialPageRoute(builder: (_) => const TrainerIncomeScreen()));
        return;
      }
      if (uri == null) {
        _showError('Link in melding is ongeldig.');
        return;
      }
      // Valideer domein en schema vóór openen (voorkomt open-redirect via server-gecontroleerde URLs).
      final opened = await safeLaunchUrl(actionUrl);
      if (!opened) _showError('Meldingslink kan niet worden geopend (onbekend domein).');
    }
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
      _showError('Geen wijzigbare voorkeurvelden gevonden.');
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

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final title = NotificationDisplayHelper.displayTitle(item);
    final body = NotificationDisplayHelper.displayBody(item);
    final type = _type(item);
    final createdAt = mapStr(item, ['created_at', 'createdAt', 'date']);
    final hasTarget = _hasTarget(item);

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
                if (hasTarget) ...[
                  const SizedBox(height: 14),
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
                      ),
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

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
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
                      padding: EdgeInsets.zero,
                      children: const [
                        TrainerEmptyState(
                          icon: Icons.notifications_none_rounded,
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
                                  child: _StatTile(
                                    label: 'Actie vereist',
                                    value: '${_countBy('action')}',
                                    color: Colors.red.shade600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatTile(
                                    label: 'Boekingen',
                                    value: '${_countBy('bookings')}',
                                    color: GymiesColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatTile(
                                    label: 'Berichten',
                                    value: '${_countBy('messages')}',
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatTile(
                                    label: 'Financieel',
                                    value: '${_countBy('financial')}',
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'all', label: Text('Alles')),
                              ButtonSegment(
                                value: 'action',
                                label: Text('Actie vereist'),
                              ),
                              ButtonSegment(
                                value: 'bookings',
                                label: Text('Boekingen'),
                              ),
                              ButtonSegment(
                                value: 'messages',
                                label: Text('Berichten'),
                              ),
                              ButtonSegment(
                                value: 'financial',
                                label: Text('Financieel'),
                              ),
                            ],
                            selected: {_filter},
                            onSelectionChanged: (v) {
                              setState(() => _filter = v.first);
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (visible.isEmpty)
                          const TrainerEmptyState(
                            icon: Icons.filter_alt_off_outlined,
                            title: 'Geen meldingen in dit filter',
                            subtitle: 'Probeer een andere categorie.',
                            padding: EdgeInsets.symmetric(vertical: 36),
                          )
                        else
                          ...visible.map((n) {
                            final title = NotificationDisplayHelper.displayTitle(n);
                            final body = NotificationDisplayHelper.displayBody(n);
                            final createdAt = NotificationDisplayHelper.formatDate(n);
                            final unread = _isUnread(n);
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: unread
                                      ? GymiesColors.primary.withValues(alpha: 0.5)
                                      : Colors.grey.shade200,
                                ),
                              ),
                              color: unread
                                  ? GymiesColors.primary.withValues(alpha: 0.08)
                                  : Colors.white,
                              child: ListTile(
                                leading: Icon(
                                  unread
                                      ? Icons.notifications_active_outlined
                                      : Icons.notifications_none_outlined,
                                ),
                                title: Text(title),
                                subtitle: Text(
                                  createdAt.isNotEmpty
                                      ? '$body\n$createdAt'
                                      : body,
                                ),
                                isThreeLine: true,
                                trailing: unread
                                    ? const Icon(Icons.brightness_1, size: 10)
                                    : null,
                                onTap: () => _onNotificationTap(n),
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
          Text(value, style: GoogleFonts.fjallaOne(fontSize: 18, color: color)),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
