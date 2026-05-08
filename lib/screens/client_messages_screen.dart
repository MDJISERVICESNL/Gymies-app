

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../l10n/generated/app_localizations.dart';
import '../config/timing_constants.dart';
import '../config/ui_constants.dart';
import '../models/booking.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../services/gymies_api.dart';
import '../services/pusher_websocket_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'dart:async';
import 'dart:convert';
import 'widgets/gymies_app_bar.dart';
import 'widgets/reschedule_card_widget.dart';
import 'widgets/reschedule_slot_picker.dart';
import 'widgets/trainer_state_views.dart';
class ClientMessagesScreen extends StatefulWidget {
  const ClientMessagesScreen({super.key});

  @override
  State<ClientMessagesScreen> createState() => _ClientMessagesScreenState();
}

class _ClientMessagesScreenState extends State<ClientMessagesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _conversations = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _searchQuery) setState(() => _searchQuery = q);
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredConversations {
    if (_searchQuery.isEmpty) return _conversations;
    return _conversations.where((c) {
      final name = _conversationDisplayName(c).toLowerCase();
      final lastMsg = mapStr(c, ['last_message', 'lastMessage', 'preview', 'body']).toLowerCase();
      return name.contains(_searchQuery) || lastMsg.contains(_searchQuery);
    }).toList();
  }

  Future<void> _load() async {
    final api = context.read<GymiesApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.getClientConversations();
      final normalized = list.where((c) => !_isSupportConversation(c)).toList()
        ..sort((a, b) {
          final aUnread = mapInt(a, ['unread_count', 'unreadCount']);
          final bUnread = mapInt(b, ['unread_count', 'unreadCount']);
          if (aUnread != bUnread) return bUnread.compareTo(aUnread);
          final aLast = mapStr(a, [
            'last_message_at',
            'updated_at',
            'created_at',
          ]);
          final bLast = mapStr(b, [
            'last_message_at',
            'updated_at',
            'created_at',
          ]);
          return bLast.compareTo(aLast);
        });
      if (!mounted) return;
      setState(() {
        _conversations = normalized;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ClientMessages] Gesprekken laden fout: $e');
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': 'ClientMessages', 'action': 'loadConversations'}));
      if (!mounted) return;
      setState(() {
        _error = S.of(context).konGesprekkenNietLaden;
        _loading = false;
      });
    }
  }

  bool _isSupportConversation(Map<String, dynamic> c) {
    final type = mapStr(c, [
      'type',
      'conversation_type',
      'conversationType',
    ]).toLowerCase();
    if (type.contains('support')) return true;
    final isSupportFlag = mapPick(c, ['is_support', 'isSupport']);
    if (isSupportFlag == true || isSupportFlag?.toString() == '1') return true;
    final name = mapStr(c, [S.of(context).trainername, S.of(context).trainername2, 'name']).toLowerCase();
    return name.contains('gymies') || name.contains('support');
  }

  String _conversationDisplayName(Map<String, dynamic> c) {
    final regular = mapStr(c, [S.of(context).trainername, S.of(context).trainername2, 'name']);
    return regular.isEmpty ? S.of(context).trainer : regular;
  }

  /// Formatteer timestamp naar leesbaar label (vandaag → tijd, gisteren, of datum).
  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
    if (dateOnly == today) {
      return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    }
    if (dateOnly == today.subtract(const Duration(days: 1))) {
      return S.of(context).gisterenLower;
    }
    const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    return '${parsed.day} ${months[parsed.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          // ── Header ──────────────────────────────
          Container(
            color: GymiesColors.darkBlue,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          S.of(context).inbox,
                          style: GoogleFonts.sora(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        if (_conversations.any((c) => mapInt(c, ['unread_count', 'unreadCount']) > 0))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: GymiesColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_conversations.where((c) => mapInt(c, ['unread_count', 'unreadCount']) > 0).length} nieuw',
                              style: GoogleFonts.sora(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Zoekbalk
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.5),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: GoogleFonts.sora(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: S.of(context).zoekGesprekken,
                          hintStyle: GoogleFonts.sora(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: Colors.white.withOpacity(0.5),
                            size: 20,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          filled: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Content ──────────────────────────────
          Expanded(
            child: GymiesListBody(
              loading: _loading,
              error: _error,
              onRefresh: _load,
              child: _conversations.isEmpty
                  ? ListView(
                      children: const [
                        _EmptyView(
                          title: S.of(context).nogGeenGesprekken,
                          subtitle:
                              S.of(context).zodraJeEenTrainerBerichtVerschijnt,
                        ),
                      ],
                    )
                  : _filteredConversations.isEmpty
                      ? ListView(
                          children: [
                            _EmptyView(
                              title: S.of(context).noResults,
                              subtitle:
                                  'Geen gesprekken gevonden voor "${_searchController.text}".',
                            ),
                          ],
                        )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: _filteredConversations.length,
                      itemBuilder: (_, i) {
                        final c = _filteredConversations[i];
                        final id = mapStr(c, [
                          'id',
                          'conversation_id',
                          'conversationId',
                        ]);
                        final trainerName = _conversationDisplayName(c);
                        final unread = mapInt(c, ['unread_count', 'unreadCount']);
                        final lastMessage = mapStr(c, [
                          'last_message',
                          'lastMessage',
                          'preview',
                          'body',
                        ]);
                        final lastAt = mapStr(c, [
                          'last_message_at',
                          'updated_at',
                        ]);
                        final timeLabel = _formatTimestamp(lastAt);
                        final hasUnread = unread > 0;
                        final avatarUrl = mapStr(c, ['avatar_url', 'avatarUrl', S.of(context).traineravatar, S.of(context).traineravatar2]);

                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: UiConstants.animChatBaseMs + (i.clamp(0, UiConstants.animChatMaxItems) * UiConstants.animChatStepMs)),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value.clamp(0.0, 1.0),
                              child: Transform.translate(
                                offset: Offset(0, 16 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Dismissible(
                              key: Key(id.isNotEmpty ? id : 'conv_$i'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (direction) async {
                                if (id.isNotEmpty) {
                                  try {
                                    await context.read<GymiesApi>().deleteClientConversation(id);
                                    return true;
                                  } catch (e) {
                                    if (kDebugMode) debugPrint('[ClientMessages] Gesprek verwijderen API fout: $e');
                                    if (mounted) {
                                      // ignore: use_build_context_synchronously
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text(S.of(context).konGesprekNietVerwijderen),
                                          backgroundColor: Colors.red.shade600,
                                        ),
                                      );
                                    }
                                    return false;
                                  }
                                }
                                return true;
                              },
                              onDismissed: (direction) {
                                if (mounted) {
                                  setState(() {
                                    _conversations.removeWhere((conv) =>
                                      mapStr(conv, ['id', 'conversation_id']) == id);
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(S.of(context).gesprekVerwijderd),
                                      backgroundColor: GymiesColors.darkBlue,
                                      action: SnackBarAction(
                                        label: S.of(context).herstellen,
                                        textColor: GymiesColors.primary,
                                        onPressed: () => _load(),
                                      ),
                                    ),
                                  );
                                }
                              },
                              background: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(
                                  Icons.delete_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              child: GestureDetector(
                                onTap: id.isEmpty
                                    ? null
                                    : () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ClientChatScreen(
                                              conversationId: id,
                                              title: trainerName,
                                            ),
                                          ),
                                        );
                                        if (mounted) await _load();
                                      },
                                child: IntrinsicHeight(
                                  child: Row(
                                    children: [
                                      // ── Stripe accent ──
                                      Container(
                                        width: 3,
                                        decoration: BoxDecoration(
                                          color: hasUnread ? GymiesColors.primary : Colors.grey.shade300,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      // ── Card body ──
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: hasUnread
                                                ? GymiesColors.primary.withOpacity(0.04)
                                                : Colors.white,
                                            borderRadius: const BorderRadius.only(
                                              topRight: Radius.circular(10),
                                              bottomRight: Radius.circular(10),
                                            ),
                                            border: Border.all(color: Colors.grey.shade200, width: 0.5),
                                          ),
                                          child: Row(
                                            children: [
                                              // ── Circle avatar with 2 initials ──
                                              () {
                                                final parts = trainerName.trim().split(RegExp(r'\s+'));
                                                final initials = parts.length >= 2
                                                    ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
                                                    : (trainerName.isNotEmpty ? trainerName[0].toUpperCase() : 'T');
                                                return Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: GymiesColors.darkBlue,
                                                    border: hasUnread
                                                        ? Border.all(color: GymiesColors.primary, width: 2)
                                                        : null,
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: avatarUrl.isNotEmpty
                                                      ? Image.network(
                                                          avatarUrl,
                                                          width: 40,
                                                          height: 40,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, _, _) => Center(
                                                            child: Text(
                                                              initials,
                                                              style: GoogleFonts.sora(
                                                                fontSize: 14,
                                                                fontWeight: FontWeight.w700,
                                                                color: GymiesColors.primary,
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      : Center(
                                                          child: Text(
                                                            initials,
                                                            style: GoogleFonts.sora(
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.w700,
                                                              color: GymiesColors.primary,
                                                            ),
                                                          ),
                                                        ),
                                                );
                                              }(),
                                              const SizedBox(width: 10),
                                              // ── Name + preview ──
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            trainerName,
                                                            style: GoogleFonts.sora(
                                                              fontSize: 13,
                                                              fontWeight: hasUnread
                                                                  ? FontWeight.w700
                                                                  : FontWeight.w500,
                                                              color: GymiesColors.darkBlue,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        Text(
                                                          timeLabel,
                                                          style: GoogleFonts.sora(
                                                            fontSize: 10,
                                                            color: Colors.grey.shade500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      lastMessage.isEmpty
                                                          ? 'Open gesprek'
                                                          : lastMessage.startsWith('__GYMIES_CARD__:')
                                                              ? S.of(context).verplaatsingsverzoek
                                                              : lastMessage,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: GoogleFonts.sora(
                                                        fontSize: 11.5,
                                                        fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                                                        color: hasUnread
                                                            ? Colors.grey.shade700
                                                            : Colors.grey.shade500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              // ── Unread badge or chevron ──
                                              if (hasUnread)
                                                Container(
                                                  constraints: const BoxConstraints(minWidth: 20),
                                                  height: 20,
                                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                                  decoration: BoxDecoration(
                                                    color: GymiesColors.primary,
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      '$unread',
                                                      style: GoogleFonts.sora(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: GymiesColors.darkBlue,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 16,
                                                  color: Colors.grey.shade400,
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
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class ClientChatScreen extends StatefulWidget {
  const ClientChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

  @override
  State<ClientChatScreen> createState() => _ClientChatScreenState();
}

class _ClientChatScreenState extends State<ClientChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  final Set<String> _rescheduleBusyIds = {};

  // ── Pusher WebSocket (nieuw) ──────────────────────────────────
  PusherWebSocketService? _pusher;
  StreamSubscription<PusherEvent>? _pusherEventSub;
  Timer? _pollTimer; // Stille fallback, alleen als Pusher faalt
  String _myChannel = ''; // private-gymies.chat.{myUserId}

  // ── Typing indicator state ────────────────────────────────────
  bool _trainerIsTyping = false;
  Timer? _typingResetTimer;
  Timer? _typingThrottleTimer;

  // ── Read receipts ─────────────────────────────────────────────
  String? _lastReadAt; // Wanneer de trainer onze berichten heeft gelezen

  /// Cached user ID — bewaard bij initState zodat het altijd beschikbaar is,
  /// ook als AuthService.user later null wordt (bijv. achtergrond-lifecycle).
  String _myUserId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cache de user ID direct bij openen — vóórdat lifecycle events het wissen
    _cacheMyUserId();
    _load();
  }

  void _cacheMyUserId() {
    try {
      final user = context.read<AuthService>().user;
      if (user != null) {
        _myUserId = mapStr(user, ['id', 'user_id', 'userId']);
        _myChannel = 'private-gymies.chat.$_myUserId';
        if (kDebugMode) debugPrint('[Chat] Cached myUserId: $_myUserId, channel: $_myChannel');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Chat] Failed to cache user ID: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      // Bij terugkeer: check of Pusher nog connected is
      if (_pusher == null || !_pusher!.isConnected) {
        _startPollingFallback();
      }
      if (mounted) _refreshMessagesSilently();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _typingResetTimer?.cancel();
    _typingThrottleTimer?.cancel();
    _pusherEventSub?.cancel();
    _pusher?.disconnect();
    _pusher?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final messages = await api.getClientConversationMessages(
        widget.conversationId,
      );
      await api.markClientConversationAsRead(widget.conversationId);
      if (!mounted) return;
      messages.sort(
        (a, b) => (DateTime.tryParse(mapStr(a, ['created_at', 'createdAt'])) ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(DateTime.tryParse(mapStr(b, ['created_at', 'createdAt'])) ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _startRealtime();
      _jumpToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': 'ClientMessages', 'action': 'loadMessages'}));
      if (!mounted) return;
      setState(() {
        _error = S.of(context).konChatNietLaden;
        _loading = false;
      });
    }
  }

  String _messageKey(Map<String, dynamic> message) {
    final id = mapStr(message, ['id', 'message_id', 'messageId']);
    if (id.isNotEmpty) return 'id:$id';
    final body = mapStr(message, ['body', 'message', 'text']);
    final createdAt = mapStr(message, ['created_at', 'createdAt']);
    final sender = mapStr(message, ['sender_id', 'senderId', 'role']);
    return 'fallback:$sender:$createdAt:$body';
  }

  void _mergeMessages(List<Map<String, dynamic>> incoming) {
    // Verwijder pending berichten die nu van de server komen
    // (body + from_user_id match = zelfde bericht)
    final pendingBodies = <String>{};
    for (final m in _messages) {
      final status = (m['_delivery_status'] ?? '').toString();
      if (status == 'pending' || status == 'sent') {
        final id = mapStr(m, ['id', 'message_id']);
        if (id.startsWith('pending_')) {
          pendingBodies.add(mapStr(m, ['body', 'message', 'text']).trim());
        }
      }
    }

    // Als een incoming bericht hetzelfde body heeft als een pending, verwijder de pending
    for (final inc in incoming) {
      final incBody = mapStr(inc, ['body', 'message', 'text']).trim();
      final incSender = mapStr(inc, ['from_user_id', 'fromUserId', 'sender_id']);
      if (incBody.isNotEmpty && pendingBodies.contains(incBody) && incSender == _myUserId) {
        _messages.removeWhere((m) {
          final mId = mapStr(m, ['id', 'message_id']);
          return mId.startsWith('pending_') && mapStr(m, ['body', 'message', 'text']).trim() == incBody;
        });
        pendingBodies.remove(incBody);
      }
    }

    final combined = [..._messages, ...incoming];
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final m in combined) {
      final key = _messageKey(m);
      if (seen.contains(key)) continue;
      seen.add(key);
      unique.add(m);
    }
    unique.sort((a, b) {
      final da = DateTime.tryParse(mapStr(a, ['created_at', 'createdAt'])) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(mapStr(b, ['created_at', 'createdAt'])) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return da.compareTo(db);
    });
    _messages = unique;
  }

  Future<void> _refreshMessagesSilently() async {
    try {
      final list = await context
          .read<GymiesApi>()
          .getClientConversationMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _mergeMessages(list);
      });
      _jumpToBottom();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ClientMessages] Silent message refresh fout: $e');
      Sentry.addBreadcrumb(Breadcrumb(message: 'ClientMessages silent refresh failed: $e', category: 'chat'));
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': 'ClientMessages', 'action': 'refreshSilently'}));
    }
  }

  // ══════════════════════════════════════════════════════════════
  // REALTIME: Pusher WebSocket + polling fallback
  // ══════════════════════════════════════════════════════════════

  void _startRealtime() {
    _connectPusher();
    // Polling als stille fallback — langzamer interval als Pusher werkt
    _startPollingFallback();
  }

  void _startPollingFallback() {
    _pollTimer?.cancel();
    // Als Pusher verbonden is: poll elke 30s (alleen als sanity check)
    // Als Pusher NIET verbonden: poll elke 4s (actieve fallback)
    final interval = (_pusher?.isConnected ?? false)
        ? const Duration(seconds: 30)
        : TimingConstants.messagePollInterval;
    _pollTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      if (_loading || _sending) return;
      _refreshMessagesSilently();
    });
  }

  Future<void> _connectPusher() async {
    if (_myUserId.isEmpty || _myChannel.isEmpty) return;

    final api = context.read<GymiesApi>();

    // 1. Haal broadcasting config op van backend
    Map<String, dynamic> config;
    try {
      config = await api.getBroadcastConfig();
      if (config['enabled'] != true) {
        if (kDebugMode) debugPrint(S.of(context).chatBroadcastingNietEnabledOpBackend);
        return;
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Chat] Broadcasting config ophalen mislukt: $e — alleen polling');
      Sentry.addBreadcrumb(Breadcrumb(message: 'Broadcast config fetch failed: $e', category: 'websocket', level: SentryLevel.warning));
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': 'ClientMessages', 'action': 'fetchBroadcastConfig'}));
      return;
    }

    final appKey = (config['key'] ?? '').toString();
    final host = (config['host'] ?? '').toString();
    final port = (config['port'] is num) ? (config['port'] as num).toInt() : 443;
    final scheme = (config['scheme'] ?? 'wss').toString();

    if (appKey.isEmpty || host.isEmpty) {
      if (kDebugMode) debugPrint('[Chat] Broadcasting config onvolledig: key=$appKey host=$host');
      return;
    }

    // 2. Maak Pusher service met auth callback
    _pusher = PusherWebSocketService(
      authCallback: (socketId, channelName) async {
        return api.authenticateBroadcastChannel(socketId, channelName);
      },
    );

    // 3. Luister naar connection state changes → update polling interval
    _pusher!.addListener(() {
      if (!mounted) return;
      setState(() {});
      // Pas polling interval aan op basis van Pusher state
      if (_pusher!.isConnected) {
        _startPollingFallback(); // Langzamere polling
      } else if (_pusher!.state == PusherConnectionState.disconnected) {
        _startPollingFallback(); // Snellere polling als fallback
      }
    });

    // 4. Luister naar Pusher events
    _pusherEventSub = _pusher!.events.listen(_handlePusherEvent);

    // 5. Verbind en subscribe
    try {
      await _pusher!.connect(
        appKey: appKey,
        host: host,
        port: port,
        scheme: scheme,
      );
      await _pusher!.subscribe(_myChannel);
      if (kDebugMode) debugPrint('[Chat] Pusher gestart — subscribed op $_myChannel');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Chat] Pusher verbinding fout: $e');
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': 'ClientMessages', 'action': 'pusherConnect'}));
    }
  }

  /// Verwerkt binnenkomende Pusher events op ons private channel.
  void _handlePusherEvent(PusherEvent event) {
    if (!mounted) return;

    if (kDebugMode) debugPrint('[Chat] Pusher event: ${event.event} on ${event.channel}');

    switch (event.event) {
      case 'message.sent':
        _handleIncomingMessage(event.data);
        break;

      case 'messages.read':
        _handleMessagesRead(event.data);
        break;

      case 'user.typing':
        _handleTrainerTyping(event.data);
        break;

      default:
        if (kDebugMode) debugPrint('[Chat] Onbekend event: ${event.event}');
        break;
    }
  }

  /// Nieuw bericht via Pusher — check of het voor deze conversatie is.
  void _handleIncomingMessage(Map<String, dynamic> data) {
    final convId = (data['conversation_id'] ?? '').toString();
    if (convId != widget.conversationId) return;

    // Het bericht bevat: message_id, from_user_id, body_preview, created_at
    final messageId = (data['message_id'] ?? '').toString();
    final fromUserId = (data['from_user_id'] ?? '').toString();

    // Skip als het ons eigen bericht is (dat is al via optimistic UI getoond)
    if (fromUserId == _myUserId) return;

    // Maak message object voor de chat
    final message = <String, dynamic>{
      'id': messageId,
      'body': data['body_preview'] ?? '',
      'from_user_id': fromUserId,
      'sender_type': data['sender_type'] ?? S.of(context).trainer2,
      'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
    };

    setState(() {
      _mergeMessages([message]);
      // Trainer is gestopt met typen zodra er een bericht komt
      _trainerIsTyping = false;
      _typingResetTimer?.cancel();
    });
    _jumpToBottom();

    // Markeer als gelezen (we hebben het chatscherm open)
    context.read<GymiesApi>().markClientConversationAsRead(widget.conversationId);
  }

  /// Trainer heeft onze berichten gelezen.
  void _handleMessagesRead(Map<String, dynamic> data) {
    final convId = (data['conversation_id'] ?? '').toString();
    if (convId != widget.conversationId) return;

    setState(() {
      _lastReadAt = (data['read_at'] ?? '').toString();
    });
  }

  /// Trainer is aan het typen.
  void _handleTrainerTyping(Map<String, dynamic> data) {
    final convId = (data['conversation_id'] ?? '').toString();
    if (convId != widget.conversationId) return;

    // Niet onze eigen typing events tonen
    final typingUserId = (data['typing_user_id'] ?? '').toString();
    if (typingUserId == _myUserId) return;

    setState(() => _trainerIsTyping = true);

    // Auto-reset na 4 seconden (voor als het stop-typing event mist)
    _typingResetTimer?.cancel();
    _typingResetTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _trainerIsTyping = false);
    });
  }

  /// Stuur typing indicator naar de trainer (throttled).
  void _sendTypingEvent() {
    if (_pusher == null || !_pusher!.isConnected) return;
    if (_myChannel.isEmpty) return;

    // Throttle: max 1x per 2 seconden
    if (_typingThrottleTimer?.isActive ?? false) return;
    _typingThrottleTimer = Timer(const Duration(seconds: 2), () {});

    _pusher!.triggerClientEvent(_myChannel, 'client-typing', {
      'conversation_id': widget.conversationId,
      'typing_user_id': _myUserId,
    });
  }

  bool _isMine(Map<String, dynamic> message) {
    // 1. Directe boolean vlaggen (optimistic UI zet is_mine)
    final direct = mapPick(message, ['is_mine', 'isMine', 'from_me']);
    if (direct is bool) return direct;
    if (direct is num) return direct.toInt() == 1;
    // String "true"/"false" (sommige backends)
    if (direct is String) {
      if (direct.toLowerCase() == 'true' || direct == '1') return true;
      if (direct.toLowerCase() == 'false' || direct == '0') return false;
    }

    // 2. Vergelijk sender ID — backend stuurt `from_user_id`
    // Gebruik gecachede ID als primaire bron (robuust tegen lifecycle issues)
    var myId = _myUserId;
    if (myId.isEmpty) {
      // Fallback: probeer live op te halen
      try {
        myId = mapStr(
          context.read<AuthService>().user ?? {},
          ['id', 'user_id', 'userId'],
        );
        if (myId.isNotEmpty) _myUserId = myId; // Cache voor volgende keer
      } catch (e) {
        // Fail-open: Fetch user ID optional, continue with empty value
        if (kDebugMode) debugPrint('[ClientMessages] Fetch user ID failed: $e');
      }
    }

    if (myId.isNotEmpty) {
      final senderId = mapStr(message, [
        'from_user_id',   // ← backend veldnaam
        'fromUserId',
        'sender_id',
        'senderId',
      ]);
      if (senderId.isNotEmpty) return senderId == myId;
    }

    // 3. Fallback: check sender_type / sender_role
    final senderType = mapStr(message, ['sender_type', 'senderType', 'sender_role', 'role']).toLowerCase();
    if (senderType == 'client' || senderType == 'user' || senderType == S.of(context).klant) return true;
    if (senderType == S.of(context).trainer2) return false;

    // 4. Laatste fallback: notification-type berichten zijn nooit van de klant
    final msgType = mapStr(message, ['type']).toLowerCase();
    if (msgType == 'notification' || msgType == 'system') return false;

    return false;
  }

  /// Bericht verzenden met optimistic UI:
  /// 1. Bericht direct tonen als "pending" (⏳)
  /// 2. Bij succes: updaten naar "sent" (✓)
  /// 3. Bij fout: markeren als "failed" (✗) met retry knop
  Future<void> _send([String? quickReplyText]) async {
    final text = (quickReplyText ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;

    // Maak optimistic bericht met tijdelijke ID
    final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    final pendingMessage = <String, dynamic>{
      'id': tempId,
      'body': text,
      'is_mine': true,
      'from_user_id': _myUserId, // Zodat _isMine() werkt na merge
      'created_at': DateTime.now().toIso8601String(),
      '_delivery_status': 'pending', // ⏳
    };

    setState(() {
      _sending = true;
      _messages.add(pendingMessage);
    });
    if (quickReplyText == null) _controller.clear();
    _jumpToBottom();
    Haptics.light();

    try {
      final created = await context.read<GymiesApi>().sendClientMessage(
        widget.conversationId,
        text,
      );
      if (!mounted) return;

      // Vervang pending bericht met server response.
      // Backend geeft vaak alleen {id: "123"} terug — behoud onze lokale data.
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx >= 0) {
          // BELANGRIJK: spread-volgorde: onze lokale data eerst, dan server data
          // (server overschrijft alleen 'id'), daarna onze expliciet gezette velden.
          final merged = <String, dynamic>{
            ..._messages[idx],       // behoud body, created_at, is_mine, from_user_id
            ...created,              // server overschrijft 'id' met echte ID
            'is_mine': true,         // altijd: wij stuurden dit
            'from_user_id': _myUserId, // altijd: voor herkenning na reload
            '_delivery_status': 'sent', // ✓
          };
          _messages[idx] = merged;
        }
      });
      Haptics.success();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Markeer als mislukt met retry optie
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx >= 0) {
          _messages[idx]['_delivery_status'] = 'failed'; // ✗
          _messages[idx]['_error'] = e.message;
        }
      });
      Haptics.error();
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': 'ClientMessages', 'action': 'sendMessage'}));
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx >= 0) {
          _messages[idx]['_delivery_status'] = 'failed';
          _messages[idx]['_error'] = S.of(context).versturenMisluktTikOmOpnieuwTe;
        }
      });
      Haptics.error();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Retry een mislukt bericht
  Future<void> _retrySend(Map<String, dynamic> failedMessage) async {
    final body = mapStr(failedMessage, ['body', 'message', 'text']);
    final tempId = failedMessage['id']?.toString() ?? '';
    if (body.isEmpty) return;

    // Reset naar pending
    setState(() {
      final idx = _messages.indexWhere((m) => m['id'] == tempId);
      if (idx >= 0) {
        _messages[idx]['_delivery_status'] = 'pending';
        _messages[idx].remove('_error');
      }
    });

    try {
      final created = await context.read<GymiesApi>().sendClientMessage(
        widget.conversationId,
        body,
      );
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx >= 0) {
          final merged = <String, dynamic>{
            ..._messages[idx],
            ...created,
            'is_mine': true,
            'from_user_id': _myUserId,
            '_delivery_status': 'sent',
          };
          _messages[idx] = merged;
        }
      });
      Haptics.success();
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, hint: Hint.withMap({'screen': 'ClientMessages', 'action': 'retrySend'}));
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx >= 0) {
          _messages[idx]['_delivery_status'] = 'failed';
          _messages[idx]['_error'] = S.of(context).versturenMisluktTikOmOpnieuwTe;
        }
      });
    }
  }

  Future<void> _respondReschedule(Map<String, dynamic> message, String action) async {
    final data = message['data'] is Map
        ? Map<String, dynamic>.from(message['data'] as Map)
        : message;
    final rescheduleReq = data['reschedule_request'];
    final reqMap = rescheduleReq is Map
        ? Map<String, dynamic>.from(rescheduleReq)
        : data;
    final bookingId = mapStr(reqMap, ['booking_id', 'bookingId']).isEmpty
        ? mapStr(data, ['booking_id', 'bookingId'])
        : mapStr(reqMap, ['booking_id', 'bookingId']);
    if (bookingId.isEmpty) return;
    setState(() => _rescheduleBusyIds.add(bookingId));
    try {
      if (action == 'counter') {
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
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
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
      await _load();
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

  // ── Verplaats sessie flow (klant-kant) ─────────────────────

  /// Opent de "Verplaats sessie" flow voor de klant:
  /// 1. Haal boekingen op bij deze trainer
  /// 2. Filter op upcoming + niet ingecheckt
  /// 3. 0 sessies → melding, 1 sessie → direct picker, 2+ → bottom sheet
  /// 4. Waarschuwing als sessie vandaag/binnen 2 uur is
  /// 5. Datum/tijd picker → requestBookingReschedule() API
  /// 6. Kaart in chat + kalender sync
  Future<void> _openClientRescheduleFlow() async {
    Haptics.selection();
    final api = context.read<GymiesApi>();

    // ── 1. Laad boekingen ──
    List<Booking> bookings;
    try {
      final all = await api.getBookings();
      // Filter: upcoming, niet gecanceld, niet ingecheckt, bij deze trainer
      bookings = all.where((b) {
        final matchesTrainer = b.trainerName.toLowerCase() ==
            widget.title.toLowerCase();
        final isValid = b.isUpcoming &&
            b.status != 'cancelled' &&
            b.status != 'checked_in' &&
            b.status != 'completed' &&
            !b.safeSessionActive;
        return matchesTrainer && isValid;
      }).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(S.of(context).konSessiesNietLaden),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    if (!mounted) return;

    // ── 2. Edge case: geen sessies ──
    if (bookings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).geenVerplaatsbareSessiesBij(widget.title)),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      return;
    }

    // ── 3. Selectie: 1 sessie → direct, 2+ → picker ──
    Booking selected;
    if (bookings.length == 1) {
      selected = bookings.first;
    } else {
      final picked = await showDialog<Booking>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: _ClientRescheduleBookingPicker(
            bookings: bookings,
            trainerName: widget.title,
          ),
        ),
      );
      if (picked == null || !mounted) return;
      selected = picked;
    }

    // ── 4. Edge case: sessie vandaag of binnen 2 uur ──
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

    // ── 5. Slot picker: toon beschikbare momenten van trainer ──
    final trainerId = selected.trainerUserId;
    if (trainerId == null || trainerId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text(S.of(context).traineridOntbreekt), backgroundColor: Colors.red.shade600),
        );
      }
      return;
    }

    final newDateTime = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RescheduleSlotPicker(
        api: api,
        trainerId: trainerId,
        trainerName: selected.trainerName,
        currentScheduledAt: selected.scheduledAt,
      ),
    );
    if (newDateTime == null || !mounted) return;

    // ── 6. Verstuur reschedule request ──
    Haptics.light();
    try {
      await api.requestBookingReschedule(
        bookingId: selected.id,
        requestedAt: newDateTime,
      );
      if (!mounted) return;
      Haptics.success();

      // Voeg reschedule-kaart bericht toe aan chat
      final rescheduleData = <String, dynamic>{
        'type': 'reschedule_request',
        'booking_id': selected.id,
        'scheduled_at': selected.scheduledAt.toIso8601String(),
        'requested_at': newDateTime.toIso8601String(),
        S.of(context).trainername: selected.trainerName,
        'session_type': selected.sessionType,
        'duration_minutes': selected.durationMinutes,
        'status': 'pending',
        'is_mine': true,
      };
      setState(() {
        _messages.add({
          'id': 'reschedule_${DateTime.now().millisecondsSinceEpoch}',
          'body': jsonEncode(rescheduleData),
          'is_mine': true,
          'created_at': DateTime.now().toIso8601String(),
          '_delivery_status': 'sent',
          ...rescheduleData,
        });
      });
      _jumpToBottom();

      // Auto-sync kalender
      try {
        final enabled = await CalendarService.instance.isAutoSyncEnabled();
        if (enabled) {
          final updatedBooking = Booking(
            id: selected.id,
            trainerName: selected.trainerName,
            scheduledAt: newDateTime,
            durationMinutes: selected.durationMinutes,
            status: 'confirmed',
            sessionType: selected.sessionType,
            packageName: selected.packageName,
          );
          await CalendarService.instance.addBookingToCalendar(updatedBooking);
        }
      } catch (e) {
        // Fail-open: Calendar sync optional, booking updated anyway
        if (kDebugMode) debugPrint('[ClientMessages] Calendar sync failed: $e');
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
    } catch (_) {
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

  /// Toon naam-label boven de bubbel als de afzender wisselt t.o.v. vorig bericht,
  /// of als er een datum-separator tussenzit.
  bool _showSenderLabel(int index) {
    if (index == 0) return true;
    if (_isDifferentDay(index)) return true; // Na datum-separator altijd tonen
    final currentMine = _isMine(_messages[index]);
    final previousMine = _isMine(_messages[index - 1]);
    return currentMine != previousMine;
  }

  /// Delivery icon: enkel vinkje (verzonden) of dubbel vinkje (gelezen).
  Widget _buildDeliveryIcon(String messageCreatedAt) {
    // Vergelijk bericht timestamp met _lastReadAt
    if (_lastReadAt != null && _lastReadAt!.isNotEmpty && messageCreatedAt.isNotEmpty) {
      final msgTime = DateTime.tryParse(messageCreatedAt);
      final readTime = DateTime.tryParse(_lastReadAt!);
      if (msgTime != null && readTime != null && !msgTime.isAfter(readTime)) {
        // Gelezen: dubbel vinkje in blauw
        return Icon(Icons.done_all_rounded, size: 14, color: const Color(0xFF3B82F6));
      }
    }
    // Niet gelezen: enkel vinkje
    return Icon(Icons.done_rounded, size: 14, color: Colors.white54);
  }

  // ── Slimme quick replies op basis van context ──────────────

  /// Analyseert het laatste trainer-bericht + tijdstip om relevante
  /// snelle antwoorden te tonen. Prioriteit:
  /// 1. Reactie op trainer's laatste bericht (keyword-matching)
  /// 2. Sessie-context (vandaag/binnenkort/recent)
  /// 3. Algemene fallback
  List<Widget> _buildSmartQuickReplies() {
    final chips = <Widget>[];
    final now = DateTime.now();
    final hour = now.hour;

    // Zoek het laatste bericht van de trainer (niet van mij)
    Map<String, dynamic>? lastTrainerMsg;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (!_isMine(_messages[i])) {
        lastTrainerMsg = _messages[i];
        break;
      }
    }

    final trainerText = lastTrainerMsg != null
        ? mapStr(lastTrainerMsg, ['body', 'message', 'text']).toLowerCase()
        : '';

    // Bepaal sessie-context: vandaag, binnenkort, of recent afgerond
    final lastMsgTime = lastTrainerMsg != null
        ? DateTime.tryParse(mapStr(lastTrainerMsg, ['created_at', 'createdAt']))
        : null;
    // ignore: unused_local_variable
    final isRecentMsg = lastMsgTime != null &&
        now.difference(lastMsgTime).inHours < 4;

    // ── 1. Reactief: reageer op wat de trainer zei ──

    // Trainer vraagt iets / stelt voor
    if (trainerText.contains('verplaats') ||
        trainerText.contains('ander tijdstip')) {
      chips.add(_QuickReplyChip(label: 'Prima!', icon: Icons.check_rounded, onTap: () => _send(S.of(context).primaDatIsGoed)));
      chips.add(_QuickReplyChip(label: 'Liever niet', icon: Icons.close_rounded, onTap: () => _send(S.of(context).lieverNietKanHetOpDe)));
      chips.add(_QuickReplyChip(label: 'Welke opties?', icon: Icons.calendar_today_rounded, onTap: () => _send(S.of(context).welkeTijdenHebJeBeschikbaar)));
    }
    else if (trainerText.contains(S.of(context).hoeWas) || trainerText.contains(S.of(context).hoeGing) ||
             trainerText.contains(S.of(context).hoeVondJe) || trainerText.contains('feedback')) {
      chips.add(_QuickReplyChip(label: 'Super!', icon: Icons.star_rounded, onTap: () => _send('Super les, bedankt!')));
      chips.add(_QuickReplyChip(label: S.of(context).wasGoed, icon: Icons.thumb_up_outlined, onTap: () => _send('Was goed! Ik merk vooruitgang.')));
      chips.add(_QuickReplyChip(label: 'Pittig!', icon: Icons.fitness_center_rounded, onTap: () => _send(S.of(context).pittigMaarGoedVoelHetNog)));
    }
    else if (trainerText.contains('tot zo') ||
             trainerText.contains(S.of(context).zieJeZo) || trainerText.contains('we zien')) {
      chips.add(_QuickReplyChip(label: 'Tot zo!', icon: Icons.waving_hand_outlined, onTap: () => _send('Tot zo!')));
      chips.add(_QuickReplyChip(label: 'Ik ben onderweg', icon: Icons.directions_run_rounded, onTap: () => _send('Ik ben onderweg!')));
    }
    else if (trainerText.contains('afzeg') ||
             trainerText.contains('annule') || trainerText.contains(S.of(context).nietDoorgaan)) {
      chips.add(_QuickReplyChip(label: 'Jammer, begrijp ik', icon: Icons.sentiment_neutral_rounded, onTap: () => _send('Jammer, maar ik begrijp het!')));
      chips.add(_QuickReplyChip(label: 'Nieuwe afspraak?', icon: Icons.event_rounded, onTap: () => _send(S.of(context).kunnenWeEenNieuweAfspraakInplannen)));
    }
    else if (trainerText.contains('goed bezig') ||
             trainerText.contains('top')) {
      chips.add(_QuickReplyChip(label: 'Dankjewel!', icon: Icons.favorite_outline_rounded, onTap: () => _send('Dankjewel! Dat motiveert!')));
      chips.add(_QuickReplyChip(label: 'Komt door jou!', icon: Icons.emoji_events_outlined, onTap: () => _send('Komt door jouw begeleiding!')));
    }
    else if (trainerText.contains('schema') ||
             trainerText.contains('programma')) {
      chips.add(_QuickReplyChip(label: 'Top, duidelijk!', icon: Icons.check_circle_outline_rounded, onTap: () => _send('Top, duidelijk!')));
      chips.add(_QuickReplyChip(label: S.of(context).vraagjeHierover, icon: Icons.help_outline_rounded, onTap: () => _send(S.of(context).ikHebHierNogEenVraagje)));
    }
    else if (trainerText.contains('betaal') || trainerText.contains(S.of(context).factuur) ||
             trainerText.contains('pakket')) {
      chips.add(_QuickReplyChip(label: 'Is geregeld', icon: Icons.check_rounded, onTap: () => _send('Is geregeld!')));
      chips.add(_QuickReplyChip(label: 'Meer info?', icon: Icons.info_outline_rounded, onTap: () => _send(S.of(context).kunJeMeMeerInfoGeven)));
    }

    // ── 2. Sessie-context chips (als er geen reactieve match was) ──

    if (chips.isEmpty) {
      // Ochtend → sessie-dag chips
      if (hour >= 6 && hour < 12) {
        chips.add(_QuickReplyChip(label: S.of(context).goedemorgen, icon: Icons.wb_sunny_outlined, onTap: () => _send('Goedemorgen!')));
        chips.add(_QuickReplyChip(label: 'Ik kom eraan', icon: Icons.directions_run_rounded, onTap: () => _send('Ik kom eraan!')));
        chips.add(_QuickReplyChip(label: 'Moet afzeggen', icon: Icons.event_busy_rounded, onTap: () => _send(S.of(context).ikMoetHelaasAfzeggenVoorVandaag)));
      }
      // Middag → na-sessie chips
      else if (hour >= 12 && hour < 18) {
        chips.add(_QuickReplyChip(label: S.of(context).goedeLes, icon: Icons.star_outline_rounded, onTap: () => _send('Goede les vandaag, bedankt!')));
        chips.add(_QuickReplyChip(label: 'Verplaatsen?', icon: Icons.swap_horiz_rounded, onTap: () => _send('Kunnen we de les verplaatsen?')));
        chips.add(_QuickReplyChip(label: 'Wanneer weer?', icon: Icons.calendar_today_rounded, onTap: () => _send(S.of(context).wanneerIsDeVolgendeSessie)));
      }
      // Avond → reflectie chips
      else {
        chips.add(_QuickReplyChip(label: 'Bedankt!', icon: Icons.favorite_outline_rounded, onTap: () => _send(S.of(context).bedanktVoorVandaag)));
        chips.add(_QuickReplyChip(label: 'Tot de volgende', icon: Icons.emoji_events_outlined, onTap: () => _send(S.of(context).totDeVolgendeSessie)));
        chips.add(_QuickReplyChip(label: 'Vraagje', icon: Icons.help_outline_rounded, onTap: () => _send(S.of(context).ikHebEenVraagje)));
      }
    }

    // ── 3. "Verplaats sessie" chip – opent de reschedule flow ──
    chips.add(_QuickReplyChip(
      label: S.of(context).verplaatsSessie,
      icon: Icons.event_repeat_rounded,
      onTap: _openClientRescheduleFlow,
    ));

    // ── 4. Altijd-beschikbare universele chips achteraan ──
    // Voeg max 2 universele toe die nog niet in de lijst staan
    final universals = <_QuickReplyData>[
      _QuickReplyData('Bedankt!', Icons.favorite_outline_rounded, 'Bedankt!'),
      _QuickReplyData('Tot zo!', Icons.waving_hand_outlined, 'Tot zo!'),
      _QuickReplyData('Ik ben er!', Icons.check_circle_outline_rounded, 'Ik ben er!'),
    ];
    final existingLabels = chips.whereType<_QuickReplyChip>().map((c) => c.label).toSet();
    int added = 0;
    for (final u in universals) {
      if (added >= 2) break;
      if (existingLabels.contains(u.label)) continue;
      chips.add(_QuickReplyChip(label: u.label, icon: u.icon, onTap: () => _send(u.message)));
      added++;
    }

    return chips;
  }

  /// Controleert of bericht op index i op een andere dag valt dan het vorige bericht.
  bool _isDifferentDay(int index) {
    if (index <= 0 || index >= _messages.length) return false;
    final current = DateTime.tryParse(
      mapStr(_messages[index], ['created_at', 'createdAt']),
    );
    final previous = DateTime.tryParse(
      mapStr(_messages[index - 1], ['created_at', 'createdAt']),
    );
    if (current == null || previous == null) return false;
    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  /// Formatteer datum als "Vandaag", "Gisteren", of "dd MMM yyyy".
  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return 'Vandaag';
    if (dateOnly == today.subtract(const Duration(days: 1))) return 'Gisteren';
    const months = [
      'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
      'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
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

  /// AppBar titel met connection status en typing indicator.
  Widget _buildAppBarTitle() {
    final pusherState = _pusher?.state ?? PusherConnectionState.disconnected;

    // Status indicator kleur
    Color statusColor;
    String? statusText;
    switch (pusherState) {
      case PusherConnectionState.connected:
        statusColor = const Color(0xFF22C55E); // groen
        statusText = null; // Geen tekst nodig bij connected
        break;
      case PusherConnectionState.connecting:
        statusColor = const Color(0xFFF59E0B); // oranje
        statusText = 'Verbinden...';
        break;
      case PusherConnectionState.reconnecting:
        statusColor = const Color(0xFFF59E0B); // oranje
        statusText = 'Herverbinden...';
        break;
      case PusherConnectionState.disconnected:
        statusColor = Colors.grey.shade400;
        statusText = null;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.sora(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: GymiesColors.darkBlue,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
          ],
        ),
        if (_trainerIsTyping)
          Text(
            S.of(context).aanHetTypen,
            style: GoogleFonts.sora(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: GymiesColors.primary,
              fontStyle: FontStyle.italic,
            ),
          )
        else if (statusText != null)
          Text(
            statusText,
            style: GoogleFonts.sora(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade500,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: widget.title,
        titleWidget: _buildAppBarTitle(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: _openClientRescheduleFlow,
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
              child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final m = _messages[i];
                        final rescheduleCard =
                            RescheduleCardWidget.fromMessage(
                          m,
                          busy: _rescheduleBusyIds.contains(
                            RescheduleCardWidget.getBookingIdFromMessage(m),
                          ),
                          isMine: _isMine(m),
                          onAccept: () => _respondReschedule(m, 'accept'),
                          onReject: () => _respondReschedule(m, 'reject'),
                          onCounterPropose: () =>
                              _respondReschedule(m, 'counter'),
                        );
                        if (rescheduleCard != null) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: rescheduleCard,
                          );
                        }
                        final mine = _isMine(m);
                        final body = mapStr(m, ['body', 'message', 'text']);

                        // ── Verberg lege berichten ──
                        final bodyTrimmed = body.trim();
                        if (bodyTrimmed.isEmpty || bodyTrimmed == '-' || bodyTrimmed == '–') {
                          return const SizedBox.shrink();
                        }

                        final createdAtStr = mapStr(m, ['created_at', 'createdAt']);
                        final createdAt = DateTime.tryParse(createdAtStr);
                        final ts = createdAt != null
                            ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
                            : '';
                        final showLabel = _showSenderLabel(i);
                        final deliveryStatus = (m['_delivery_status'] ?? 'sent').toString();
                        final isFailed = deliveryStatus == 'failed';
                        final isPending = deliveryStatus == 'pending';

                        // ── Datum separator tussen berichten van verschillende dagen ──
                        Widget? dateSeparator;
                        if (i == 0 || _isDifferentDay(i)) {
                          final label = _formatDateLabel(createdAt ?? DateTime.now());
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
                                  label,
                                  style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: mine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (dateSeparator != null) dateSeparator,
                            if (showLabel)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: i == 0 ? 0 : 16,
                                  bottom: 4,
                                  left: mine ? 0 : 4,
                                  right: mine ? 4 : 0,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: mine
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  children: [
                                    if (!mine)
                                      Container(
                                        width: 20,
                                        height: 20,
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: GymiesColors.darkBlue.withOpacity(0.1),
                                        ),
                                        child: Center(
                                          child: Text(
                                            widget.title.isNotEmpty
                                                ? widget.title[0].toUpperCase()
                                                : 'T',
                                            style: GoogleFonts.sora(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: GymiesColors.darkBlue,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      mine ? 'Jij' : widget.title,
                                      style: GoogleFonts.sora(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: mine
                                            ? GymiesColors.darkBlue.withOpacity(0.5)
                                            : GymiesColors.darkBlue.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            GestureDetector(
                              onTap: isFailed ? () => _retrySend(m) : null,
                              child: Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
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
                                    border: mine
                                        ? null
                                        : Border.all(color: Colors.grey.shade200),
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
                                      // ── Timestamp + delivery status ──
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
                                              _buildDeliveryIcon(createdAtStr),
                                          ],
                                        ],
                                      ),
                                      // ── Foutmelding + retry hint ──
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
                      },
                    ),
                  ),
          ),
          // ── Typing indicator ──────────────────────────
          if (_trainerIsTyping)
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GymiesColors.darkBlue.withOpacity(0.1),
                    ),
                    child: Center(
                      child: Text(
                        widget.title.isNotEmpty ? widget.title[0].toUpperCase() : 'T',
                        style: GoogleFonts.sora(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TypingDots(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // ── Slimme quick reply chips ──────────────────
          Builder(builder: (_) {
            final chips = _buildSmartQuickReplies();
            if (chips.isEmpty) return const SizedBox.shrink();
            return Container(
              color: Colors.grey.shade50,
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
                      onChanged: (_) => _sendTypingEvent(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_sending || _controller.text.trim().isEmpty) ? null : _send,
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
}

/// Data-class voor universele quick reply opties.
class _QuickReplyData {
  const _QuickReplyData(this.label, this.icon, this.message);
  final String label;
  final IconData icon;
  final String message;
}

class _QuickReplyChip extends StatelessWidget {
  const _QuickReplyChip({
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

/// Bottom sheet picker wanneer de klant meerdere sessies heeft bij de trainer.
class _ClientRescheduleBookingPicker extends StatelessWidget {
  const _ClientRescheduleBookingPicker({
    required this.bookings,
    required this.trainerName,
  });

  final List<Booking> bookings;
  final String trainerName;

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
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
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
                        'Kies een sessie bij $trainerName',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade400, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
          SizedBox(height: MediaQuery.of(context).padding.bottom),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 80),
          // Gestapelde chat-bubbels icoon
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: GymiesColors.darkBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 28,
                      color: GymiesColors.darkBlue.withOpacity(0.3),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.chat_rounded,
                      size: 24,
                      color: GymiesColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 20,
              color: GymiesColors.darkBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            S.of(context).ontdekTrainersBijJouInDeBuurt,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 13,
              color: GymiesColors.darkBlue.withOpacity(0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Geanimeerde typing dots (drie stippen die om de beurt bouncen).
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (_controller.value + i * 0.25) % 1.0;
          final bounce = phase < 0.5
              ? (phase * 2)
              : (1 - (phase - 0.5) * 2);
          return Container(
            margin: EdgeInsets.only(right: i < 2 ? 3 : 0),
            child: Transform.translate(
              offset: Offset(0, -4.0 * bounce),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GymiesColors.darkBlue.withOpacity(0.4 + 0.3 * bounce),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
