import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/timing_constants.dart';
import '../config/ui_constants.dart';
import '../services/api_config.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/reschedule_card_widget.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<GymiesApi>().getClientConversations();
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
    } catch (e) {
      debugPrint('[ClientMessages] Gesprekken laden fout: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Kon gesprekken niet laden.';
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
    final name = mapStr(c, ['trainer_name', 'trainerName', 'name']).toLowerCase();
    return name.contains('gymies') || name.contains('support');
  }

  String _conversationDisplayName(Map<String, dynamic> c) {
    final regular = mapStr(c, ['trainer_name', 'trainerName', 'name']);
    return regular.isEmpty ? 'Trainer' : regular;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Berichten'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _conversations.isEmpty
                  ? ListView(
                      children: const [
                        _EmptyView(
                          title: 'Nog geen gesprekken',
                          subtitle: 'Hier zie je alleen chats met trainers.',
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _conversations.length,
                      itemBuilder: (_, i) {
                        final c = _conversations[i];
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
                          child: Dismissible(
                          key: Key(id.isNotEmpty ? id : 'conv_$i'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (direction) async {
                            // Probeer gesprek via API te verwijderen.
                            // Bij succes: verwijder lokaal. Bij API fout (endpoint
                            // niet beschikbaar): verwijder alsnog lokaal (graceful).
                            if (id.isNotEmpty) {
                              try {
                                await context.read<GymiesApi>().deleteClientConversation(id);
                              } catch (e) {
                                debugPrint('[ClientMessages] Gesprek verwijderen API fout: $e');
                                // Graceful: verwijder lokaal uit lijst, komt terug na reload
                              }
                            }
                            return true;
                          },
                          onDismissed: (direction) {
                            if (mounted) {
                              setState(() {
                                _conversations.removeAt(i);
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Gesprek verwijderd'),
                                  backgroundColor: GymiesColors.darkBlue,
                                  action: SnackBarAction(
                                    label: 'Herstellen',
                                    textColor: GymiesColors.primary,
                                    onPressed: () => _load(), // Herlaad lijst
                                  ),
                                ),
                              );
                            }
                          },
                          background: Container(
                            color: Colors.red.shade600,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(
                              Icons.delete_rounded,
                              color: Colors.white,
                            ),
                          ),
                          child: Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: GymiesColors.primary.withValues(
                                  alpha: 0.2,
                                ),
                                child: Text(
                                  trainerName.isNotEmpty ? trainerName[0].toUpperCase() : 'T',
                                  style: const TextStyle(
                                    color: GymiesColors.darkBlue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(trainerName),
                              subtitle: Text(
                                '${lastMessage.isEmpty ? 'Open gesprek' : lastMessage}\n$lastAt',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: unread > 0
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: GymiesColors.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$unread',
                                        style: const TextStyle(
                                          color: GymiesColors.darkBlue,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.chevron_right),
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
                            ),
                          ),
                        ),
                      );
                      },
                    ),
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
      if (mounted) _refreshMessagesSilently();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon chat niet laden.';
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
    } catch (e) {
      debugPrint('[ClientMessages] Silent message refresh fout: $e');
      // Stil falen voor achtergrond sync.
    }
  }

  void _startRealtime() {
    _startPollingFallback();
    _connectWebSocket();
  }

  void _startPollingFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(TimingConstants.messagePollInterval, (_) {
      if (!mounted) return;
      if (_loading || _sending) return;
      _refreshMessagesSilently();
    });
  }

  List<Uri> _wsCandidates() {
    final token = context.read<AuthService>().token ?? '';
    final conversationId = widget.conversationId;
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

  void _connectWebSocket() {
    if (!gymiesWsEnabled || _connectingWs || _wsConnected) return;
    final candidates = _wsCandidates();
    if (candidates.isEmpty) return;
    _connectingWs = true;
    for (final uri in candidates) {
      try {
        final channel = WebSocketChannel.connect(uri);
        final sub = channel.stream.listen(
          (event) {
            if (!mounted) return;
            _wsConnected = true;
            final parsed = _parseIncomingWsMessage(event);
            if (parsed == null) return;
            setState(() {
              _mergeMessages([parsed]);
            });
            _jumpToBottom();
          },
          onError: (_) {
            _wsConnected = false;
          },
          onDone: () {
            _wsConnected = false;
            if (mounted) {
              Future<void>.delayed(
                const Duration(seconds: 3),
                _connectWebSocket,
              );
            }
          },
          cancelOnError: false,
        );
        _wsChannel = channel;
        _wsSubscription = sub;
        _connectingWs = false;
        return;
      } catch (e) {
        debugPrint('[ClientMessages] WebSocket verbinding poging fout: $e');
        // probeer volgende kandidaat
      }
    }
    _connectingWs = false;
  }

  Map<String, dynamic>? _parseIncomingWsMessage(dynamic rawEvent) {
    dynamic decoded = rawEvent;
    if (rawEvent is String) {
      try {
        decoded = jsonDecode(rawEvent);
      } catch (e) {
        debugPrint('[ClientMessages] JSON decode websocket message fout: $e');
        return {
          'body': rawEvent,
          'created_at': DateTime.now().toIso8601String(),
        };
      }
    }
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      final message = decoded['message'];
      if (message is Map<String, dynamic>) return message;
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  bool _isMine(Map<String, dynamic> message) {
    final direct = mapPick(message, ['is_mine', 'isMine', 'from_me']);
    if (direct is bool) return direct;
    if (direct is num) return direct.toInt() == 1;
    // Compare sender ID against the logged-in user's ID
    final myId = mapStr(
      context.read<AuthService>().user ?? {},
      ['id', 'user_id', 'userId'],
    );
    if (myId.isNotEmpty) {
      final senderId = mapStr(message, ['sender_id', 'senderId', 'user_id']);
      if (senderId.isNotEmpty) return senderId == myId;
    }
    final senderRole = mapStr(message, ['sender_role', 'role']).toLowerCase();
    return senderRole == 'client' || senderRole == 'user';
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final created = await context.read<GymiesApi>().sendClientMessage(
        widget.conversationId,
        text,
      );
      if (!mounted) return;
      _controller.clear();
      if (created.isNotEmpty) {
        created['is_mine'] = true;
        setState(() => _mergeMessages([created]));
      } else {
        await _load();
      }
      _jumpToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
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
                      ? 'Verzoek afgewezen'
                      : 'Tegenvoorstel verstuurd',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: widget.title,
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
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.72,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? GymiesColors.darkBlue
                                  : GymiesColors.primary.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              body.isEmpty ? '-' : body,
                              style: TextStyle(
                                color: mine
                                    ? Colors.white
                                    : GymiesColors.darkBlue,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
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
                        hintText: 'Typ een bericht...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
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
          const Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey),
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
