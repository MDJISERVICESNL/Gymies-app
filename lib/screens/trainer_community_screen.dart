import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/ui_constants.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';

/// Trainer Community Screen — tabbed interface voor:
/// 1. Groepschats (gym-scoped group chats)
/// 2. Trainers (fellow trainers aan dezelfde gym's)
class TrainerCommunityScreen extends StatefulWidget {
  const TrainerCommunityScreen({super.key});

  @override
  State<TrainerCommunityScreen> createState() => _TrainerCommunityScreenState();
}

class _TrainerCommunityScreenState extends State<TrainerCommunityScreen>
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Trainer Community',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GymiesColors.primary,
          indicatorWeight: 3,
          labelColor: GymiesColors.primary,
          unselectedLabelColor: Colors.grey.shade600,
          labelStyle: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Groepschats'),
            Tab(text: 'Trainers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Groepschats
          const _GroupChatsTab(),
          // Tab 2: Trainers
          const _TrainersTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: Groepschats
// ─────────────────────────────────────────────────────────────────────────────

class _GroupChatsTab extends StatefulWidget {
  const _GroupChatsTab();

  @override
  State<_GroupChatsTab> createState() => _GroupChatsTabState();
}

class _GroupChatsTabState extends State<_GroupChatsTab> {
  late Future<Map<String, dynamic>> _chatsFuture;

  @override
  void initState() {
    super.initState();
    _chatsFuture = context.read<GymiesApi>().getMyGymChats();
  }

  void _loadChats() {
    if (mounted) {
      setState(() {
        _chatsFuture = context.read<GymiesApi>().getMyGymChats();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _loadChats();
        await _chatsFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _chatsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(GymiesColors.primary),
              ),
            );
          }

          if (snapshot.hasError) {
            return _ErrorState(
              error: snapshot.error,
              onRetry: () => setState(_loadChats),
            );
          }

          final data = snapshot.data ?? {};
          final chats = (data['data'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

          if (chats.isEmpty) {
            return _EmptyState(
              title: 'Geen groepschats',
              message: 'Je bent nog niet lid van groepschats. Neem contact op met je gym.',
              icon: Icons.chat_outlined,
            );
          }

          return ListView.builder(
            itemCount: chats.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final chat = chats[index];
              return _ChatListTile(
                chat: chat,
                onTap: () {
                  Haptics.selection();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _ChatDetailScreen(chat: chat),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// List tile voor een gym chat
class _ChatListTile extends StatelessWidget {
  const _ChatListTile({
    required this.chat,
    required this.onTap,
  });

  final Map<String, dynamic> chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gymName = chat['gym_name'] ?? 'Onbekende gym';
    final memberCount = chat['member_count'] ?? 0;
    final lastMessage = chat['last_message'] ?? '(Geen berichten)';
    final lastMessageAt = chat['last_message_at'];
    final isMuted = chat['is_muted'] ?? false;

    final lastMessageTime = lastMessageAt != null
        ? _formatMessageTime(DateTime.parse(lastMessageAt.toString()))
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gym name + muted badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      gymName,
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.darkBlue,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMuted)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.notifications_off,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Last message preview
              Text(
                lastMessage,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Footer: member count + timestamp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$memberCount leden',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    lastMessageTime,
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Gisteren';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Trainers
// ─────────────────────────────────────────────────────────────────────────────

class _TrainersTab extends StatefulWidget {
  const _TrainersTab();

  @override
  State<_TrainersTab> createState() => _TrainersTabState();
}

class _TrainersTabState extends State<_TrainersTab> {
  late Future<Map<String, dynamic>> _trainersFuture;

  @override
  void initState() {
    super.initState();
    _loadTrainers();
  }

  void _loadTrainers() {
    _trainersFuture = context.read<GymiesApi>().getMyGymTrainers();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(_loadTrainers);
        await _trainersFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _trainersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(GymiesColors.primary),
              ),
            );
          }

          if (snapshot.hasError) {
            return _ErrorState(
              error: snapshot.error,
              onRetry: () => setState(_loadTrainers),
            );
          }

          final data = snapshot.data ?? {};
          final trainers = (data['data'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

          if (trainers.isEmpty) {
            return _EmptyState(
              title: 'Geen trainers',
              message: 'Er zijn geen andere trainers op je gym\'s.',
              icon: Icons.people_outline,
            );
          }

          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.9,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            padding: const EdgeInsets.all(12),
            itemCount: trainers.length,
            itemBuilder: (context, index) {
              final trainer = trainers[index];
              return _TrainerCard(trainer: trainer);
            },
          );
        },
      ),
    );
  }
}

/// Card voor een trainer in de grid
class _TrainerCard extends StatelessWidget {
  const _TrainerCard({required this.trainer});

  final Map<String, dynamic> trainer;

  @override
  Widget build(BuildContext context) {
    final name = trainer['name'] ?? 'Trainer';
    final specialization = trainer['specialization'] ?? 'Specialisatie onbekend';
    final avatarUrl = trainer['avatar_url'] as String?;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: GymiesColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.sora(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: GymiesColors.accent,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: GoogleFonts.sora(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: GymiesColors.accent,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            // Name
            Text(
              name,
              style: GoogleFonts.sora(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: GymiesColors.darkBlue,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // Specialization
            Text(
              specialization,
              style: GoogleFonts.sora(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat Detail Screen — inline chat view
// ─────────────────────────────────────────────────────────────────────────────

class _ChatDetailScreen extends StatefulWidget {
  const _ChatDetailScreen({required this.chat});

  final Map<String, dynamic> chat;

  @override
  State<_ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<_ChatDetailScreen> {
  late Future<Map<String, dynamic>> _messagesFuture;
  late TextEditingController _messageController;
  bool _isSending = false;
  late String _chatId;
  late String _gymName;

  @override
  void initState() {
    super.initState();
    _chatId = widget.chat['id']?.toString() ?? '';
    _gymName = widget.chat['gym_name'] ?? 'Chat';
    _messageController = TextEditingController();
    _loadMessages();
  }

  void _loadMessages() {
    _messagesFuture = context.read<GymiesApi>().getGymChatMessages(_chatId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final api = context.read<GymiesApi>();
    setState(() => _isSending = true);
    _messageController.clear();

    try {
      await api.sendGymChatMessage(_chatId, text);
      if (mounted) {
        Haptics.success();
        setState(() {
          _isSending = false;
          _messagesFuture = api.getGymChatMessages(_chatId);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        Haptics.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fout bij verzenden: ${e.message}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _toggleMute() async {
    final api = context.read<GymiesApi>();
    try {
      await api.toggleGymChatMute(_chatId);
      if (mounted) {
        Haptics.light();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat notificaties bijgewerkt')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        Haptics.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: ${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: _gymName,
        actions: [
          GymiesAppBarAction(
            icon: Icons.notifications_off,
            tooltip: 'Mute notificaties',
            onTap: _toggleMute,
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _messagesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(GymiesColors.primary),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Fout bij laden van berichten',
                          style: GoogleFonts.sora(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => setState(_loadMessages),
                          child: const Text('Opnieuw proberen'),
                        ),
                      ],
                    ),
                  );
                }

                final data = snapshot.data ?? {};
                final messages = (data['data'] as List<dynamic>?)
                        ?.cast<Map<String, dynamic>>()
                        ?.reversed
                        .toList() ??
                    [];

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Nog geen berichten',
                      style: GoogleFonts.sora(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _MessageBubble(message: message);
                  },
                );
              },
            ),
          ),
          // Input bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              12 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isSending,
                    maxLines: null,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Typ een bericht...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
                        borderSide: const BorderSide(
                          color: GymiesColors.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isSending ? null : _sendMessage,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isSending ? Colors.grey.shade300 : GymiesColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: _isSending
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  GymiesColors.darkBlue,
                                ),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.send,
                            color: GymiesColors.darkBlue,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Message bubble — left (others) or right (own) aligned
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final senderName = message['sender_name'] ?? 'Trainer';
    final senderId = message['sender_id']?.toString();
    final text = message['message'] ?? '';
    final createdAt = message['created_at'];

    final currentUserId = context.read<AuthService>().userId;
    final isOwnMessage = senderId == currentUserId;

    final timestamp = createdAt != null
        ? DateTime.parse(createdAt.toString())
        : DateTime.now();
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOwnMessage) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: GymiesColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: GymiesColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isOwnMessage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      senderName,
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: isOwnMessage
                        ? GymiesColors.primary
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    text,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: isOwnMessage
                          ? GymiesColors.darkBlue
                          : Colors.grey.shade800,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: GoogleFonts.sora(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          if (isOwnMessage) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable UI Components
// ─────────────────────────────────────────────────────────────────────────────

/// Empty state widget voor wanneer er geen data beschikbaar is
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              style: GoogleFonts.sora(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state widget voor wanneer er een fout optreedt
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Er is iets fout gelopen',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error?.toString() ?? 'Onbekende fout',
              style: GoogleFonts.sora(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Opnieuw proberen'),
          ),
        ],
      ),
    );
  }
}
