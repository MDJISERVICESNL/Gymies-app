import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/timing_constants.dart';
import '../utils/haptics.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'client_group_session_detail_screen.dart';
import 'client_my_group_sessions_screen.dart';
import 'login_register_screen.dart';
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
  final DateTime _filterTo = DateTime.now().add(TimingConstants.groupSessionFilterRange);

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

  static String _monthAbbr(int month) {
    const months = [
      'JAN', 'FEB', 'MRT', 'APR', 'MEI', 'JUN',
      'JUL', 'AUG', 'SEP', 'OKT', 'NOV', 'DEC',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Groepslessen',
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (auth.isLoggedIn && !auth.isTrainer && !auth.isAdmin)
                      IconButton(
                        icon: const Icon(Icons.event_available_rounded, color: Colors.white),
                        tooltip: 'Mijn inschrijvingen',
                        onPressed: () async {
                          Haptics.selection();
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
              ),
            ),
          ),
          Expanded(
            child: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _sessions.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          children: [
                            const SizedBox(height: 64),
                            Center(
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: GymiesColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.groups_outlined,
                                  size: 34,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Geen groepslessen gevonden',
                              style: GoogleFonts.sora(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.darkBlue,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Er zijn momenteel geen groepslessen gepland in de gekozen periode.',
                              style: GoogleFonts.sora(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
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
                            ]));
                            final trainerName =
                                mapStr(s, ['trainer_name', 'trainerName', 'name']);
                            final capacity =
                                int.tryParse(mapStr(s, ['capacity', 'max_participants'])) ?? 0;
                            final enrolled =
                                int.tryParse(mapStr(s, ['enrolled_count', 'participants_count'])) ?? 0;
                            final city = mapStr(s, ['city', 'location']);
                            final pricePpCents = int.tryParse(
                                    mapStr(s, ['price_per_participant_cents'])) ??
                                0;
                            final priceCents =
                                int.tryParse(mapStr(s, ['price_cents'])) ?? 0;
                            final displayCents = pricePpCents > 0
                                ? pricePpCents
                                : (capacity > 0 && priceCents > 0
                                    ? (priceCents / capacity).ceil()
                                    : priceCents);
                            final confirmationStatus = mapStr(s, ['confirmation_status']);
                            final minP = int.tryParse(mapStr(s, ['min_participants'])) ?? 1;
                            final isFull = capacity > 0 && enrolled >= capacity;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: id.isEmpty
                                      ? null
                                      : () async {
                                          Haptics.selection();
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
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 12,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          // ── Date block ──
                                          if (startsAt != null)
                                            Container(
                                              width: 50,
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isFull
                                                    ? Colors.grey.shade100
                                                    : GymiesColors.primary,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    _monthAbbr(startsAt.month),
                                                    style: GoogleFonts.sora(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: isFull
                                                          ? Colors.grey.shade500
                                                          : GymiesColors.darkBlue,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${startsAt.day}',
                                                    style: GoogleFonts.sora(
                                                      fontSize: 22,
                                                      fontWeight: FontWeight.w700,
                                                      color: isFull
                                                          ? Colors.grey.shade600
                                                          : GymiesColors.darkBlue,
                                                      height: 1.1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (startsAt != null)
                                            const SizedBox(width: 12),
                                          // ── Info ──
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: GoogleFonts.sora(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: GymiesColors.darkBlue,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    if (startsAt != null)
                                                      Text(
                                                        '${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}',
                                                        style: GoogleFonts.sora(
                                                          fontSize: 12,
                                                          color: Colors.grey.shade600,
                                                        ),
                                                      ),
                                                    if (trainerName.isNotEmpty) ...[
                                                      Text(
                                                        ' · ',
                                                        style: GoogleFonts.sora(
                                                          fontSize: 12,
                                                          color: Colors.grey.shade400,
                                                        ),
                                                      ),
                                                      Flexible(
                                                        child: Text(
                                                          trainerName,
                                                          style: GoogleFonts.sora(
                                                            fontSize: 12,
                                                            color: Colors.grey.shade600,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    // Plaatsen badge
                                                    if (capacity > 0)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: isFull
                                                              ? Colors.red.withValues(alpha: 0.12)
                                                              : Colors.green.withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          isFull
                                                              ? 'Vol'
                                                              : '$enrolled / $capacity plaatsen',
                                                          style: GoogleFonts.sora(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: isFull
                                                                ? Colors.red.shade700
                                                                : Colors.green.shade700,
                                                          ),
                                                        ),
                                                      ),
                                                    // Price badge
                                                    if (displayCents > 0) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: GymiesColors.primary.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          '€${(displayCents / 100).toStringAsFixed(2).replaceAll('.', ',')} p.p.',
                                                          style: GoogleFonts.sora(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: GymiesColors.darkBlue,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                    // Crowdfund status badge
                                                    if (confirmationStatus == 'confirmed') ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          'Gaat door!',
                                                          style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                                                        ),
                                                      ),
                                                    ] else if (confirmationStatus == 'open' && minP > 1) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange.withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          '$enrolled/$minP nodig',
                                                          style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
                                                        ),
                                                      ),
                                                    ],
                                                    if (city.isNotEmpty) ...[
                                                      const SizedBox(width: 6),
                                                      Icon(
                                                        Icons.location_on_outlined,
                                                        size: 13,
                                                        color: Colors.grey.shade500,
                                                      ),
                                                      const SizedBox(width: 2),
                                                      Flexible(
                                                        child: Text(
                                                          city,
                                                          style: GoogleFonts.sora(
                                                            fontSize: 11,
                                                            color: Colors.grey.shade500,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 20,
                                            color: Colors.grey.shade400,
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
