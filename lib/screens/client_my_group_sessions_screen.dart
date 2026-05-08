

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../utils/haptics.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'client_group_session_detail_screen.dart';
import 'widgets/trainer_state_views.dart';
/// Mijn inschrijvingen groepslessen – voor ingelogde klanten.
class ClientMyGroupSessionsScreen extends StatefulWidget {
  const ClientMyGroupSessionsScreen({super.key});

  @override
  State<ClientMyGroupSessionsScreen> createState() =>
      _ClientMyGroupSessionsScreenState();
}

class _ClientMyGroupSessionsScreenState extends State<ClientMyGroupSessionsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _registrations = [];
  bool _didFirstLoad = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didFirstLoad) {
      _didFirstLoad = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<GymiesApi>().getMyGroupRegistrations();
      if (!mounted) return;
      setState(() {
        _registrations = list;
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
        _error = S.of(context).konInschrijvingenNietLaden;
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
                        S.of(context).mijnGroepslessen,
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
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
              child: _registrations.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            children: [
                              const SizedBox(height: 64),
                              Center(
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: GymiesColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(
                                    Icons.event_available_outlined,
                                    size: 34,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                S.of(context).geenInschrijvingen,
                                style: GoogleFonts.sora(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: GymiesColors.darkBlue,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                S.of(context).jeHebtJeNogNietIngeschrevenVoorEenGroepsles,
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
                            itemCount: _registrations.length,
                            itemBuilder: (_, i) {
                              final r = _registrations[i];
                              final id = mapStr(r, [
                                'group_session_id',
                                'groupSessionId',
                              ]);
                              final key = ValueKey<String>(id.isNotEmpty ? id : 'reg_$i');
                              final rawTitle = mapStr(r, [
                                'group_session_title',
                                'title',
                                'name',
                              ]);
                              final displayTitle = rawTitle.isEmpty ? S.of(context).groepsles : rawTitle;
                              final startsAt = DateTime.tryParse(mapStr(r, [
                                'scheduled_at',
                                'scheduledAt',
                                'starts_at',
                                'startsAt',
                                'start_at',
                              ]));
                              final status = mapStr(r, [
                                'status',
                                'payment_status',
                              ]).toLowerCase();
                              final isConfirmed = status == 'paid' || status == 'confirmed';
                              final isPast = startsAt != null && startsAt.isBefore(DateTime.now());

                              return Padding(
                                key: key,
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
                                            color: Colors.black.withOpacity(0.05),
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
                                                  color: isPast
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
                                                        color: isPast
                                                            ? Colors.grey.shade500
                                                            : GymiesColors.darkBlue,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${startsAt.day}',
                                                      style: GoogleFonts.sora(
                                                        fontSize: 22,
                                                        fontWeight: FontWeight.w700,
                                                        color: isPast
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
                                                    displayTitle,
                                                    style: GoogleFonts.sora(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w700,
                                                      color: GymiesColors.darkBlue,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  if (startsAt != null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}',
                                                      style: GoogleFonts.sora(
                                                        fontSize: 12,
                                                        color: Colors.grey.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                  if (status.isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isConfirmed
                                                            ? Colors.green.withOpacity(0.12)
                                                            : Colors.orange.withOpacity(0.12),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        isConfirmed ? 'Bevestigd' : status,
                                                        style: GoogleFonts.sora(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                          color: isConfirmed
                                                              ? Colors.green.shade700
                                                              : Colors.orange.shade700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
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
