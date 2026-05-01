import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/ui_constants.dart';
import '../theme/gymies_theme.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'login_register_screen.dart';
import 'admin_ticket_detail_screen.dart';
import 'admin_fee_management_screen.dart';
import 'admin_subscription_features_screen.dart';
import 'admin_user_detail_screen.dart';
import 'admin_messages_screen.dart';

/// Control Tower – admin dashboard voor medewerkers.
/// Mobiel-first UX: snel overzicht, zoeken en support afhandelen.
class ControlTowerScreen extends StatefulWidget {
  const ControlTowerScreen({super.key});

  @override
  State<ControlTowerScreen> createState() => _ControlTowerScreenState();
}

class _ControlTowerScreenState extends State<ControlTowerScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _overview = {};
  Map<String, dynamic> _inbox = {};
  List<Map<String, dynamic>> _tickets = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final api = context.read<GymiesApi>();
      final apiClient = context.read<ApiClient>();
      if (auth.isLoggedIn && auth.token != null && auth.token!.isNotEmpty) {
        apiClient.setAuthToken(auth.token);
      }
      // Graceful degradation: elke call apart zodat partial failures OK zijn
      Map<String, dynamic> overview = {};
      Map<String, dynamic> inbox = {};
      List<Map<String, dynamic>> tickets = [];

      try {
        final res = await api.getAdminOverview();
        overview = _asMap(res) ?? {};
      } catch (e) {
        if (kDebugMode) debugPrint('[ControlTower] Overview laden mislukt: $e');
      }

      try {
        final res = await api.getAdminInbox();
        inbox = _asMap(res) ?? {};
      } catch (e) {
        if (kDebugMode) debugPrint('[ControlTower] Inbox laden mislukt: $e');
      }

      try {
        final res = await api.getAdminTickets(status: 'open');
        if (res is List) {
          tickets = res.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[ControlTower] Tickets laden mislukt: $e');
      }

      if (!mounted) return;
      setState(() {
        _overview = overview;
        _inbox = inbox;
        _tickets = List<Map<String, dynamic>>.from(tickets);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon Control Tower niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _doSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _searchQuery = q);
    try {
      final res = await context.read<GymiesApi>().adminSearch(query: q);
      final raw = res['data'] ?? res['users'] ?? res['results'] ?? res;
      final list = raw is List ? raw : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _searchResults = list
            .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
            .toList();
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _searchResults = []);
    }
  }

  void _openTicket(Map<String, dynamic> ticket) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AdminTicketDetailScreen(ticket: ticket),
      ),
    ).then((_) => _load());
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiConstants.darkNavyBackground,
      appBar: AppBar(
        backgroundColor: UiConstants.darkNavyBackground,
        elevation: 0,
        title: Text(
          'Control Tower',
          style: GoogleFonts.sora(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: GymiesColors.primary,
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: GymiesColors.primary),
            color: UiConstants.darkNavyCard,
            onSelected: (v) {
              Haptics.selection();
              if (v == 'features') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminSubscriptionFeaturesScreen(),
                  ),
                );
              } else if (v == 'fees') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminFeeManagementScreen(),
                  ),
                );
              } else if (v == 'logout') {
                Haptics.heavy();
                _logout();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'features',
                child: Row(
                  children: [
                    Icon(Icons.tune, color: Colors.white70, size: 20),
                    SizedBox(width: 12),
                    Text('Abonnement features'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'fees',
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined, color: Colors.white70, size: 20),
                    SizedBox(width: 12),
                    Text('Fee-beheer'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.white70),
                    SizedBox(width: 12),
                    Text('Uitloggen'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: GymiesColors.primary))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: GymiesColors.primary,
                  backgroundColor: UiConstants.blueGrayAccent,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildWelcomeHeader(),
                        const SizedBox(height: 20),
                        _buildMessagesCard(),
                        const SizedBox(height: 20),
                        _buildSearch(),
                        const SizedBox(height: 20),
                        _buildQuickStats(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('Open support tickets'),
                        const SizedBox(height: 12),
                        _buildTicketsList(),
                        if (_searchQuery.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildSectionTitle('Zoekresultaten'),
                          const SizedBox(height: 12),
                          _buildSearchResults(),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    final msg = _error ?? 'Er ging iets mis.';
    final isSessionError = msg.toLowerCase().contains('sessie') ||
        msg.toLowerCase().contains('verlopen');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            if (isSessionError)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Log opnieuw in'),
                  style: FilledButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    foregroundColor: GymiesColors.darkBlue,
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw proberen'),
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

  Widget _buildMessagesCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Haptics.selection();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AdminMessagesScreen(),
            ),
          ).then((_) => _load());
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
          color: UiConstants.blueGrayAccent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: GymiesColors.primary.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: GymiesColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Berichtencentrum',
                      style: GoogleFonts.sora(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tickets van klanten en trainers beantwoorden',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Goedemorgen' : hour < 18 ? 'Goedemiddag' : 'Goedenavond';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: GoogleFonts.sora(
            fontSize: 18,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Overzicht voor vandaag',
          style: GoogleFonts.sora(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _buildSearch() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Zoek gebruiker (e-mail, naam)',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
              prefixIcon: const Icon(Icons.search, color: GymiesColors.primary),
              filled: true,
              fillColor: UiConstants.blueGrayAccent,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: const TextStyle(color: Colors.white),
            onSubmitted: (_) => _doSearch(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _loading ? null : () {
            Haptics.selection();
            _doSearch();
          },
          icon: const Icon(Icons.search),
          style: IconButton.styleFrom(
            backgroundColor: GymiesColors.primary,
            foregroundColor: GymiesColors.darkBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    final overviewOpen = _overview['open_tickets_count'] ?? _overview['open_tickets'] ?? _overview['tickets_open'];
    final openCount = overviewOpen is int ? overviewOpen : _tickets.length;
    final inboxItems = _inbox['items'] ?? _inbox['tasks'] ?? [];
    final inboxCount = inboxItems is List ? inboxItems.length : 0;
    final totalUsers = _overview['users_count'] ?? _overview['total_users'];
    final usersCount = totalUsers is int ? totalUsers : (totalUsers is num ? totalUsers.toInt() : null);
    final moderationCount = _overview['moderation_pending'] ?? _overview['profiles_pending'];
    final modCount = moderationCount is int ? moderationCount : (moderationCount is num ? moderationCount.toInt() : null);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.support_agent,
                label: 'Open tickets',
                value: '$openCount',
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.inbox,
                label: 'Actiepunten',
                value: '$inboxCount',
                color: Colors.blue,
              ),
            ),
          ],
        ),
        if (usersCount != null || modCount != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (usersCount != null)
                Expanded(
                  child: _StatCard(
                    icon: Icons.people,
                    label: 'Gebruikers',
                    value: _formatNumber(usersCount),
                    color: Colors.green,
                  ),
                ),
              if (usersCount != null && modCount != null) const SizedBox(width: 12),
              if (modCount != null)
                Expanded(
                  child: _StatCard(
                    icon: Icons.person_search,
                    label: 'Moderatie',
                    value: '$modCount',
                    color: Colors.amber,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.sora(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTicketsList() {
    if (_tickets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
decoration: BoxDecoration(
        color: UiConstants.blueGrayAccent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GymiesColors.primary.withValues(alpha: 0.2)),
      ),
        child: Center(
          child: Text(
            'Geen open tickets',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ),
      );
    }
    return Column(
      children: _tickets.map((t) => _TicketCard(
            ticket: t,
            onTap: () => _openTicket(t),
          )).toList(),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
decoration: BoxDecoration(
        color: UiConstants.blueGrayAccent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GymiesColors.primary.withValues(alpha: 0.2)),
      ),
        child: Center(
          child: Text(
            'Geen resultaten voor "$_searchQuery"',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ),
      );
    }
    return Column(
      children: _searchResults.map((u) {
        final name = mapStr(u, ['name', 'display_name', 'email']);
        final email = mapStr(u, ['email']);
        final userId = mapStr(u, ['id', 'user_id']);
        return Card(
          color: UiConstants.blueGrayAccent,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: GymiesColors.primary.withValues(alpha: 0.2)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: GymiesColors.primary.withValues(alpha: 0.35),
              child: const Icon(Icons.person, color: GymiesColors.primary),
            ),
            title: Text(
              name.isNotEmpty ? name : email,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: email.isNotEmpty && name != email
                ? Text(email, style: TextStyle(color: Colors.white70))
                : null,
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
            onTap: () {
              Haptics.selection();
              if (userId.isNotEmpty) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminUserDetailScreen(
                      userId: userId,
                      initialUser: u,
                    ),
                  ),
                ).then((_) => _load());
              }
            },
          ),
        );
      }).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: UiConstants.blueGrayAccent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subject = mapStr(ticket, ['subject', 'title', 'topic']);
    final author = mapStr(ticket, ['author_name', 'user_name', 'author', 'from']);
    final createdAt = mapStr(ticket, ['created_at', 'createdAt']);
    final status = mapStr(ticket, ['status', 'state']);

    final dateStr = _formatDate(createdAt);
    return Card(
      color: UiConstants.blueGrayAccent,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: GymiesColors.primary.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
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
                      subject.isNotEmpty ? subject : 'Geen onderwerp',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        author,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
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
                    color: GymiesColors.primary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
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
