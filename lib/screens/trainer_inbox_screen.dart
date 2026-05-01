import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/trainer_models.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/notification_realtime_service.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import '../utils/notification_display_helper.dart';
import '../utils/url_launcher_utils.dart';
import 'trainer_chat_screen.dart';
import 'trainer_newsletter_compose_screen.dart';
import 'trainer_finance_screen.dart';
import 'trainer_sessions_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_segment_tab_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/gymies_upgrade_prompt.dart';
import 'widgets/trainer_state_views.dart';

/// Gecombineerd Inbox-scherm: Gesprekken (berichten) + Meldingen (notificaties).
class TrainerInboxScreen extends StatefulWidget {
  const TrainerInboxScreen({super.key});

  @override
  State<TrainerInboxScreen> createState() => _TrainerInboxScreenState();
}

class _TrainerInboxScreenState extends State<TrainerInboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: 'Inbox',
        actions: [
          GymiesAppBarAction(
            icon: Icons.edit_outlined,
            tooltip: 'Nieuw bericht',
            onTap: () {
              // TODO: open new conversation picker
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: GymiesSegmentTabBar(
          controller: _tabController,
          tabs: const ['Gesprekken', 'Meldingen', 'Nieuwsbrief'],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ConversationsTab(tabController: _tabController),
          _NotificationsTab(tabController: _tabController),
          const _NewsletterTab(),
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

  static const _months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    if (dateOnly == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (dateOnly == today.subtract(const Duration(days: 1))) return 'gisteren';
    if (now.difference(dt).inDays < 7) {
      const days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
      return days[dt.weekday - 1];
    }
    return '${dt.day} ${_months[dt.month - 1]}';
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
                // ── Zoekbalk met ongelezen-filter ──
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue),
                        decoration: InputDecoration(
                          hintText: 'Zoek gesprekken...',
                          hintStyle: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade400),
                          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: GymiesColors.primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        setState(() => _unreadOnly = !_unreadOnly);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _unreadOnly
                              ? GymiesColors.primary.withValues(alpha: 0.12)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _unreadOnly ? GymiesColors.primary : Colors.grey.shade200,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          'Ongelezen',
                          style: GoogleFonts.sora(
                            fontSize: 11,
                            fontWeight: _unreadOnly ? FontWeight.w600 : FontWeight.w400,
                            color: _unreadOnly ? GymiesColors.darkBlue : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ],
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
                    final hasUnread = c.unreadCount > 0;
                    final lastAt = DateTime.tryParse(c.lastMessageAt ?? '');
                    final lastAtLabel = _formatTimestamp(lastAt);
                    final initials = c.clientName.length >= 2
                        ? '${c.clientName[0]}${c.clientName.split(' ').length > 1 ? c.clientName.split(' ').last[0] : c.clientName[1]}'.toUpperCase()
                        : (c.clientName.isNotEmpty ? c.clientName[0].toUpperCase() : '?');
                    return GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context)
                            .push(MaterialPageRoute(
                              builder: (_) => TrainerChatScreen(conversation: c),
                            ))
                            .then((_) => _load());
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              // ── 3px accent: gold=unread, gray=read ──
                              Container(
                                width: 3,
                                decoration: BoxDecoration(
                                  color: hasUnread ? GymiesColors.primary : Colors.grey.shade300,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(3),
                                    bottomLeft: Radius.circular(3),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                      color: hasUnread
                                          ? GymiesColors.primary.withValues(alpha: 0.3)
                                          : Colors.grey.shade200,
                                      width: 0.5,
                                    ),
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(10),
                                      bottomRight: Radius.circular(10),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // ── Circle avatar ──
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: GymiesColors.darkBlue,
                                          shape: BoxShape.circle,
                                          border: hasUnread
                                              ? Border.all(color: GymiesColors.primary, width: 2)
                                              : null,
                                        ),
                                        child: Center(
                                          child: Text(
                                            initials,
                                            style: GoogleFonts.sora(
                                              fontWeight: FontWeight.w600,
                                              color: GymiesColors.primary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    c.clientName,
                                                    style: GoogleFonts.sora(
                                                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                                                      fontSize: 13,
                                                      color: GymiesColors.darkBlue,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (lastAtLabel.isNotEmpty)
                                                  Text(
                                                    lastAtLabel,
                                                    style: GoogleFonts.sora(
                                                      fontSize: 10,
                                                      color: Colors.grey.shade500,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            if (c.lastMessage != null)
                                              Text(
                                                c.lastMessage!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.sora(
                                                  fontSize: 11,
                                                  fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                                                  color: hasUnread ? Colors.grey.shade700 : Colors.grey.shade500,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (hasUnread)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: GymiesColors.primary,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${c.unreadCount}',
                                            style: GoogleFonts.sora(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: GymiesColors.darkBlue,
                                            ),
                                          ),
                                        )
                                      else
                                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300, size: 18),
                                    ],
                                  ),
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
    Haptics.light();
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
    Haptics.selection();
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
        MaterialPageRoute(builder: (_) => const TrainerFinanceScreen()),
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
    Haptics.selection();
    final title = NotificationDisplayHelper.displayTitle(item);
    final body = NotificationDisplayHelper.displayBody(item);
    final type = _type(item);
    final createdAt = mapStr(item, ['created_at', 'createdAt', 'date']);

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
                      color: GymiesColors.primary.withValues(alpha: 0.15),
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
            ],
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
    Haptics.selection();
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
                        color: GymiesColors.primary.withValues(alpha: 0.15),
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
                        'Melding voorkeuren',
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
                      ...keys.map((key) {
                        final value = _asBool(draft[key]);
                        return SwitchListTile(
                          value: value,
                          title: Text(
                            _labelFromKey(key),
                            style: GoogleFonts.sora(fontSize: 14),
                          ),
                          onChanged: (v) =>
                              setModalState(() => draft[key] = v),
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
                            Haptics.light();
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
    );
  }

  Widget _stripeStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.sora(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: color.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notifFilterChip(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? GymiesColors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? GymiesColors.primary.withValues(alpha: 0.3)
                : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? GymiesColors.primary : Colors.grey.shade600,
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
                // ── Stripe-style stat cards ──
                Row(
                  children: [
                    _stripeStatCard('Actie', '${_countBy('action')}', Colors.red.shade600),
                    const SizedBox(width: 6),
                    _stripeStatCard('Boekingen', '${_countBy('bookings')}', GymiesColors.primary),
                    const SizedBox(width: 6),
                    _stripeStatCard('Berichten', '${_countBy('messages')}', GymiesColors.darkBlue),
                    const SizedBox(width: 6),
                    _stripeStatCard('Financieel', '${_countBy('financial')}', Colors.green.shade700),
                  ],
                ),
                const SizedBox(height: 10),
                // ── Filter chips + acties ──
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _notifFilterChip('Alles', 'all'),
                            const SizedBox(width: 4),
                            _notifFilterChip('Actie', 'action'),
                            const SizedBox(width: 4),
                            _notifFilterChip('Boekingen', 'bookings'),
                            const SizedBox(width: 4),
                            _notifFilterChip('Berichten', 'messages'),
                            const SizedBox(width: 4),
                            _notifFilterChip('Financieel', 'financial'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _savingPreferences ? null : _openPreferencesSheet,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200, width: 0.5),
                        ),
                        child: Icon(Icons.tune_rounded, color: GymiesColors.darkBlue, size: 16),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _busy ? null : _markAllRead,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: GymiesColors.darkBlue.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Gelezen',
                          style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
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
                    final accentColor = unread ? GymiesColors.primary : Colors.grey.shade300;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => _onNotificationTap(n),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 0),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: unread
                                        ? GymiesColors.primary.withValues(alpha: 0.04)
                                        : Colors.white,
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(10),
                                      bottomRight: Radius.circular(10),
                                    ),
                                    border: Border.all(color: Colors.grey.shade200, width: 0.5),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: (unread ? GymiesColors.primary : GymiesColors.darkBlue).withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          unread ? Icons.notifications_active_outlined : Icons.notifications_none_outlined,
                                          size: 16,
                                          color: unread ? GymiesColors.darkBlue : Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    title,
                                                    style: GoogleFonts.sora(
                                                      fontSize: 12.5,
                                                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                                                      color: GymiesColors.darkBlue,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (createdAt.isNotEmpty)
                                                  Text(
                                                    createdAt,
                                                    style: GoogleFonts.sora(fontSize: 10, color: Colors.grey.shade500),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              body,
                                              style: GoogleFonts.sora(
                                                fontSize: 11.5,
                                                fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                                                color: Colors.grey.shade700,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (_requiresAction(n)) ...[
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: GymiesColors.primary.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'Actie vereist →',
                                                  style: GoogleFonts.sora(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: GymiesColors.darkBlue,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (unread)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(top: 4, left: 6),
                                          decoration: const BoxDecoration(
                                            color: GymiesColors.primary,
                                            shape: BoxShape.circle,
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
                    );
                  }),
              ],
            ),
    );
  }
}


// ---------------------------------------------------------------------------
// Tab 2 – Nieuwsbrief (Pro+ feature)
// ---------------------------------------------------------------------------

class _NewsletterTab extends StatefulWidget {
  const _NewsletterTab();

  @override
  State<_NewsletterTab> createState() => _NewsletterTabState();
}

class _NewsletterTabState extends State<_NewsletterTab> {
  List<Map<String, dynamic>> _newsletters = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<GymiesApi>();
      final list = await api.getNewsletters();
      if (mounted) {
        setState(() {
          _newsletters = List<Map<String, dynamic>>.from(list);
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('[Newsletter] Laden fout: $e');
      if (mounted) setState(() { _error = 'Kon nieuwsbrieven niet laden.'; _loading = false; });
    }
  }

  Future<void> _compose() async {
    Haptics.selection();
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const TrainerNewsletterComposeScreen(),
      ),
    );
    if (sent == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ent = Provider.of<SubscriptionEntitlementsService>(context);
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    if (!isProPlus) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Feature preview cards
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200, width: 0.5),
            ),
            child: Column(
              children: [
                Icon(Icons.newspaper_rounded, size: 40, color: Colors.grey.shade300),
                const SizedBox(height: 10),
                Text(
                  'Nieuwsbrief',
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bereik al je klanten met één druk op de knop. Deel tips, aanbiedingen en updates.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FeatureChip(icon: Icons.send_rounded, label: 'Bulk versturen'),
                    const SizedBox(width: 8),
                    _FeatureChip(icon: Icons.analytics_outlined, label: 'Open rate'),
                    const SizedBox(width: 8),
                    _FeatureChip(icon: Icons.history_rounded, label: 'Archief'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const GymiesUpgradePrompt(
            icon: Icons.newspaper_rounded,
            feature: 'Nieuwsbrief',
            tier: 'Pro+',
            description:
                'Stuur nieuwsbrieven naar al je klanten tegelijk. Houd ze '
                'op de hoogte van nieuwe lessen, aanbiedingen en tips.',
          ),
        ],
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw proberen'),
            ),
          ],
        ),
      );
    }

    if (_newsletters.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          TrainerEmptyState(
            icon: Icons.newspaper_rounded,
            title: 'Nog geen nieuwsbrieven',
            subtitle:
                'Stuur je eerste nieuwsbrief naar al je klanten. Deel tips, aanbiedingen of updates.',
            actionLabel: 'Nieuwsbrief schrijven',
            actionIcon: Icons.edit_rounded,
            onAction: _compose,
            padding: const EdgeInsets.all(32),
          ),
        ],
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: _newsletters.length,
            itemBuilder: (_, i) {
              final nl = _newsletters[i];
              final subject = (nl['subject'] ?? nl['title'] ?? 'Nieuwsbrief').toString();
              final sentAt = nl['sent_at'] ?? nl['created_at'] ?? '';
              final recipientCount = nl['recipient_count'] ?? nl['recipients'] ?? '?';
              final openRateRaw = nl['open_rate'];
              final openRate = openRateRaw is num
                  ? openRateRaw.toDouble()
                  : double.tryParse(openRateRaw?.toString() ?? '');

              DateTime? sentDate;
              if (sentAt.toString().isNotEmpty) {
                sentDate = DateTime.tryParse(sentAt.toString());
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                            border: Border.all(color: Colors.grey.shade200, width: 0.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: GymiesColors.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.email_rounded, color: GymiesColors.darkBlue, size: 17),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            subject,
                                            style: GoogleFonts.sora(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12.5,
                                              color: GymiesColors.darkBlue,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 16),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$recipientCount ontvangers'
                                      '${sentDate != null ? ' · ${sentDate.day}/${sentDate.month}/${sentDate.year}' : ''}'
                                      '${openRate != null ? ' · ${(openRate * 100).toStringAsFixed(0)}% geopend' : ''}',
                                      style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600),
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
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'fab_newsletter',
            onPressed: _compose,
            backgroundColor: GymiesColors.darkBlue,
            tooltip: 'Nieuwe nieuwsbrief',
            child: const Icon(Icons.edit_rounded, color: GymiesColors.primary, size: 20),
          ),
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: GymiesColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: GymiesColors.darkBlue),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w500, color: GymiesColors.darkBlue),
          ),
        ],
      ),
    );
  }
}
