import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/gymies_api.dart';
import '../../theme/gymies_theme.dart';

/// Een uurblok gegenereerd uit een beschikbaarheidsvenster.
class _HourBlock {
  const _HourBlock({required this.hour, required this.minute});
  final int hour;
  final int minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get endLabel {
    final endH = hour + 1;
    return '${endH.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

/// Bottom sheet die beschikbare slots van een trainer toont
/// voor het verplaatsen van een sessie.
///
/// Splitst brede tijdvensters (bijv. 08:00-18:00) in blokken van 1 uur.
/// Retourneert een [DateTime] wanneer de gebruiker een slot selecteert.
class RescheduleSlotPicker extends StatefulWidget {
  const RescheduleSlotPicker({
    super.key,
    required this.api,
    required this.trainerId,
    required this.trainerName,
    this.currentScheduledAt,
  });

  final GymiesApi api;
  final String trainerId;
  final String trainerName;
  final DateTime? currentScheduledAt;

  @override
  State<RescheduleSlotPicker> createState() => _RescheduleSlotPickerState();
}

class _RescheduleSlotPickerState extends State<RescheduleSlotPicker> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _slots = [];
  DateTime? _selectedDate;

  static const _weekdayNames = ['', 'ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    try {
      final slots =
          await widget.api.getTrainerPublicAvailability(widget.trainerId);
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon beschikbaarheid niet laden';
        _loading = false;
      });
    }
  }

  // ── Tijd parsing helpers ──

  /// Parse "HH:mm:ss" of "HH:mm" naar (uur, minuut).
  (int, int) _parseTime(String raw) {
    final parts = raw.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return (h, m);
  }

  int _weekdayFromSlot(Map<String, dynamic> slot) {
    final raw = (slot['weekday'] ??
            slot['day_of_week'] ??
            slot['dayOfWeek'] ??
            slot['iso_weekday'] ??
            slot['day'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (raw == null || raw.isEmpty) return 0;
    final n = int.tryParse(raw);
    if (n != null && n >= 1 && n <= 7) return n;
    const map = {
      'maandag': 1, 'monday': 1,
      'dinsdag': 2, 'tuesday': 2,
      'woensdag': 3, 'wednesday': 3,
      'donderdag': 4, 'thursday': 4,
      'vrijdag': 5, 'friday': 5,
      'zaterdag': 6, 'saturday': 6,
      'zondag': 7, 'sunday': 7,
    };
    return map[raw] ?? 0;
  }

  /// Geeft de ruwe availability-vensters terug die matchen op [date].
  List<Map<String, dynamic>> _rawSlotsForDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return _slots.where((slot) {
      final exactDate =
          (slot['date'] ?? slot['slot_date'] ?? '').toString().trim();
      if (exactDate.isNotEmpty) {
        final parsed = DateTime.tryParse(exactDate);
        if (parsed != null) {
          if (DateTime(parsed.year, parsed.month, parsed.day) != day) {
            return false;
          }
        }
      } else {
        if (_weekdayFromSlot(slot) != date.weekday) return false;
      }
      final av = (slot['available'] ?? slot['is_available'] ?? slot['bookable'])
          ?.toString()
          .toLowerCase();
      if (av == 'false' || av == '0') return false;
      return (slot['start_time'] ?? slot['startTime'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
    }).toList();
  }

  /// Splits beschikbaarheidsvensters in blokken van 1 uur.
  /// bijv. 08:00-18:00 → [08:00-09:00, 09:00-10:00, ..., 17:00-18:00]
  List<_HourBlock> _hourBlocksForDate(DateTime date) {
    final rawSlots = _rawSlotsForDate(date);
    final blocks = <_HourBlock>[];
    final now = DateTime.now();

    for (final slot in rawSlots) {
      final startRaw =
          (slot['start_time'] ?? slot['startTime'] ?? '').toString().trim();
      final endRaw =
          (slot['end_time'] ?? slot['endTime'] ?? '').toString().trim();

      if (startRaw.isEmpty) continue;

      final (startH, startM) = _parseTime(startRaw);
      // Default eindtijd: startuur + 1
      final (endH, _) = endRaw.isNotEmpty ? _parseTime(endRaw) : (startH + 1, 0);

      // Als start en eind minder dan 2 uur uit elkaar → het IS al een blok
      if (endH - startH <= 1) {
        // Filter verleden slots
        final slotDt = DateTime(date.year, date.month, date.day, startH, startM);
        if (slotDt.isAfter(now)) {
          blocks.add(_HourBlock(hour: startH, minute: startM));
        }
        continue;
      }

      // Splits in uurblokken
      for (int h = startH; h < endH; h++) {
        final slotDt = DateTime(date.year, date.month, date.day, h, 0);
        if (slotDt.isAfter(now)) {
          blocks.add(_HourBlock(hour: h, minute: 0));
        }
      }
    }

    blocks.sort((a, b) {
      final cmp = a.hour.compareTo(b.hour);
      return cmp != 0 ? cmp : a.minute.compareTo(b.minute);
    });
    return blocks;
  }

  /// Komende 28 dagen met beschikbare uurblokken.
  List<DateTime> _availableDates() {
    final today = DateTime.now();
    final dates = <DateTime>[];
    for (int i = 1; i <= 28; i++) {
      final date = DateTime(today.year, today.month, today.day + i);
      if (_hourBlocksForDate(date).isNotEmpty) dates.add(date);
    }
    return dates;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Sessie verplaatsen',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Kies een beschikbaar moment van ${widget.trainerName}',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: GymiesColors.primary,
                    ),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.red.shade400, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: GoogleFonts.sora(
                          color: Colors.red.shade400,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                _buildDateSelector(),
                if (_selectedDate != null) _buildTimeSlots(),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final dates = _availableDates();
    if (dates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Geen beschikbare momenten gevonden',
              style:
                  GoogleFonts.sora(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final date = dates[i];
          final isSelected = _selectedDate != null &&
              date.year == _selectedDate!.year &&
              date.month == _selectedDate!.month &&
              date.day == _selectedDate!.day;
          return GestureDetector(
            onTap: () => setState(() => _selectedDate = date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              decoration: BoxDecoration(
                color: isSelected
                    ? GymiesColors.darkBlue
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: isSelected
                    ? null
                    : Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _weekdayNames[date.weekday],
                    style: GoogleFonts.sora(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.white70
                          : Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.white
                          : GymiesColors.darkBlue,
                    ),
                  ),
                  Text(
                    DateFormat.MMM('nl_NL').format(date),
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      color: isSelected
                          ? Colors.white60
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeSlots() {
    final blocks = _hourBlocksForDate(_selectedDate!);
    if (blocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Geen tijden beschikbaar op deze dag',
          style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade500),
        ),
      );
    }
    return Flexible(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        itemCount: blocks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final block = blocks[i];
          final label = '${block.label} - ${block.endLabel}';
          return GestureDetector(
            onTap: () {
              final dt = DateTime(
                _selectedDate!.year,
                _selectedDate!.month,
                _selectedDate!.day,
                block.hour,
                block.minute,
              );
              Navigator.of(context).pop(dt);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: GymiesColors.primary.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      size: 20, color: GymiesColors.primary),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: Colors.grey.shade400),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
