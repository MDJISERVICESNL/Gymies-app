import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';
import '../l10n/generated/app_localizations.dart';

/// Gym boekingen overzicht — met filters, status badges en detail-view.
class GymBookingsScreen extends StatefulWidget {
  const GymBookingsScreen({super.key});

  @override
  State<GymBookingsScreen> createState() => _GymBookingsScreenState();
}

class _GymBookingsScreenState extends State<GymBookingsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _filtered = [];

  // Filters
  String _periodFilter = 'all'; // all, today, week, month
  String _statusFilter = 'all'; // all, confirmed, pending, cancelled, completed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<GymiesApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Gebruik API filters als period is ingesteld
      DateTime? from;
      DateTime? to;
      final now = DateTime.now();
      switch (_periodFilter) {
        case 'today':
          from = DateTime(now.year, now.month, now.day);
          to = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'week':
          from = now.subtract(Duration(days: now.weekday - 1));
          from = DateTime(from.year, from.month, from.day);
          to = from.add(const Duration(days: 6, hours: 23, minutes: 59));
          break;
        case 'month':
          from = DateTime(now.year, now.month, 1);
          to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
      }

      final statusParam = _statusFilter != 'all' ? _statusFilter : null;
      final list = await api.getGymBookings(status: statusParam, from: from, to: to);
      if (!mounted) return;
      setState(() {
        _bookings = list;
        _loading = false;
      });
      _applyLocalFilters();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = S.of(context).konBoekingenNietLaden2;
        _loading = false;
      });
    }
  }

  void _applyLocalFilters() {
    // Sorteer op datum (nieuwste eerst)
    final sorted = List<Map<String, dynamic>>.from(_bookings);
    sorted.sort((a, b) {
      final dtA = DateTime.tryParse(mapStr(a, ['scheduled_at', 'scheduledAt'])) ?? DateTime(2000);
      final dtB = DateTime.tryParse(mapStr(b, ['scheduled_at', 'scheduledAt'])) ?? DateTime(2000);
      return dtB.compareTo(dtA);
    });
    setState(() => _filtered = sorted);
  }

  void _showBookingDetail(Map<String, dynamic> booking) {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookingDetailSheet(booking: booking),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(title: S.of(context).bookings),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: Column(
          children: [
            // ── Periode filter chips ──────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  _FilterChip(
                    label: S.of(context).allemaal,
                    selected: _periodFilter == 'all',
                    onTap: () { _periodFilter = 'all'; _load(); },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: S.of(context).vandaag,
                    selected: _periodFilter == 'today',
                    onTap: () { _periodFilter = 'today'; _load(); },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: S.of(context).dezeWeek,
                    selected: _periodFilter == 'week',
                    onTap: () { _periodFilter = 'week'; _load(); },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: S.of(context).dezeMaand,
                    selected: _periodFilter == 'month',
                    onTap: () { _periodFilter = 'month'; _load(); },
                  ),
                ],
              ),
            ),

            // ── Status filter chips ──────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatusChip(
                    label: S.of(context).alleStatussen,
                    selected: _statusFilter == 'all',
                    onTap: () { _statusFilter = 'all'; _load(); },
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: S.of(context).bevestigd,
                    selected: _statusFilter == 'confirmed',
                    color: Colors.green.shade600,
                    onTap: () { _statusFilter = 'confirmed'; _load(); },
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: S.of(context).inAfwachting,
                    selected: _statusFilter == 'pending',
                    color: Colors.amber.shade700,
                    onTap: () { _statusFilter = 'pending'; _load(); },
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: S.of(context).geannuleerd,
                    selected: _statusFilter == 'cancelled',
                    color: Colors.red.shade500,
                    onTap: () { _statusFilter = 'cancelled'; _load(); },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Booking count ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} ${_filtered.length == 1 ? 'boeking' : S.of(context).boekingen2}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Lijst ─────────────────────────────────────────
            Expanded(
              child: _filtered.isEmpty && !_loading
                  ? ListView(
                      children: [
                        TrainerEmptyState(
                          icon: Icons.event_available_rounded,
                          title: S.of(context).geenBoekingen,
                          subtitle: S.of(context).erZijnNogGeenBoekingenIn,
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: GymiesColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _BookingCard(
                          booking: _filtered[i],
                          onTap: () => _showBookingDetail(_filtered[i]),
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

// ── Filter chip (periode) ───────────────────────────────────────────
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

// ── Status chip ─────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.grey.shade600;
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? chipColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? chipColor : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? chipColor : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

// ── Booking card ────────────────────────────────────────────────────
class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.onTap,
  });

  final Map<String, dynamic> booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final clientName = mapStr(booking, ['client_name', 'client']);
    final trainerName = mapStr(booking, ['trainer_name', 'trainer']);
    final sessionType = mapStr(booking, ['session_type', 'type', 'service']);
    final status = mapStr(booking, ['status']).toLowerCase();
    final rawDate = mapStr(booking, ['scheduled_at', 'scheduledAt', 'date']);
    final dt = DateTime.tryParse(rawDate);
    final duration = mapInt(booking, ['duration_minutes', 'duration']);

    final dateStr = dt != null
        ? '${dt.day}/${dt.month}/${dt.year}'
        : '-';
    final timeStr = dt != null
        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'confirmed':
      case 'bevestigd':
        statusColor = Colors.green.shade600;
        statusLabel = S.of(context).bevestigd;
        break;
      case 'pending':
      case 'in_afwachting':
        statusColor = Colors.amber.shade700;
        statusLabel = S.of(context).inAfwachting;
        break;
      case 'cancelled':
      case 'geannuleerd':
        statusColor = Colors.red.shade500;
        statusLabel = S.of(context).geannuleerd;
        break;
      case 'completed':
      case 'afgerond':
        statusColor = Colors.blue.shade600;
        statusLabel = S.of(context).afgerond;
        break;
      default:
        statusColor = Colors.grey.shade500;
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
                // Tijd + datum kolom
                Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: GymiesColors.darkBlue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        timeStr.isNotEmpty ? timeStr : '--:--',
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      if (dt != null)
                        Text(
                          '${dt.day}/${dt.month}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientName.isNotEmpty ? clientName : '-',
                        style: GoogleFonts.sora(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: GymiesColors.darkBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (trainerName.isNotEmpty) ...[
                            Icon(Icons.person_outline_rounded, size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                trainerName,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          if (sessionType.isNotEmpty) ...[
                            if (trainerName.isNotEmpty)
                              Text(' · ', style: TextStyle(color: Colors.grey.shade400)),
                            Flexible(
                              child: Text(
                                sessionType,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (duration > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '$duration min',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          ),
        ),
      ),
    );
  }
}

// ── Booking detail bottom sheet ─────────────────────────────────────
class _BookingDetailSheet extends StatelessWidget {
  const _BookingDetailSheet({required this.booking});
  final Map<String, dynamic> booking;

  @override
  Widget build(BuildContext context) {
    final clientName = mapStr(booking, ['client_name', 'client']);
    final clientEmail = mapStr(booking, ['client_email']);
    final trainerName = mapStr(booking, ['trainer_name', 'trainer']);
    final sessionType = mapStr(booking, ['session_type', 'type', 'service']);
    final status = mapStr(booking, ['status']).toLowerCase();
    final rawDate = mapStr(booking, ['scheduled_at', 'scheduledAt', 'date']);
    final dt = DateTime.tryParse(rawDate);
    final duration = mapInt(booking, ['duration_minutes', 'duration']);
    final price = booking['price'] ?? booking['amount'];
    final location = mapStr(booking, ['location_name', 'location']);
    final notes = mapStr(booking, ['notes', 'remark']);
    final bookingId = mapStr(booking, ['id', 'booking_id']);

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'confirmed':
      case 'bevestigd':
        statusColor = Colors.green.shade600;
        statusLabel = S.of(context).bevestigd;
        break;
      case 'pending':
      case 'in_afwachting':
        statusColor = Colors.amber.shade700;
        statusLabel = S.of(context).inAfwachting;
        break;
      case 'cancelled':
      case 'geannuleerd':
        statusColor = Colors.red.shade500;
        statusLabel = S.of(context).geannuleerd;
        break;
      case 'completed':
      case 'afgerond':
        statusColor = Colors.blue.shade600;
        statusLabel = S.of(context).afgerond;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  S.of(context).boekingDetails,
                  style: GoogleFonts.sora(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Details
          if (dt != null)
            _DetailItem(
              icon: Icons.calendar_today_outlined,
              label: S.of(context).datumTijd,
              value: '${dt.day}/${dt.month}/${dt.year} om ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
            ),
          if (clientName.isNotEmpty)
            _DetailItem(icon: Icons.person_outlined, label: S.of(context).klant, value: clientName),
          if (clientEmail.isNotEmpty)
            _DetailItem(icon: Icons.email_outlined, label: S.of(context).email2, value: clientEmail),
          if (trainerName.isNotEmpty)
            _DetailItem(icon: Icons.fitness_center_rounded, label: S.of(context).trainer, value: trainerName),
          if (sessionType.isNotEmpty)
            _DetailItem(icon: Icons.category_outlined, label: S.of(context).type, value: sessionType),
          if (duration > 0)
            _DetailItem(icon: Icons.timer_outlined, label: S.of(context).duur, value: '$duration ${S.of(context).minuten}'),
          if (price != null)
            _DetailItem(
              icon: Icons.euro_outlined,
              label: S.of(context).prijs,
              value: price is num
                  ? '€ ${price.toStringAsFixed(2)}'
                  : '€ $price',
            ),
          if (location.isNotEmpty)
            _DetailItem(icon: Icons.location_on_outlined, label: S.of(context).locatie, value: location),
          if (notes.isNotEmpty)
            _DetailItem(icon: Icons.notes_outlined, label: S.of(context).opmerkingen, value: notes),
          if (bookingId.isNotEmpty)
            _DetailItem(
              icon: Icons.tag_outlined,
              label: 'ID',
              value: '#$bookingId',
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Detail item (in booking bottom sheet) ────────────────────────────
class _DetailItem extends StatelessWidget {
  const _DetailItem({
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
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
            ),
          ),
        ],
      ),
    );
  }
}
