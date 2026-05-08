import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'trainer_client_dossier_screen.dart';
import 'widgets/gymies_app_bar.dart';

class TrainerDossierBuilderScreen extends StatefulWidget {
  const TrainerDossierBuilderScreen({super.key});

  @override
  State<TrainerDossierBuilderScreen> createState() =>
      _TrainerDossierBuilderScreenState();
}

class _TrainerDossierBuilderScreenState
    extends State<TrainerDossierBuilderScreen> {
  bool _loading = true;
  String? _error;
  String _query = '';
  List<_DossierClientRef> _clients = [];
  List<_DossierOverview> _dossiers = [];

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
      final api = context.read<GymiesApi>();
      final convs = await api.getTrainerConversations();
      final clientsById = <String, _DossierClientRef>{};

      for (final c in convs) {
        final id = c.clientUserId.trim();
        if (id.isEmpty) continue;
        clientsById[id] = _DossierClientRef(
          id: id,
          name: c.clientName.trim().isEmpty ? S.of(context).clientSingle : c.clientName.trim(),
          email: null,
        );
      }

      try {
        final sleeping = await api.getTrainerSleepingClients();
        for (final s in sleeping) {
          final id = mapStr(s, ['client_user_id', 'clientUserId', 'id']).trim();
          if (id.isEmpty) continue;
          clientsById[id] = _DossierClientRef(
            id: id,
            name: mapStr(s, ['name', 'full_name']).trim().isEmpty
                ? (clientsById[id]?.name ?? S.of(context).clientSingle)
                : mapStr(s, ['name', 'full_name']).trim(),
            email: mapStr(s, ['email', 'email_address']).trim().isEmpty
                ? clientsById[id]?.email
                : mapStr(s, ['email', 'email_address']).trim(),
          );
        }
      } catch (_) {
        // Non-blocking; conversation source is primary.
      }

      try {
        final health = await api.getTrainerClientHealthScores();
        for (final h in health) {
          final id = mapStr(h, ['client_user_id', 'clientUserId', 'id']).trim();
          if (id.isEmpty) continue;
          clientsById[id] = _DossierClientRef(
            id: id,
            name: mapStr(h, ['client_name', 'name', 'full_name']).trim().isEmpty
                ? (clientsById[id]?.name ?? S.of(context).clientSingle)
                : mapStr(h, ['client_name', 'name', 'full_name']).trim(),
            email: clientsById[id]?.email,
          );
        }
      } catch (_) {
        // Non-blocking; optional dataset.
      }

      final clients = clientsById.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final overviewList = <_DossierOverview>[];
      for (final c in clients) {
        try {
          final dossier = await api.getTrainerClientDossier(c.id);
          final createdAt = mapStr(dossier, [
            'created_at',
            'createdAt',
            'dossier_created_at',
            'first_entry_at',
            'last_session_entry_at',
            'updated_at',
          ]);
          final hasContent =
              dossier.isNotEmpty &&
              dossier.keys.any(
                (k) =>
                    dossier[k] != null &&
                    dossier[k].toString().trim().isNotEmpty,
              );
          if (hasContent && createdAt.trim().isNotEmpty) {
            overviewList.add(
              _DossierOverview(
                clientId: c.id,
                fullName: c.name,
                createdAt: DateTime.tryParse(createdAt.trim()),
              ),
            );
          } else if (hasContent) {
            overviewList.add(
              _DossierOverview(
                clientId: c.id,
                fullName: c.name,
                createdAt: null,
              ),
            );
          }
        } catch (_) {
          // Skip dossier summary if endpoint/client fails.
        }
      }

      overviewList.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

      if (!mounted) return;
      setState(() {
        _clients = clients;
        _dossiers = overviewList;
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
        _error = S.of(context).konDossierDataNietLaden;
        _loading = false;
      });
    }
  }

  String _dateLabel(DateTime? dt) {
    if (dt == null) return S.of(context).onbekendeDatum;
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
  }

  Widget _stateChip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openClient(_DossierClientRef client) async {
    Haptics.selection();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainerClientDossierScreen(
          clientUserId: client.id,
          clientName: client.name,
          clientEmail: client.email ?? '',
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filteredClients = _clients.where((c) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return c.name.toLowerCase().contains(q) ||
          (c.email ?? '').toLowerCase().contains(q);
    }).toList();
    final dossierByClient = {for (final d in _dossiers) d.clientId: d};

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: S.of(context).dossierOpstellen),
      body: _error != null
          ? Center(child: Text(_error!))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: GymiesColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _stateChip(
                            icon: Icons.people_alt_outlined,
                            label: S.of(context).klantenCount(_clients.length.toString()),
                            bg: Colors.indigo.shade50,
                            fg: Colors.indigo.shade800,
                          ),
                          _stateChip(
                            icon: Icons.folder_open_rounded,
                            label: 'Dossiers: ${_dossiers.length}',
                            bg: Colors.green.shade50,
                            fg: Colors.green.shade800,
                          ),
                          _stateChip(
                            icon: Icons.add_chart_rounded,
                            label: S.of(context).nieuweOpzetKlaar,
                            bg: Colors.blue.shade50,
                            fg: Colors.blue.shade800,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: S.of(context).zoekKlantOpNaamOfEmail,
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    S.of(context).kiesKlantVoorDossier,
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (filteredClients.isEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: ListTile(
                        title: Text(S.of(context).geenKlantenGevonden),
                        subtitle: Text(
                          S.of(context).startEerstEenChatOfSessieMetEenKlant,
                        ),
                      ),
                    )
                  else
                    ...filteredClients.map((c) {
                      final existing = dossierByClient[c.id];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: GymiesColors.darkBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: GymiesColors.darkBlue, fontSize: 14),
                              ),
                            ),
                          ),
                          title: Text(c.name),
                          subtitle: Text(
                            existing == null
                                ? S.of(context).nogGeenDossier
                                : 'Dossier bestaat sinds ${_dateLabel(existing.createdAt)}',
                          ),
                          trailing: existing == null
                              ? _stateChip(
                                  icon: Icons.fiber_new_rounded,
                                  label: 'Nieuw',
                                  bg: Colors.orange.shade100,
                                  fg: Colors.orange.shade800,
                                )
                              : _stateChip(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: 'Bijgewerkt',
                                  bg: Colors.green.shade100,
                                  fg: Colors.green.shade800,
                                ),
                          onTap: () => _openClient(c),
                        ),
                      );
                    }),
                  const SizedBox(height: 18),
                  Text(
                    S.of(context).opgesteldeDossiers,
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_dossiers.isEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: ListTile(
                        title: Text(S.of(context).nogGeenDossiers),
                        subtitle: Text(
                          S.of(context).openEenKlantEnMaakDeEersteSessieentryprogressAan,
                        ),
                      ),
                    )
                  else
                    ..._dossiers.map(
                      (d) => Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: GymiesColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.folder_open_rounded, color: GymiesColors.darkBlue, size: 20),
                          ),
                          title: Text(d.fullName),
                          subtitle: Text(
                            'Aangemaakt: ${_dateLabel(d.createdAt)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            final match = _clients.where(
                              (c) => c.id == d.clientId,
                            );
                            if (match.isEmpty) return;
                            _openClient(match.first);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _DossierClientRef {
  const _DossierClientRef({required this.id, required this.name, this.email});
  final String id;
  final String name;
  final String? email;
}

class _DossierOverview {
  const _DossierOverview({
    required this.clientId,
    required this.fullName,
    required this.createdAt,
  });
  final String clientId;
  final String fullName;
  final DateTime? createdAt;
}
