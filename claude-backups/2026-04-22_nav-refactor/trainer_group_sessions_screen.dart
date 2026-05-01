import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
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

  Future<void> _showCreateOrEdit({Map<String, dynamic>? item}) async {
    final title = TextEditingController(text: mapStr(item, ['title', 'name']));
    final capacity = TextEditingController(
      text: mapStr(item, ['capacity', 'max_participants']).isNotEmpty
          ? mapStr(item, ['capacity', 'max_participants'])
          : '10',
    );
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
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            item == null ? 'Groepsles toevoegen' : 'Groepsles bewerken',
          ),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final navigator = Navigator.of(ctx);
                      final cap = int.tryParse(capacity.text.trim());
                      if (title.text.trim().isEmpty || cap == null || cap <= 0) {
                        _errorSnack('Vul een titel in en een capaciteit van minimaal 1.');
                        return;
                      }
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
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
              ),
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish(Map<String, dynamic> item) async {
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
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: list
                .map(
                  (p) => Card(
                    child: ListTile(
                      title: Text(
                        mapStr(p, ['name', 'full_name']).isNotEmpty
                            ? mapStr(p, ['name', 'full_name'])
                            : 'Deelnemer',
                      ),
                      subtitle: Text(
                        'Status: ${mapStr(p, ['status', 'attendance_status']).isNotEmpty ? mapStr(p, ['status', 'attendance_status']) : '-'}',
                      ),
                      trailing: IconButton(
                        onPressed: () async {
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
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _errorSnack(e.message);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Groepslessen',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _showCreateOrEdit,
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
                        return Card(
                          child: ListTile(
                            title: Text(
                              mapStr(s, ['title', 'name']).isNotEmpty
                                  ? mapStr(s, ['title', 'name'])
                                  : 'Groepsles',
                              style: GoogleFonts.fjallaOne(
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            subtitle: Text(
                              '${mapStr(s, ['starts_at', 'startsAt', 'start_time']).isNotEmpty ? mapStr(s, ['starts_at', 'startsAt', 'start_time']) : '-'} · cap ${mapStr(s, ['capacity', 'max_participants']).isNotEmpty ? mapStr(s, ['capacity', 'max_participants']) : '-'}',
                            ),
                            trailing: PopupMenuButton<String>(
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
                                  case 'participants':
                                    _participants(s);
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
                                PopupMenuItem(
                                  value: 'participants',
                                  child: Text('Deelnemers'),
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
