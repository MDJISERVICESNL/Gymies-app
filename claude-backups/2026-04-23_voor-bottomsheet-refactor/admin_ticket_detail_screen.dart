import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme/gymies_theme.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';

/// Admin ticket detail – berichten bekijken en beantwoorden.
class AdminTicketDetailScreen extends StatefulWidget {
  const AdminTicketDetailScreen({
    super.key,
    required this.ticket,
  });

  final Map<String, dynamic> ticket;

  @override
  State<AdminTicketDetailScreen> createState() => _AdminTicketDetailScreenState();
}

class _AdminTicketDetailScreenState extends State<AdminTicketDetailScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _replyController = TextEditingController();
  bool _sending = false;
  final ScrollController _scrollController = ScrollController();

  String get _ticketId => mapStr(widget.ticket, ['id', 'ticket_id', 'ticketId']);
  String get _subject => mapStr(widget.ticket, ['subject', 'title', 'topic']);
  String get _status =>
      mapStr(widget.ticket, ['status', 'state']).isNotEmpty
          ? mapStr(widget.ticket, ['status', 'state'])
          : 'open';
  String get _author =>
      mapStr(widget.ticket, [
        'author_name',
        'user_name',
        'client_name',
        'trainer_name',
        'created_by_name',
      ]);
  String get _authorEmail =>
      mapStr(widget.ticket, ['author_email', 'user_email', 'email']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
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
      final list = await api.getAdminTicketMessages(_ticketId);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
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
        _error = 'Kon berichten niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _sendReply() async {
    final body = _replyController.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final api = context.read<GymiesApi>();
      await api.addAdminTicketMessage(_ticketId, body);
      _replyController.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bericht verstuurd'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _updateStatus(String status) async {
    try {
      final api = context.read<GymiesApi>();
      // Backend expects: status, priority, reason.
      await api.updateAdminTicket(_ticketId, {
        'status': status,
        'priority': 'medium',
        'reason': status == 'resolved' ? 'Afgehandeld door medewerker' : 'Status gewijzigd',
      });
      if (!mounted) return;
      Navigator.of(context).pop({'status': status});
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showStatusMenu() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Status wijzigen',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 16),
              _StatusOption(
                label: 'Open',
                onTap: () {
                  Navigator.pop(ctx);
                  _updateStatus('new');
                },
              ),
              _StatusOption(
                label: 'In behandeling',
                onTap: () {
                  Navigator.pop(ctx);
                  _updateStatus('in_progress');
                },
              ),
              _StatusOption(
                label: 'Afgehandeld',
                onTap: () {
                  Navigator.pop(ctx);
                  _updateStatus('resolved');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Support',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showStatusMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          _HeaderCard(
            subject: _subject,
            status: _status,
            author: _author,
            authorEmail: _authorEmail,
            ticketId: _ticketId,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(
                        message: _error!,
                        onRetry: _load,
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              'Nog geen berichten',
                              style: GoogleFonts.inter(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              return _MessageBubble(
                                message: _messages[i],
                                str: mapStr,
                              );
                            },
                          ),
          ),
          _ReplyBar(
            controller: _replyController,
            onSend: _sendReply,
            sending: _sending,
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.subject,
    required this.status,
    required this.author,
    required this.authorEmail,
    required this.ticketId,
  });

  final String subject;
  final String status;
  final String author;
  final String authorEmail;
  final String ticketId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: GymiesColors.darkBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subject.isEmpty ? 'Ticket #$ticketId' : subject,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (author.isNotEmpty || authorEmail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              author.isNotEmpty ? '$author${authorEmail.isNotEmpty ? ' · $authorEmail' : ''}' : authorEmail,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _statusLabel(status),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String s) {
    final lower = s.toLowerCase();
    if (lower.contains('open') || lower.contains('new')) return 'Open';
    if (lower.contains('pending') || lower.contains('waiting')) {
      return 'In behandeling';
    }
    if (lower.contains('closed') || lower.contains('resolved')) return 'Afgehandeld';
    return s.isEmpty ? 'Open' : s;
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.str,
  });

  final Map<String, dynamic> message;
  final String Function(Map<String, dynamic>, List<String>) str;

  @override
  Widget build(BuildContext context) {
    final body = str(message, ['body', 'message', 'content', 'text']);
    final author = str(message, ['author', 'sender', 'role', 'sender_role']);
    final createdAt = str(message, ['created_at', 'createdAt', 'date']);
    final isAdmin = author.toLowerCase().contains('admin') ||
        author.toLowerCase().contains('staff') ||
        str(message, ['is_admin', 'from_admin']).toLowerCase() == 'true';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isAdmin) const SizedBox(width: 48),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isAdmin
                    ? GymiesColors.primary.withValues(alpha: 0.25)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (createdAt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      createdAt.length > 19
                          ? createdAt.substring(0, 19).replaceAll('T', ' ')
                          : createdAt,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isAdmin) const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.controller,
    required this.onSend,
    required this.sending,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 3,
                minLines: 1,
                enabled: !sending,
                decoration: InputDecoration(
                  hintText: 'Typ je antwoord...',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: GymiesColors.darkBlue,
                foregroundColor: GymiesColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw proberen'),
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.darkBlue,
                foregroundColor: GymiesColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      onTap: onTap,
    );
  }
}
