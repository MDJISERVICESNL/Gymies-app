import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';

/// Detail-scherm voor een geschil: info-header + chat-berichten + invoerveld.
class ClientDisputeDetailScreen extends StatefulWidget {
  const ClientDisputeDetailScreen({super.key, required this.disputeId});
  final String disputeId;

  @override
  State<ClientDisputeDetailScreen> createState() =>
      _ClientDisputeDetailScreenState();
}

class _ClientDisputeDetailScreenState extends State<ClientDisputeDetailScreen> {
  Map<String, dynamic> _dispute = {};
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  late GymiesApi _api;
  bool _didFirstLoad = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<GymiesApi>();
    if (!_didFirstLoad) {
      _didFirstLoad = true;
      _load();
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _api;
      final data = await api.getDisputeDetail(widget.disputeId);
      if (!mounted) return;
      setState(() {
        _dispute = data;
        _messages = _parseMessages(data['messages']);
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon geschil niet laden.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _parseMessages(dynamic raw) {
    if (raw is List) {
      return raw.map<Map<String, dynamic>>((m) {
        if (m is Map) return Map<String, dynamic>.from(m);
        return <String, dynamic>{};
      }).toList();
    }
    return [];
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final api = _api;
      await api.addDisputeMessage(
        disputeId: widget.disputeId,
        message: text,
      );
      _msgCtrl.clear();
      Haptics.success();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Kon bericht niet versturen.'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String get _status => (_dispute['status'] ?? 'open').toString();
  bool get _isResolved => _status == 'resolved';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: Colors.white,
        title: Text(
          'Geschil',
          style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: GymiesColors.primary),
            )
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    Expanded(child: _buildContent()),
                    if (!_isResolved) _buildInputBar(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: GoogleFonts.sora(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Opnieuw proberen', style: GoogleFonts.sora(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        _buildInfoCard(),
        const SizedBox(height: 16),
        if (_messages.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'BERICHTEN',
              style: GoogleFonts.sora(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ..._messages.map(_buildMessageBubble),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 32, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'Nog geen berichten',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isResolved
                        ? 'Dit geschil is opgelost.'
                        : 'Stuur een bericht om het gesprek te starten.',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_isResolved) _buildResolutionBanner(),
      ],
    );
  }

  Widget _buildInfoCard() {
    final reason = (_dispute['reason'] ?? '').toString();
    final details = (_dispute['details'] ?? '').toString();
    final createdAt = (_dispute['created_at'] ?? '').toString();
    final resolutionType = _dispute['resolution_type']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Row(
            children: [
              _StatusBadge(status: _status),
              const Spacer(),
              if (createdAt.isNotEmpty)
                Text(
                  _formatDate(createdAt),
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Reden
          Text(
            reason,
            style: GoogleFonts.sora(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: GymiesColors.darkBlue,
            ),
          ),

          // Details
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              details,
              style: GoogleFonts.sora(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ],

          // Resolutie
          if (resolutionType != null && _isResolved) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 18, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resolutionLabel(resolutionType),
                      style: GoogleFonts.sora(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isMine = msg['is_mine'] == true;
    final author = (msg['author'] ?? 'Onbekend').toString();
    final text = (msg['message'] ?? '').toString();
    final time = (msg['created_at'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isMine
                  ? GymiesColors.darkBlue
                  : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      author,
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.primary,
                      ),
                    ),
                  ),
                Text(
                  text,
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    color: isMine ? Colors.white : GymiesColors.darkBlue,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(time),
                  style: GoogleFonts.sora(
                    fontSize: 10,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResolutionBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Dit geschil is opgelost. Je kunt geen berichten meer versturen.',
              style: GoogleFonts.sora(
                fontSize: 12,
                color: Colors.green.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        8,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _msgCtrl,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue),
                decoration: InputDecoration(
                  hintText: 'Typ een bericht...',
                  hintStyle: GoogleFonts.sora(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: GymiesColors.primary,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _sending ? null : _sendMessage,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: GymiesColors.darkBlue,
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        size: 20,
                        color: GymiesColors.darkBlue,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  String _resolutionLabel(String? type) {
    switch (type) {
      case 'client':
        return 'Opgelost in het voordeel van de klant';
      case 'trainer':
        return 'Opgelost in het voordeel van de trainer';
      case 'split':
        return 'Opgelost met een compromis (split)';
      default:
        return 'Geschil opgelost';
    }
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.day}-${dt.month}-${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  String _formatTime(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return raw;
    }
  }
}

// ════════════════════════════════════════════════════════════════════
// Status badge widget
// ════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  Color get _color {
    switch (status) {
      case 'open':
        return Colors.orange.shade600;
      case 'in_progress':
        return Colors.blue.shade600;
      case 'resolved':
        return Colors.green.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  String get _label {
    switch (status) {
      case 'open':
        return 'Open';
      case 'in_progress':
        return 'In behandeling';
      case 'resolved':
        return 'Opgelost';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: GoogleFonts.sora(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}
