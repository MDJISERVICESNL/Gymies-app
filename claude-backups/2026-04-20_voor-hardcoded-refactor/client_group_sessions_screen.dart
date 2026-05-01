import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'client_group_session_detail_screen.dart';
import 'client_my_group_sessions_screen.dart';
import 'login_register_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Publieke lijst groepslessen – voor iedereen (ook niet ingelogd).
class ClientGroupSessionsScreen extends StatefulWidget {
  const ClientGroupSessionsScreen({super.key});

  @override
  State<ClientGroupSessionsScreen> createState() =>
      _ClientGroupSessionsScreenState();
}

class _ClientGroupSessionsScreenState extends State<ClientGroupSessionsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = [];
  final DateTime _filterFrom = DateTime.now();
  final DateTime _filterTo = DateTime.now().add(const Duration(days: 60));

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
      final list = await context.read<GymiesApi>().getPublicGroupSessions(
            from: _filterFrom,
            to: _filterTo,
          );
      if (!mounted) return;
      setState(() {
        _sessions = list;
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
        _error = 'Kon groepslessen niet laden.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Groepslessen',
        actions: [
          if (auth.isLoggedIn && !auth.isTrainer && !auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.event_available_rounded),
              tooltip: 'Mijn inschrijvingen',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ClientMyGroupSessionsScreen(),
                  ),
                );
                if (mounted) _load();
              },
            ),
        ],
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _sessions.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 48),
                            Icon(
                              Icons.groups_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Geen groepslessen gevonden',
                              style: GoogleFonts.fjallaOne(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.darkBlue,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                              'Er zijn momenteel geen groepslessen gepland in de gekozen periode.',
                              style: TextStyle(color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _sessions.length,
                          itemBuilder: (_, i) {
                            final s = _sessions[i];
                            final id = mapStr(s, ['id', 'group_session_id']);
                            final rawTitle = mapStr(s, ['title', 'name']);
                            final title = rawTitle.isEmpty ? 'Groepsles' : rawTitle;
                            final startsAt = DateTime.tryParse(mapStr(s, [
                              'starts_at',
                              'startsAt',
                              'start_at',
                              'date',
                            ])) ?? DateTime.now();
                            final trainerName =
                                mapStr(s, ['trainer_name', 'trainerName', 'name']);
                            final capacity =
                                int.tryParse(mapStr(s, ['capacity', 'max_participants'])) ?? 0;
                            final enrolled =
                                int.tryParse(mapStr(s, ['enrolled_count', 'participants_count'])) ?? 0;
                            final city = mapStr(s, ['city', 'location']);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '${startsAt.day}/${startsAt.month}/${startsAt.year} ${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (trainerName.isNotEmpty)
                                      Text(trainerName),
                                    if (city.isNotEmpty) Text(city),
                                    if (capacity > 0)
                                      Text(
                                        '$enrolled / $capacity deelnemers',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: id.isEmpty
                                    ? null
                                    : () async {
                                        if (!auth.isLoggedIn ||
                                            auth.isTrainer ||
                                            auth.isAdmin) {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const LoginRegisterScreen(),
                                            ),
                                          );
                                          if (mounted) _load();
                                          return;
                                        }
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ClientGroupSessionDetailScreen(
                                              groupSessionId: id,
                                            ),
                                          ),
                                        );
                                        if (mounted) _load();
                                      },
                              ),
                            );
                          },
                        ),
        ),
    );
  }
}
