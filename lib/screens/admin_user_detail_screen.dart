import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme/gymies_theme.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';

/// Admin gebruiker detail – profiel en notities.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({
    super.key,
    required this.userId,
    this.initialUser,
  });

  final String userId;
  final Map<String, dynamic>? initialUser;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  Map<String, dynamic> _user = {};
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user = Map<String, dynamic>.from(widget.initialUser ?? {});
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final results = await Future.wait([
        api.getAdminUserDetail(widget.userId),
        api.getAdminUserNotes(widget.userId),
      ]);
      if (!mounted) return;
      final user = results[0] is Map<String, dynamic>
          ? results[0] as Map<String, dynamic>
          : <String, dynamic>{};
      final notes = results[1] is List
          ? (results[1] as List)
              .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _user = user;
        _notes = notes;
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
        _error = 'Kon gebruiker niet laden.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = mapStr(_user, ['display_name', 'name']);
    final email = mapStr(_user, ['email']);
    final role = mapStr(_user, ['role']);
    final status = mapStr(_user, ['status', 'account_status']);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: name.isNotEmpty ? name : email,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () {
              Haptics.selection();
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildProfileCard(name, email, role, status),
                        const SizedBox(height: 24),
                        _buildSectionTitle('Admin notities'),
                        const SizedBox(height: 8),
                        _buildNotesList(),
                      ],
                    ),
                  ),
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
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Er ging iets mis.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade800),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Haptics.light();
                _load();
              },
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

  Widget _buildProfileCard(
    String name,
    String email,
    String role,
    String status,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: GymiesColors.primary.withValues(alpha: 0.3),
                  child: Text(
                    (name.isNotEmpty ? name[0] : email.isNotEmpty ? email[0] : '?')
                        .toUpperCase(),
                    style: GoogleFonts.sora(
                      fontSize: 28,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'Geen naam',
                        style: GoogleFonts.sora(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (role.isNotEmpty || status.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (role.isNotEmpty)
                              _Chip(label: role),
                            if (status.isNotEmpty)
                              _Chip(
                                label: status,
                                color: status.toLowerCase().contains('active')
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.sora(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: GymiesColors.darkBlue,
      ),
    );
  }

  Widget _buildNotesList() {
    if (_notes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Geen notities',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ),
      );
    }
    return Column(
      children: _notes.map((n) {
        final body = mapStr(n, ['body', 'content', 'note', 'text']);
        final author = mapStr(n, ['author_name', 'created_by', 'author']);
        final createdAt = mapStr(n, ['created_at', 'createdAt']);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              body.isNotEmpty ? body : '(Lege notitie)',
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: (author.isNotEmpty || createdAt.isNotEmpty)
                ? Text(
                    [author, createdAt].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? GymiesColors.primary).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color ?? GymiesColors.darkBlue,
        ),
      ),
    );
  }
}
