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

class TrainerGroupSessionsScreen extends StatefulWidget {
  const TrainerGroupSessionsScreen({super.key});

  @override
  State<TrainerGroupSessionsScreen> createState() =>
      _TrainerGroupSessionsScreenState();
}

class _TrainerGroupSessionsScreenState
    extends State<TrainerGroupSessionsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _sessions = [];

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
      final list = await context.read<GymiesApi>().getTrainerGroupSessions();
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

  String _formatEuro(int cents) {
    final euros = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '€$euros';
  }

  Future<void> _showCreateOrEdit({Map<String, dynamic>? item}) async {
    final title = TextEditingController(text: mapStr(item, ['title', 'name']));
    final capacity = TextEditingController(
      text: mapStr(item, ['capacity', 'max_participants']).isNotEmpty
          ? mapStr(item, ['capacity', 'max_participants'])
          : '10',
    );
    // Price per participant in euros (e.g. "15.00")
    final existingPriceCents =
        int.tryParse(mapStr(item, ['price_per_participant_cents'])) ?? 0;
    final priceController = TextEditingController(
      text: existingPriceCents > 0
          ? (existingPriceCents / 100).toStringAsFixed(2)
          : '',
    );
    // Min participants (crowdfund drempel)
    final minParticipants = TextEditingController(
      text: mapStr(item, ['min_participants']).isNotEmpty
          ? mapStr(item, ['min_participants'])
          : '4',
    );
    // Duration
    final duration = TextEditingController(
      text: mapStr(item, ['duration_minutes']).isNotEmpty
          ? mapStr(item, ['duration_minutes'])
          : '60',
    );
    // Confirmation deadline (uren voor aanvang)
    final deadlineHours = TextEditingController(text: '48');
    final existingStart =
        mapStr(item, ['starts_at', 'startsAt', 'start_time']).isNotEmpty
        ? DateTime.tryParse(mapStr(item, ['starts_at', 'startsAt', 'start_time']))
        : null;
    DateTime selectedDate = existingStart ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(
      existingStart ?? DateTime.now(),
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => GymiesDialog(
          title: item == null ? 'Groepsles toevoegen' : 'Groepsles bewerken',
          headerIcon: Icons.groups_rounded,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Datum'),
                  subtitle: Text(
                    '${selectedDate.day.toString().padLeft(2, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.year}',
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: _busy
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: selectedDate,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365 * 5),
                            ),
                          );
                          if (picked == null) return;
                          setDialogState(() => selectedDate = picked);
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tijd'),
                  subtitle: Text(
                    '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.schedule_outlined),
                  onTap: _busy
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                            context: dialogContext,
                            initialTime: selectedTime,
                          );
                          if (picked == null) return;
                          setDialogState(() => selectedTime = picked);
                        },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Capaciteit'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Prijs per persoon (€)',
                    hintText: '15.00',
                    prefixText: '€ ',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duur (minuten)',
                    hintText: '60',
                  ),
                ),
                const SizedBox(height: 16),
                // Crowdfund sectie
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.group_add_rounded, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 6),
                          Text('Doorgang garantie',
                            style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Klanten reserveren een plek. Pas als het minimum bereikt is, wordt de betaallink verstuurd.',
                        style: GoogleFonts.sora(fontSize: 11, color: Colors.blue.shade600, height: 1.3),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: minParticipants,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min. deelnemers voor doorgang',
                          hintText: '4',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: deadlineHours,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Deadline (uren voor aanvang)',
                          hintText: '48',
                          helperText: 'Als het minimum niet bereikt is voor deze deadline, wordt de les automatisch geannuleerd.',
                          helperMaxLines: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            GymiesDialogAction(
              label: 'Annuleren',
              returnValue: null,
            ),
            GymiesDialogAction(
              label: 'Opslaan',
              isPrimary: true,
              onPressed: _busy
                  ? null
                  : () async {
                      Haptics.light();
                      final navigator = Navigator.of(ctx);
                      final cap = int.tryParse(capacity.text.trim());
                      if (title.text.trim().isEmpty || cap == null || cap <= 0) {
                        _errorSnack('Vul een titel in en een capaciteit van minimaal 1.');
                        return;
                      }
                      // Parse price: "15.00" or "15,00" → 1500 cents
                      final priceText = priceController.text.trim().replaceAll(',', '.');
                      final priceEuros = double.tryParse(priceText);
                      final priceCents = priceEuros != null && priceEuros > 0
                          ? (priceEuros * 100).round()
                          : 0;
                      final minPart = int.tryParse(minParticipants.text.trim()) ?? 1;
                      final dur = int.tryParse(duration.text.trim()) ?? 60;
                      final dlHours = int.tryParse(deadlineHours.text.trim()) ?? 48;
                      final scheduledAt = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        selectedTime.hour,
                        selectedTime.minute,
                      );
                      setState(() => _busy = true);
                      try {
                        final api = context.read<GymiesApi>();
                        if (item == null) {
                          await api.createTrainerGroupSession(
                            title: title.text.trim(),
                            startsAtIso: scheduledAt.toIso8601String(),
                            capacity: cap,
                            pricePerParticipantCents: priceCents > 0 ? priceCents : null,
                            minParticipants: minPart,
                            durationMinutes: dur,
                            confirmationDeadlineHours: dlHours,
                          );
                        } else {
                          final groupSessionId = _resolveGroupSessionId(item);
                          if (groupSessionId == null) {
                            _errorSnack(
                              'Groepsles-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.',
                            );
                            return;
                          }
                          await api.updateTrainerGroupSession(
                            id: groupSessionId,
                            title: title.text.trim(),
                            startsAtIso: scheduledAt.toIso8601String(),
                            capacity: cap,
                            pricePerParticipantCents: priceCents > 0 ? priceCents : null,
                            minParticipants: minPart,
                            durationMinutes: dur,
                            confirmationDeadlineHours: dlHours,
                          );
                        }
                        if (navigator.canPop()) navigator.pop();
                        if (!mounted) return;
                        await _load();
                        _success(
                          item == null
                              ? 'Groepsles toegevoegd'
                              : 'Groepsles bijgewerkt',
                        );
                      } on ApiException catch (e) {
                        if (!mounted) return;
                        _errorSnack(e.message);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish(Map<String, dynamic> item) async {
    Haptics.light();
    final groupSessionId = _resolveGroupSessionId(item);
    if (groupSessionId == null) {
      _errorSnack(
        'Groepsles-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.',
      );
      return;
    }
    await _runAction(() async {
      await context.read<GymiesApi>().publishTrainerGroupSession(
        groupSessionId,
      );
      _success('Groepsles gepubliceerd');
    });
  }

  Future<void> _cancel(Map<String, dynamic> item) async {
    Haptics.heavy();
    final groupSessionId = _resolveGroupSessionId(item);
    if (groupSessionId == null) {
      _errorSnack(
        'Groepsles-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.',
      );
      return;
    }
    await _runAction(() async {
      await context.read<GymiesApi>().cancelTrainerGroupSession(groupSessionId);
      _success('Groepsles geannuleerd');
    });
  }

  Future<void> _participants(Map<String, dynamic> item) async {
    Haptics.selection();
    final groupSessionId = _resolveGroupSessionId(item);
    if (groupSessionId == null) {
      _errorSnack(
        'Groepsles-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.',
      );
      return;
    }
    try {
      final list = await context
          .read<GymiesApi>()
          .getTrainerGroupSessionParticipants(groupSessionId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.groups_rounded,
                        color: GymiesColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Deelnemers',
                        style: GoogleFonts.sora(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(_).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: list
                        .map(
                          (p) => Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              title: Text(
                                mapStr(p, ['name', 'full_name']).isNotEmpty
                                    ? mapStr(p, ['name', 'full_name'])
                                    : 'Deelnemer',
                                style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    'Status: ${mapStr(p, ['status', 'attendance_status']).isNotEmpty ? mapStr(p, ['status', 'attendance_status']) : '-'}',
                                    style: GoogleFonts.sora(fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  if (mapStr(p, ['payment_status']).isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: mapStr(p, ['payment_status']) == 'paid'
                                            ? Colors.green.shade50
                                            : Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        mapStr(p, ['payment_status']) == 'paid' ? 'Betaald' : 'Open',
                                        style: GoogleFonts.sora(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: mapStr(p, ['payment_status']) == 'paid'
                                              ? Colors.green.shade700
                                              : Colors.orange.shade700,
                                        ),
                                      ),
                                    ),
                                  if (int.tryParse(mapStr(p, ['amount_cents'])) != null &&
                                      int.parse(mapStr(p, ['amount_cents'])) > 0) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatEuro(int.parse(mapStr(p, ['amount_cents']))),
                                      style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: IconButton(
                                onPressed: () async {
                                  Haptics.light();
                                  final participantId = _resolveParticipantId(p);
                                  if (participantId == null) {
                                    _errorSnack(
                                      'Deelnemer-ID ontbreekt voor deze regel.',
                                    );
                                    return;
                                  }
                                  await context
                                      .read<GymiesApi>()
                                      .markGroupParticipantAttended(
                                        groupSessionId: groupSessionId,
                                        participantId: participantId,
                                      );
                                  if (!mounted) return;
                                  Navigator.of(context).pop();
                                  _success('Aanwezigheid gemarkeerd');
                                },
                                icon: const Icon(Icons.check_circle_outline),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _errorSnack(e.message);
    }
  }

  Future<void> _showWaitlist(Map<String, dynamic> session) async {
    Haptics.selection();
    final groupSessionId = _resolveGroupSessionId(session);
    if (groupSessionId == null) {
      _errorSnack('Groepsles-ID ontbreekt.');
      return;
    }
    List<Map<String, dynamic>> waitlist = [];
    try {
      final api = context.read<GymiesApi>();
      // Try group-session-specific waitlist endpoint
      final res = await api.get('group-sessions/$groupSessionId/waitlist');
      final raw = res['data'] ?? res['waitlist'] ?? res['items'] ?? [];
      if (raw is List) {
        waitlist = raw.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
      }
    } catch (_) {
      // Fallback: endpoint may not exist yet or is not available
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.hourglass_top_rounded, color: Colors.blue.shade700, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Wachtlijst', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                        Text('${waitlist.length} wachtenden', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(_).pop()),
                ],
              ),
              const SizedBox(height: 16),
              if (waitlist.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.hourglass_empty_rounded, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Nog niemand op de wachtlijst', style: GoogleFonts.sora(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    children: waitlist.map((w) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: GymiesColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              (mapStr(w, ['name', 'full_name']).isNotEmpty ? mapStr(w, ['name', 'full_name'])[0] : '?').toUpperCase(),
                              style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 15, color: GymiesColors.darkBlue),
                            ),
                          ),
                        ),
                        title: Text(mapStr(w, ['name', 'full_name']).isNotEmpty ? mapStr(w, ['name', 'full_name']) : 'Klant', style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                        subtitle: Text(mapStr(w, ['created_at', 'joined_at']).isNotEmpty ? 'Aangemeld: ${mapStr(w, ['created_at', 'joined_at'])}' : '', style: GoogleFonts.sora(fontSize: 12)),
                        trailing: FilledButton(
                          onPressed: () async {
                            Haptics.light();
                            try {
                              await context.read<GymiesApi>().promoteFromWaitlist(
                                sessionId: session['id'].toString(),
                                clientUserId: w['client_user_id'] ?? w['user_id'] ?? '',
                              );
                              if (!mounted) return;
                              Haptics.success();
                              Navigator.of(context).pop();
                              _success('Klant gepromoveerd van wachtlijst');
                              await _load();
                            } on ApiException catch (e) {
                              if (!mounted) return;
                              Haptics.error();
                              _errorSnack(e.message);
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: GymiesColors.primary,
                            foregroundColor: GymiesColors.darkBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Toelaten', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    )).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      _errorSnack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _success(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  void _errorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String? _resolveGroupSessionId(Map<String, dynamic>? map) {
    final id = mapStr(map, ['id', 'group_session_id', 'groupSessionId']);
    return id.isEmpty ? null : id;
  }

  String? _resolveParticipantId(Map<String, dynamic>? map) {
    final id = mapStr(map, ['id', 'participant_id', 'participantId']);
    return id.isEmpty ? null : id;
  }

  String _formatDate(Map<String, dynamic> session) {
    final raw = mapStr(session, ['starts_at', 'startsAt', 'start_time']);
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const days = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
    return '${days[dt.weekday - 1]} ${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}';
  }

  String _formatTime(Map<String, dynamic> session) {
    final raw = mapStr(session, ['starts_at', 'startsAt', 'start_time']);
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  bool _isFull(Map<String, dynamic> session) {
    final capacity = int.tryParse(mapStr(session, ['capacity', 'max_participants'])) ?? 0;
    final enrolled = int.tryParse(mapStr(session, ['enrolled_count', 'enrolledCount', 'participants_count', 'participantsCount'])) ?? 0;
    return capacity > 0 && enrolled >= capacity;
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status.toLowerCase()) {
      case 'published':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        label = 'Live';
        break;
      case 'cancelled':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        label = 'Geannuleerd';
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade600;
        label = 'Concept';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _buildCapacityBar(Map<String, dynamic> session) {
    final capacity = int.tryParse(mapStr(session, ['capacity', 'max_participants'])) ?? 0;
    final enrolled = int.tryParse(mapStr(session, ['enrolled_count', 'enrolledCount', 'participants_count', 'participantsCount'])) ?? 0;
    final waitlistCount = int.tryParse(mapStr(session, ['waitlist_count', 'waitlistCount'])) ?? 0;
    final isFull = capacity > 0 && enrolled >= capacity;
    final progress = capacity > 0 ? (enrolled / capacity).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.people_outline_rounded, size: 16, color: isFull ? Colors.orange.shade700 : GymiesColors.darkBlue),
            const SizedBox(width: 6),
            Text('$enrolled / $capacity plekken', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
            if (isFull) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('VOL', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
              ),
            ],
            if (waitlistCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('$waitlistCount op wachtlijst', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(isFull ? Colors.orange.shade400 : GymiesColors.primary),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: 'Groepslessen',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy
            ? null
            : () {
                Haptics.selection();
                _showCreateOrEdit();
              },
        backgroundColor: GymiesColors.primary,
        foregroundColor: GymiesColors.darkBlue,
        icon: const Icon(Icons.add),
        label: const Text('Groepsles'),
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _sessions.isEmpty
                  ? ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        TrainerEmptyState(
                          icon: Icons.groups_rounded,
                          title: 'Nog geen groepslessen',
                          actionLabel: 'Groepsles toevoegen',
                          actionIcon: Icons.add,
                          onAction: _showCreateOrEdit,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sessions.length,
                      itemBuilder: (_, i) {
                        final s = _sessions[i];
                        final title = mapStr(s, ['title', 'name']).isNotEmpty ? mapStr(s, ['title', 'name']) : 'Groepsles';
                        final status = mapStr(s, ['status', 'state']).isNotEmpty ? mapStr(s, ['status', 'state']) : 'draft';
                        final formattedDate = _formatDate(s);
                        final formattedTime = _formatTime(s);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title row with status badge
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(title, style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                                    ),
                                    _buildStatusBadge(status),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Date & time row
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey.shade500),
                                    const SizedBox(width: 6),
                                    Text(formattedDate, style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade700)),
                                    const SizedBox(width: 16),
                                    Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500),
                                    const SizedBox(width: 6),
                                    Text(formattedTime, style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade700)),
                                  ],
                                ),
                                // Price per participant
                                if (int.tryParse(mapStr(s, ['price_per_participant_cents'])) != null &&
                                    int.parse(mapStr(s, ['price_per_participant_cents'])) > 0) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.euro_rounded, size: 14, color: Colors.green.shade600),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${_formatEuro(int.parse(mapStr(s, ['price_per_participant_cents'])))} p.p.',
                                        style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 10),
                                // Capacity bar
                                _buildCapacityBar(s),
                                const SizedBox(height: 10),
                                // Action buttons row
                                Row(
                                  children: [
                                    // Participants button
                                    OutlinedButton(
                                      onPressed: () => _participants(s),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: Colors.grey.shade200),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: GymiesColors.darkBlue.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(Icons.groups_rounded, size: 13, color: GymiesColors.darkBlue),
                                          ),
                                          const SizedBox(width: 6),
                                          Text('Deelnemers', style: GoogleFonts.sora(fontSize: 12, color: GymiesColors.darkBlue)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Waitlist button (if capacity is full)
                                    if (_isFull(s))
                                      OutlinedButton(
                                        onPressed: () => _showWaitlist(s),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: Colors.blue.shade200),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 22,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade700.withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Icon(Icons.hourglass_top_rounded, size: 13, color: Colors.blue.shade700),
                                            ),
                                            const SizedBox(width: 6),
                                            Text('Wachtlijst', style: GoogleFonts.sora(fontSize: 12, color: Colors.blue.shade700)),
                                          ],
                                        ),
                                      ),
                                    const Spacer(),
                                    // Menu button
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'edit':
                                            _showCreateOrEdit(item: s);
                                            break;
                                          case 'publish':
                                            _publish(s);
                                            break;
                                          case 'cancel':
                                            _cancel(s);
                                            break;
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Bewerken'),
                                        ),
                                        PopupMenuItem(
                                          value: 'publish',
                                          child: Text('Publiceren'),
                                        ),
                                        PopupMenuItem(
                                          value: 'cancel',
                                          child: Text('Annuleren'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
