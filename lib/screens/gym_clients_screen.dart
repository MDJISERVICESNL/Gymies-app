import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'gym_churn_report_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';
import '../l10n/generated/app_localizations.dart';

/// Gym klanten overzicht — zoeken, stats, churn-indicator, detail bottom sheet.
class GymClientsScreen extends StatefulWidget {
  const GymClientsScreen({super.key});

  @override
  State<GymClientsScreen> createState() => _GymClientsScreenState();
}

class _GymClientsScreenState extends State<GymClientsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchController = TextEditingController();
  String _sortBy = 'name'; // name, recent, bookings

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<GymiesApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.getGymClients();
      if (!mounted) return;
      setState(() {
        _clients = list;
        _loading = false;
      });
      _applyFilters();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = S.of(context).konKlantenNietLaden;
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    var result = _clients.where((c) {
      if (query.isEmpty) return true;
      final name = mapStr(c, ['name', 'display_name']).toLowerCase();
      final email = mapStr(c, ['email']).toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();

    // Sorteer
    switch (_sortBy) {
      case 'recent':
        result.sort((a, b) {
          final dtA = DateTime.tryParse(mapStr(a, ['last_booking', 'last_visit', 'last_session_at'])) ?? DateTime(2000);
          final dtB = DateTime.tryParse(mapStr(b, ['last_booking', 'last_visit', 'last_session_at'])) ?? DateTime(2000);
          return dtB.compareTo(dtA);
        });
        break;
      case 'bookings':
        result.sort((a, b) {
          final countA = mapInt(a, ['bookings_count', 'total_bookings', 'sessions_count']);
          final countB = mapInt(b, ['bookings_count', 'total_bookings', 'sessions_count']);
          return countB.compareTo(countA);
        });
        break;
      default: // name
        result.sort((a, b) {
          final nameA = mapStr(a, ['name', 'display_name']).toLowerCase();
          final nameB = mapStr(b, ['name', 'display_name']).toLowerCase();
          return nameA.compareTo(nameB);
        });
    }

    setState(() => _filtered = result);
  }

  void _showClientDetail(Map<String, dynamic> client) {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClientDetailSheet(client: client),
    );
  }

  void _openChurnReport() {
    final user = context.read<AuthService>().user ?? {};
    final orgId = user['organisation_id']?.toString();
    if (orgId == null || orgId.isEmpty || orgId == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).geenOrganisatieGevonden),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GymChurnReportScreen(
        gymId: orgId,
        gymName: mapStr(user, ['name', 'display_name']),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: S.of(context).klanten,
        actions: [
          GymiesAppBarAction(
            icon: Icons.trending_down_rounded,
            onTap: _openChurnReport,
            tooltip: S.of(context).churnRapport,
          ),
        ],
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: Column(
          children: [
            // ── Zoekbalk ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: S.of(context).zoekKlant,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: GymiesColors.darkBlue, width: 1.5),
                  ),
                ),
              ),
            ),

            // ── Sort chips ────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _SortChip(
                    label: S.of(context).naam,
                    icon: Icons.sort_by_alpha_rounded,
                    selected: _sortBy == 'name',
                    onTap: () => setState(() { _sortBy = 'name'; _applyFilters(); }),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: S.of(context).recenteActiviteit,
                    icon: Icons.schedule_rounded,
                    selected: _sortBy == 'recent',
                    onTap: () => setState(() { _sortBy = 'recent'; _applyFilters(); }),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: S.of(context).bookings,
                    icon: Icons.event_rounded,
                    selected: _sortBy == 'bookings',
                    onTap: () => setState(() { _sortBy = 'bookings'; _applyFilters(); }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Client count ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} ${_filtered.length == 1 ? 'klant' : S.of(context).klanten2}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Lijst ────────────────────────────────────────
            Expanded(
              child: _filtered.isEmpty && !_loading
                  ? ListView(
                      children: [
                        TrainerEmptyState(
                          icon: Icons.person_outline_rounded,
                          title: _searchController.text.isNotEmpty
                              ? S.of(context).geenResultaten
                              : S.of(context).geenKlanten,
                          subtitle: _searchController.text.isNotEmpty
                              ? S.of(context).probeerAndereZoektermen
                              : S.of(context).erZijnNogGeenKlantenGekoppeld,
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: GymiesColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _ClientCard(
                          client: _filtered[i],
                          onTap: () => _showClientDetail(_filtered[i]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sort chip ───────────────────────────────────────────────────────
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? GymiesColors.darkBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? GymiesColors.darkBlue : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Client card ─────────────────────────────────────────────────────
class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.client,
    required this.onTap,
  });

  final Map<String, dynamic> client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = mapStr(client, ['name', 'display_name']);
    final email = mapStr(client, ['email']);
    final bookingsCount = mapInt(client, ['bookings_count', 'total_bookings', 'sessions_count']);
    final lastVisitRaw = mapStr(client, ['last_booking', 'last_visit', 'last_session_at']);
    final lastVisit = DateTime.tryParse(lastVisitRaw);
    final churnScore = client['churn_score'] ?? client['risk_score'];

    final initials = name.isNotEmpty
        ? name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    // Churn risico indicator
    double? churnValue;
    if (churnScore is num) churnValue = churnScore.toDouble();
    else if (churnScore != null) churnValue = double.tryParse(churnScore.toString());

    Color? churnColor;
    String? churnLabel;
    if (churnValue != null) {
      if (churnValue >= 70) {
        churnColor = Colors.red.shade500;
        churnLabel = S.of(context).hoogRisico;
      } else if (churnValue >= 40) {
        churnColor = Colors.amber.shade700;
        churnLabel = S.of(context).middenRisico;
      } else {
        churnColor = Colors.green.shade600;
        churnLabel = S.of(context).laagRisico;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundColor: GymiesColors.primary.withOpacity(0.15),
                  child: Text(
                    initials,
                    style: GoogleFonts.sora(
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.accent,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name.isNotEmpty ? name : email,
                              style: GoogleFonts.sora(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: GymiesColors.darkBlue,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Churn risico badge
                          if (churnColor != null && churnLabel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: churnColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                churnLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: churnColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Boekingen count
                          if (bookingsCount > 0) ...[
                            Icon(Icons.event_rounded, size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 3),
                            Text(
                              '$bookingsCount ${bookingsCount == 1 ? 'boeking' : S.of(context).boekingen2}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                          // Laatste bezoek
                          if (lastVisit != null) ...[
                            if (bookingsCount > 0)
                              Text(' · ', style: TextStyle(color: Colors.grey.shade400)),
                            Icon(Icons.schedule_rounded, size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 3),
                            Text(
                              '${lastVisit.day}/${lastVisit.month}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                          if (bookingsCount == 0 && lastVisit == null)
                            Text(
                              email,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Client detail bottom sheet ──────────────────────────────────────
class _ClientDetailSheet extends StatelessWidget {
  const _ClientDetailSheet({required this.client});
  final Map<String, dynamic> client;

  @override
  Widget build(BuildContext context) {
    final name = mapStr(client, ['name', 'display_name']);
    final email = mapStr(client, ['email']);
    final phone = mapStr(client, ['phone', 'phone_number']);
    final bookingsCount = mapInt(client, ['bookings_count', 'total_bookings', 'sessions_count']);
    final lastVisitRaw = mapStr(client, ['last_booking', 'last_visit', 'last_session_at']);
    final lastVisit = DateTime.tryParse(lastVisitRaw);
    final joinedRaw = mapStr(client, ['created_at', 'joined_at']);
    final joined = DateTime.tryParse(joinedRaw);
    final churnScore = client['churn_score'] ?? client['risk_score'];
    final topSignal = mapStr(client, ['top_signal', 'churn_signal']);

    final initials = name.isNotEmpty
        ? name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    double? churnValue;
    if (churnScore is num) churnValue = churnScore.toDouble();
    else if (churnScore != null) churnValue = double.tryParse(churnScore.toString());

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Avatar + naam
          CircleAvatar(
            radius: 36,
            backgroundColor: GymiesColors.primary.withOpacity(0.15),
            child: Text(
              initials,
              style: GoogleFonts.sora(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: GymiesColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name.isNotEmpty ? name : email,
            style: GoogleFonts.sora(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: GymiesColors.darkBlue,
            ),
          ),
          if (email.isNotEmpty && name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(email, style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            ),

          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _ClientStatBox(
                  value: '$bookingsCount',
                  label: S.of(context).bookings,
                  icon: Icons.event_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ClientStatBox(
                  value: lastVisit != null ? '${lastVisit.day}/${lastVisit.month}' : '-',
                  label: S.of(context).laatsteBezoek,
                  icon: Icons.schedule_rounded,
                ),
              ),
              if (churnValue != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _ClientStatBox(
                    value: '${churnValue.toStringAsFixed(0)}%',
                    label: S.of(context).churnRisico,
                    icon: Icons.warning_amber_rounded,
                    valueColor: churnValue >= 70
                        ? Colors.red.shade500
                        : churnValue >= 40
                            ? Colors.amber.shade700
                            : Colors.green.shade600,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Contact info
          if (phone.isNotEmpty)
            _ContactRow(icon: Icons.phone_outlined, value: phone),
          if (joined != null)
            _ContactRow(
              icon: Icons.calendar_today_outlined,
              value: '${S.of(context).lidSinds} ${joined.day}/${joined.month}/${joined.year}',
            ),
          if (topSignal.isNotEmpty)
            _ContactRow(
              icon: Icons.trending_down_rounded,
              value: '${S.of(context).churnSignaal}: $topSignal',
              color: Colors.red.shade500,
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Stat box (in client detail sheet) ────────────────────────────────
class _ClientStatBox extends StatelessWidget {
  const _ClientStatBox({
    required this.value,
    required this.label,
    required this.icon,
    this.valueColor,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.sora(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor ?? GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Contact row ─────────────────────────────────────────────────────
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: color ?? GymiesColors.darkBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
