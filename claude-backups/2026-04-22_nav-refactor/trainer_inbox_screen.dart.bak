import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/trainer_models.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/notification_realtime_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/notification_display_helper.dart';
import '../utils/url_launcher_utils.dart';
import 'trainer_chat_screen.dart';
import 'trainer_income_screen.dart';
import 'trainer_sessions_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Gecombineerd Inbox-scherm: Gesprekken (berichten) + Meldingen (notificaties).
class TrainerInboxScreen extends StatefulWidget {
  const TrainerInboxScreen({super.key, this.onAvatarTap});
  final VoidCallback? onAvatarTap;

  @override
  State<TrainerInboxScreen> createState() => _TrainerInboxScreenState();
}

class _TrainerInboxScreenState extends State<TrainerInboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? _resolveAvatarLabel(BuildContext context) {
    try {
      final auth = Provider.of<dynamic>(context, listen: false);
      final name = auth?.user?['display_name']?.toString() ??
          auth?.user?['name']?.toString() ??
          '';
      return name.isNotEmpty ? name : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Inbox',
        onAvatarTap: widget.onAvatarTap,
        avatarLabel: _resolveAvatarLabel(context),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GymiesColors.primary,
          labelColor: GymiesColors.primary,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Gesprekken'),
            Tab(text: 'Meldingen'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ConversationsTab(tabController: _tabController),
          _NotificationsTab(tabController: _tabController),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 0 – Gesprekken
// ---------------------------------------------------------------------------

class _ConversationsTab extends StatefulWidget {
  const _ConversationsTab({required this.tabController});
  final TabController tabController;

  @override
  State<_ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends State<_ConversationsTab>
    with WidgetsBindingObserver {
  List<TrainerConversation> _conversations = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _unreadOnly = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      _load(background: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startTimer();
      if (mounted) _load(background: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool background = false}) async {
    if (!mounted) return;
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
      final list = await api.getTrainerConversations();
      list.sort((a, b) {
        final ad = DateTime.tryParse(a.lastMessageAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd = DateTime.tryParse(b.lastMessageAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
        if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
        return bd.compareTo(ad);
      });
      if (mounted) {
        setState(() {
          _conversations = list;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Kon berichten niet laden.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _conversations.where((c) {
      if (_unreadOnly && c.unreadCount <= 0) return false;
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      return c.clientName.toLowerCase().contains(q) ||
          (c.lastMessage ?? '').toLowerCase().contains(q);
    }).toList();

    return GymiesListBody(
      loading: _loading,
      error: _error,
      onRefresh: _load,
      child: _conversations.isEmpty
          ? ListView(
              padding: EdgeInsets.zero,
              children: [
                TrainerEmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Geen berichten',
                  subtitle:
                      'Nieuwe chats van klanten verschijnen hier zodra er een bericht binnenkomt.',
                  actionLabel: 'Ververs berichten',
                  onAction: _load,
                  padding: const EdgeInsets.all(32),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Zoek op klant of bericht',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilterChip(
                  selected: _unreadOnly,
                  onSelected: (v) => setState(() => _unreadOnly = v),
                  label: const Text('Alleen ongelezen'),
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  const TrainerEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Geen resultaten',
                    subtitle: 'Pas je zoekterm of filter aan.',
                    padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
                  )
                else
                  ...filtered.map((c) {
                    final lastAt = DateTime.tryParse(c.lastMessageAt ?? '');
                    final lastAtLabel = lastAt == null
                        ? ''
                        : '${lastAt.day.toString().padLeft(2, '0')}-${lastAt.month.toString().padLeft(2, '0')} '
                            '${lastAt.hour.toString().padLeft(2, '0')}:${lastAt.minute.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        elevation: 1,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                GymiesColors.primary.withValues(alpha: 0.3),
                            child: Text(
                              c.clientName.isNotEmpty
                                  ? c.clientName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: GymiesColors.darkBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.clientName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (c.unreadCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: GymiesColors.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${c.unreadCount}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: GymiesColors.darkBlue,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (c.lastMessage != null)
                                Text(
                                  c.lastMessage!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              if (lastAtLabel.isNotEmpty)
                                Text(
                                  lastAtLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context)
                                .push(MaterialPageRoute(
                                  builder: (_) =>
                                      TrainerChatScreen(conversation: c),
                                ))
                                .then((_) => _load());
                          },
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 – Meldingen
// ---------------------------------------------------------------------------

class _NotificationsTab extends StatefulWidget {
  const _NotificationsTab({required this.tabController});
  final TabController tabController;

  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
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
        setState(() => _notifications = [event, ..._notifications]);
      });
    });
    _load();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
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

  bool _isUnread(Map<String, dynamic> item) {
    final unread = mapPick(item, ['unread', 'is_unread']);
    if (unread is bool) return unread;
    if (unread is num) return unread.toInt() == 1;
    return mapStr(item, ['read_at', 'readAt']).isEmpty;
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'on';
  }

  String _type(Map<String, dynamic> item) =>
      mapStr(item, ['type', 'notification_type', 'category']).toLowerCase();

  String _category(Map<String, dynamic> item) {
    final type = _type(item);
    final title = mapStr(item, ['title', 'subject']).toLowerCase();
    final body = mapStr(item, ['body', 'message', 'text']).toLowerCase();
    final all = '$type $title $body';
    if (all.contains('booking') ||
        all.contains('boeking') ||
        all.contains('session') ||
        all.contains('sessie')) { return 'bookings'; }
    if (all.contains('message') ||
        all.contains('bericht') ||
        all.contains('chat')) { return 'messages'; }
    if (all.contains('invoice') ||
        all.contains('factuur') ||
        all.contains('payment') ||
        all.contains('payout') ||
        all.contains('revenue') ||
        all.contains('omzet')) { return 'financial'; }
    if (all.contains('required') ||
        all.contains('pending') ||
        all.contains('urgent') ||
        all.contains('actie')) { return 'action'; }
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: GymiesColors.darkBlue),
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
    final realtime = _realtime();
    try {
      realtime?.markOneRead();
      await context
          .read<GymiesApi>()
          .markNotificationsRead(notificationId: id);
      if (!mounted) return;
      await _load();
    } catch (_) {}
  }

  Future<void> _onNotificationTap(Map<String, dynamic> item) async {
    if (_isUnread(item)) await _markOneRead(item);
    if (!mounted) return;
    final category = _category(item);
    // Als de melding gaat over berichten → wissel naar Gesprekken tab
    if (category == 'messages') {
      widget.tabController.animateTo(0);
      return;
    }
    // Boekingen → open sessies scherm
    if (category == 'bookings') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TrainerSessionsScreen()),
      );
      return;
    }
    // Financieel → open inkomsten scherm
    if (category == 'financial') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TrainerIncomeScreen()),
      );
      return;
    }
    // Action URL
    final data = _mapOf(item, ['data', 'meta', 'payload']) ?? {};
    final actionUrl = mapStr(item, ['action_url', 'url', 'link']).isNotEmpty
        ? mapStr(item, ['action_url', 'url', 'link'])
        : mapStr(data, ['action_url', 'url', 'link']);
    if (actionUrl.isNotEmpty) {
      final uri = Uri.tryParse(actionUrl);
      if (uri != null) {
        // Valideer domein en schema vóór openen (voorkomt open-redirect via server-gecontroleerde URLs).
        final opened = await safeLaunchUrl(actionUrl);
        if (!opened && mounted) _showError('Meldingslink kan niet worden geopend (onbekend domein).');
      } else {
        _showError('Link in melding is ongeldig.');
      }
      return;
    }
    // Geen target → toon detail
    await _openDetail(item);
  }

  Map<String, dynamic>? _mapOf(
      Map<String, dynamic> map, List<String> keys) {
    final v = mapPick(map, keys);
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final title = NotificationDisplayHelper.displayTitle(item);
    final body = NotificationDisplayHelper.displayBody(item);
    final type = _type(item);
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
              ],
            ),
          ),
        ),
      ),
    );
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
    return spaced.isEmpty ? key : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  Future<void> _openPreferencesSheet() async {
    const smartDefaults = <String, bool>{
      'reminder_t24h_push': true,
      'reminder_t2h_push': true,
      'reminder_check_in_window_push': true,
      'reminder_missed_check_in_push': true,
    };
    final seeded = <String, dynamic>{...smartDefaults, ..._preferences};
    final keys = seeded.entries
        .where((e) => e.value is bool || e.value is num || e.value is String)
        .where((e) {
          final k = e.key.toLowerCase();
          return k.contains('push') ||
              k.contains('reminder') ||
              k.contains('email') ||
              k.contains('booking') ||
              k.contains('message') ||
              k.contains('notification') ||
              k.contains('enabled');
        })
        .map((e) => e.key)
        .toList()
      ..sort();

    if (keys.isEmpty) {
      _showError('Geen wijzigbare voorkeurvelden gevonden.');
      return;
    }
    final draft = <String, dynamic>{...seeded};
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
                        ...keys.map((key) {
                          final value = _asBool(draft[key]);
                          return SwitchListTile(
                            value: value,
                            title: Text(_labelFromKey(key)),
                            onChanged: (v) =>
                                setModalState(() => draft[key] = v),
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
                              final nav = Navigator.of(ctx);
                              setState(() => _savingPreferences = true);
                              try {
                                final updated = await context
                                    .read<GymiesApi>()
                                    .updateNotificationPreferences(draft);
                                if (!mounted) return;
                                setState(() {
                                  _preferences =
                                      updated.isEmpty ? draft : updated;
                                });
                                nav.pop();
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
    final visible = _visible();
    return GymiesListBody(
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
                // Stat-kaart
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            label: 'Actie',
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
                // Filter + acties rij
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('Alles')),
                            ButtonSegment(
                                value: 'action', label: Text('Actie')),
                            ButtonSegment(
                                value: 'bookings', label: Text('Boekingen')),
                            ButtonSegment(
                                value: 'messages', label: Text('Berichten')),
                            ButtonSegment(
                                value: 'financial', label: Text('Financieel')),
                          ],
                          selected: {_filter},
                          onSelectionChanged: (v) =>
                              setState(() => _filter = v.first),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Voorkeuren',
                      onPressed: _savingPreferences
                          ? null
                          : _openPreferencesSheet,
                      icon: const Icon(Icons.tune_rounded,
                          color: GymiesColors.primary),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _markAllRead,
                      child: Text(
                        'Alles gelezen',
                        style: GoogleFonts.fjallaOne(
                          color: GymiesColors.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                    final createdAt =
                        NotificationDisplayHelper.formatDate(n);
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
                          createdAt.isNotEmpty ? '$body\n$createdAt' : body,
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
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.fjallaOne(fontSize: 18, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: color, fontSize: 11),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
