import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/trainer_state_views.dart';
import '../l10n/generated/app_localizations.dart';

/// Gym trainers overzicht — zoeken, filteren, details bekijken, uitnodigen.
class GymTrainersScreen extends StatefulWidget {
  const GymTrainersScreen({super.key});

  @override
  State<GymTrainersScreen> createState() => _GymTrainersScreenState();
}

class _GymTrainersScreenState extends State<GymTrainersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _trainers = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchController = TextEditingController();
  String _statusFilter = 'all'; // all, active, inactive, onboarding

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
      final list = await api.getGymTrainers();
      if (!mounted) return;
      setState(() {
        _trainers = list;
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
        _error = S.of(context).konTrainersNietLaden;
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filtered = _trainers.where((t) {
        // Zoek filter
        if (query.isNotEmpty) {
          final name = mapStr(t, ['name', 'display_name']).toLowerCase();
          final email = mapStr(t, ['email']).toLowerCase();
          final specialization = mapStr(t, ['specialization', 'specialty']).toLowerCase();
          if (!name.contains(query) && !email.contains(query) && !specialization.contains(query)) {
            return false;
          }
        }
        // Status filter
        if (_statusFilter != 'all') {
          final status = mapStr(t, ['status', 'onboarding_status']).toLowerCase();
          if (_statusFilter == 'active' && status != 'active' && status != 'actief') return false;
          if (_statusFilter == 'inactive' && status != 'inactive' && status != 'inactief') return false;
          if (_statusFilter == 'onboarding' && status != 'onboarding' && status != 'pending') return false;
        }
        return true;
      }).toList();
    });
  }

  void _showTrainerDetail(Map<String, dynamic> trainer) {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TrainerDetailSheet(trainer: trainer),
    );
  }

  void _showInviteDialog() {
    Haptics.selection();
    final emailC = TextEditingController();
    final roleC = TextEditingController(text: 'trainer');

    GymiesDialog.custom<void>(
      context,
      title: S.of(context).trainerUitnodigen,
      icon: Icons.person_add_rounded,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailC,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: S.of(context).emailadres,
                hintText: 'trainer@voorbeeld.nl',
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
              ),
            ),
          ],
        ),
      ),
      actions: [
        GymiesDialogAction(
          label: S.of(context).annuleren,
          returnValue: null,
        ),
        GymiesDialogAction(
          label: S.of(context).uitnodigen,
          isPrimary: true,
          onPressed: () async {
            final email = emailC.text.trim();
            if (email.isEmpty || !email.contains('@')) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context).voerEenGeldigEmailadresIn),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            Navigator.pop(context);
            try {
              await context.read<GymiesApi>().inviteGymMember(email: email, role: 'trainer');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context).uitnodigingVerstuurdNaar(email)),
                  backgroundColor: GymiesColors.darkBlue,
                ),
              );
              _load(); // Herlaad lijst
            } on ApiException catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.message), backgroundColor: Colors.red),
              );
            }
          },
        ),
      ],
    ).then((_) {
      emailC.dispose();
      roleC.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(title: S.of(context).trainers),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showInviteDialog,
        backgroundColor: GymiesColors.primary,
        foregroundColor: GymiesColors.darkBlue,
        icon: const Icon(Icons.person_add_rounded, size: 20),
        label: Text(
          S.of(context).uitnodigen,
          style: GoogleFonts.sora(fontWeight: FontWeight.w600),
        ),
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
                  hintText: S.of(context).zoekTrainer,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                          },
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

            // ── Filter chips ─────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterChip(
                    label: S.of(context).allemaal,
                    selected: _statusFilter == 'all',
                    onTap: () => setState(() { _statusFilter = 'all'; _applyFilters(); }),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: S.of(context).actief,
                    selected: _statusFilter == 'active',
                    onTap: () => setState(() { _statusFilter = 'active'; _applyFilters(); }),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Onboarding',
                    selected: _statusFilter == 'onboarding',
                    onTap: () => setState(() { _statusFilter = 'onboarding'; _applyFilters(); }),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: S.of(context).inactief,
                    selected: _statusFilter == 'inactive',
                    onTap: () => setState(() { _statusFilter = 'inactive'; _applyFilters(); }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Trainer count ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} ${_filtered.length == 1 ? 'trainer' : S.of(context).trainers2}',
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
                          icon: Icons.people_rounded,
                          title: _searchController.text.isNotEmpty
                              ? S.of(context).geenResultaten
                              : S.of(context).geenTrainers,
                          subtitle: _searchController.text.isNotEmpty
                              ? S.of(context).probeerAndereZoektermen
                              : S.of(context).erZijnNogGeenTrainersGekoppeld,
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: GymiesColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _TrainerCard(
                          trainer: _filtered[i],
                          onTap: () => _showTrainerDetail(_filtered[i]),
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

// ── Filter chip ─────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? GymiesColors.darkBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? GymiesColors.darkBlue : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

// ── Trainer card ────────────────────────────────────────────────────
class _TrainerCard extends StatelessWidget {
  const _TrainerCard({
    required this.trainer,
    required this.onTap,
  });

  final Map<String, dynamic> trainer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = mapStr(trainer, ['name', 'display_name']);
    final email = mapStr(trainer, ['email']);
    final status = mapStr(trainer, ['status', 'onboarding_status']).toLowerCase();
    final specialization = mapStr(trainer, ['specialization', 'specialty']);
    final sessionsCount = mapInt(trainer, ['sessions_count', 'bookings_count', 'total_sessions']);
    final rating = trainer['rating'];
    final ratingStr = rating is num ? rating.toStringAsFixed(1) : null;

    final initials = name.isNotEmpty
        ? name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'active':
      case 'actief':
        statusColor = Colors.green.shade600;
        statusLabel = S.of(context).actief;
        break;
      case 'onboarding':
      case 'pending':
        statusColor = Colors.amber.shade700;
        statusLabel = 'Onboarding';
        break;
      case 'inactive':
      case 'inactief':
        statusColor = Colors.grey.shade500;
        statusLabel = S.of(context).inactief;
        break;
      default:
        statusColor = Colors.grey.shade400;
        statusLabel = status.isNotEmpty ? status : '-';
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
                  backgroundColor: GymiesColors.darkBlue.withOpacity(0.08),
                  child: Text(
                    initials,
                    style: GoogleFonts.sora(
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
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
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (specialization.isNotEmpty) ...[
                            Icon(Icons.fitness_center_rounded, size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                specialization,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else
                            Text(
                              email,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          const Spacer(),
                          if (sessionsCount > 0) ...[
                            Icon(Icons.event_rounded, size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 3),
                            Text(
                              '$sessionsCount',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                          if (ratingStr != null) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade600),
                            const SizedBox(width: 2),
                            Text(
                              ratingStr,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
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

// ── Trainer detail bottom sheet ─────────────────────────────────────
class _TrainerDetailSheet extends StatelessWidget {
  const _TrainerDetailSheet({required this.trainer});
  final Map<String, dynamic> trainer;

  @override
  Widget build(BuildContext context) {
    final name = mapStr(trainer, ['name', 'display_name']);
    final email = mapStr(trainer, ['email']);
    final phone = mapStr(trainer, ['phone', 'phone_number']);
    final status = mapStr(trainer, ['status', 'onboarding_status']).toLowerCase();
    final specialization = mapStr(trainer, ['specialization', 'specialty']);
    final sessionsCount = mapInt(trainer, ['sessions_count', 'bookings_count', 'total_sessions']);
    final clientsCount = mapInt(trainer, ['clients_count', 'total_clients']);
    final rating = trainer['rating'];
    final joinedAt = mapStr(trainer, ['created_at', 'joined_at']);
    final locationName = mapStr(trainer, ['location_name', 'location']);

    final initials = name.isNotEmpty
        ? name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'active':
      case 'actief':
        statusColor = Colors.green.shade600;
        statusLabel = S.of(context).actief;
        break;
      case 'onboarding':
      case 'pending':
        statusColor = Colors.amber.shade700;
        statusLabel = 'Onboarding';
        break;
      default:
        statusColor = Colors.grey.shade500;
        statusLabel = status.isNotEmpty ? status : '-';
    }

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
            backgroundColor: GymiesColors.darkBlue.withOpacity(0.08),
            child: Text(
              initials,
              style: GoogleFonts.sora(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: GymiesColors.darkBlue,
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
          if (specialization.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                specialization,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _DetailStat(
                  icon: Icons.event_rounded,
                  value: '$sessionsCount',
                  label: S.of(context).sessies,
                ),
              ),
              Expanded(
                child: _DetailStat(
                  icon: Icons.people_rounded,
                  value: '$clientsCount',
                  label: S.of(context).klanten,
                ),
              ),
              Expanded(
                child: _DetailStat(
                  icon: Icons.star_rounded,
                  value: rating is num ? rating.toStringAsFixed(1) : '-',
                  label: S.of(context).beoordeling,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Contact info
          if (email.isNotEmpty)
            _DetailRow(icon: Icons.email_outlined, label: S.of(context).email2, value: email),
          if (phone.isNotEmpty)
            _DetailRow(icon: Icons.phone_outlined, label: S.of(context).telefoon, value: phone),
          if (locationName.isNotEmpty)
            _DetailRow(icon: Icons.location_on_outlined, label: S.of(context).locatie, value: locationName),
          if (joinedAt.isNotEmpty)
            Builder(builder: (_) {
              final dt = DateTime.tryParse(joinedAt);
              if (dt == null) return const SizedBox.shrink();
              return _DetailRow(
                icon: Icons.calendar_today_outlined,
                label: S.of(context).lidSinds,
                value: '${dt.day}/${dt.month}/${dt.year}',
              );
            }),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Detail stat (in bottom sheet) ────────────────────────────────────
class _DetailStat extends StatelessWidget {
  const _DetailStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: GymiesColors.darkBlue.withOpacity(0.5), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: GymiesColors.darkBlue,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// ── Detail row (contact info in bottom sheet) ────────────────────────
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: GymiesColors.darkBlue,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
