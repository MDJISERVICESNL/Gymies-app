import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/ui_constants.dart';
import '../theme/gymies_theme.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'admin_ticket_detail_screen.dart';
import '../l10n/generated/app_localizations.dart';

/// Admin berichtencentrum – tickets van klanten en trainers.
/// Tabs: Klanten | Trainers. Alleen open/pending tickets. Afgehandeld verdwijnt uit lijst.
class AdminMessagesScreen extends StatefulWidget {
  const AdminMessagesScreen({super.key});

  @override
  State<AdminMessagesScreen> createState() => _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends State<AdminMessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clientTickets = [];
  List<Map<String, dynamic>> _trainerTickets = [];

  static const _openStatuses = ['open', 'pending', 'new', 'in_progress'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isOpen(Map<String, dynamic> t) {
    final s = mapStr(t, ['status', 'state']).toLowerCase();
    return s.isEmpty || _openStatuses.any((x) => s.contains(x));
  }

  bool _isFromTrainer(Map<String, dynamic> t) {
    final role = mapStr(t, ['author_role', 'user_role', 'role', 'type']).toLowerCase();
    // Check for common trainer role strings to avoid context.read during build
    return role.contains('trainer') || role.contains('coach') || role == 'pro';
  }

  bool _isFromClient(Map<String, dynamic> t) {
    return !_isFromTrainer(t);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final all = await api.getAdminTickets();
      if (!mounted) return;
      final open = (all as List)
          .map((e) => e as Map<String, dynamic>)
          .where(_isOpen)
          .toList();
      final client = open.where(_isFromClient).toList();
      final trainer = open.where(_isFromTrainer).toList();
      setState(() {
        _clientTickets = client;
        _trainerTickets = trainer;
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
        _error = S.of(context).konTicketsNietLaden;
        _loading = false;
      });
    }
  }

  void _openTicket(Map<String, dynamic> ticket) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AdminTicketDetailScreen(ticket: ticket),
          ),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiConstants.darkNavyBackground,
      appBar: AppBar(
        backgroundColor: UiConstants.darkNavyBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GymiesColors.primary),
          onPressed: () {
            Haptics.selection();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          S.of(context).berichtencentrum,
          style: GoogleFonts.sora(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: GymiesColors.primary),
            onPressed: _loading ? null : () {
              Haptics.selection();
              _load();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GymiesColors.primary,
          indicatorWeight: 4,
          labelColor: GymiesColors.primary,
          unselectedLabelColor: Colors.white54,
          labelStyle: GoogleFonts.sora(fontSize: 16),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline, size: 20),
                  const SizedBox(width: 8),
                  Text(S.of(context).klanten),
                  if (_clientTickets.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_clientTickets.length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fitness_center, size: 20),
                  const SizedBox(width: 8),
                  Text(S.of(context).trainers),
                  if (_trainerTickets.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_trainerTickets.length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: GymiesColors.primary),
            )
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTicketList(_clientTickets, S.of(context).clientSingle),
                    _buildTicketList(_trainerTickets, S.of(context).trainer),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _error ?? S.of(context).erGingIetsMis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Haptics.light();
                _load();
              },
              icon: const Icon(Icons.refresh),
              label: Text(S.of(context).opnieuwProberen),
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketList(List<Map<String, dynamic>> tickets, String roleLabel) {
    if (tickets.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: GymiesColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: Colors.white.withOpacity(0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'Geen open tickets van $roleLabel',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nieuwe tickets van ${roleLabel.toLowerCase()} verschijnen hier.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: GymiesColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tickets.length,
        itemBuilder: (_, i) => _TicketCard(
          ticket: tickets[i],
          onTap: () => _openTicket(tickets[i]),
          str: mapStr,
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.onTap,
    required this.str,
  });

  final Map<String, dynamic> ticket;
  final VoidCallback onTap;
  final String Function(Map<String, dynamic>, List<String>) str;

  @override
  Widget build(BuildContext context) {
    final subject = str(ticket, ['subject', 'title', 'topic']);
    final author = str(ticket, [
      'author_name',
      'user_name',
      'client_name',
      S.of(context).trainername,
      'created_by_name',
    ]);
    final email = str(ticket, ['author_email', 'user_email', 'email']);
    final createdAt = str(ticket, ['created_at', 'createdAt']);
    final status = str(ticket, ['status', 'state']);
    final preview = str(ticket, ['last_message', 'preview', 'first_message']);

    final dateStr = _formatDate(createdAt);

    return Card(
      color: UiConstants.darkNavyCard,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.isNotEmpty ? subject : S.of(context).geenOnderwerp,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (author.isNotEmpty || email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        author.isNotEmpty
                            ? (email.isNotEmpty ? '$author · $email' : author)
                            : email,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview.length > 80 ? '${preview.substring(0, 80)}…' : preview,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (status.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: const TextStyle(
                      color: GymiesColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String s) {
    final lower = s.toLowerCase();
    if (lower.contains('open') || lower.contains('new')) return 'Open';
    if (lower.contains('pending') || lower.contains('waiting')) return S.of(context).statusInBehandeling;
    if (lower.contains('closed') || lower.contains('resolved')) return 'Afgehandeld';
    return s.isEmpty ? 'Open' : s;
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length > 16 ? raw.substring(0, 16) : raw;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) {
      return 'Vandaag ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (d == yesterday) {
      return 'Gisteren ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
