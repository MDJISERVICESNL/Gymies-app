import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/timing_constants.dart';
import '../models/trainer_models.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class _CopyWeeksChip extends StatelessWidget {
  const _CopyWeeksChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GymiesColors.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(Icons.content_copy_rounded, size: 22, color: GymiesColors.darkBlue),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.fjallaOne(
                  fontSize: 13,
                  color: GymiesColors.darkBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TrainerAgendaScreen extends StatefulWidget {
  const TrainerAgendaScreen({super.key});

  @override
  State<TrainerAgendaScreen> createState() => _TrainerAgendaScreenState();
}

class _TrainerAgendaScreenState extends State<TrainerAgendaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;
  List<TrainerAvailabilitySlot> _slots = [];
  List<TrainerAvailabilityException> _exceptions = [];
  bool _mutating = false;
  String _weekView = 'this';
  int _bookingAdvanceDays = 28;
  String _paymentMethod = 'transfer_and_cash';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final slots = await api.getTrainerAvailabilitySlots();
      final exceptions = await api.getTrainerAvailabilityExceptions();
      final settings = await api.getTrainerAvailabilitySettings();
      if (!mounted) return;
      setState(() {
        _bookingAdvanceDays = (settings['booking_advance_days'] is int)
            ? settings['booking_advance_days'] as int
            : int.tryParse(settings['booking_advance_days']?.toString() ?? '') ?? 28;
        _paymentMethod = (settings['payment_method']?.toString().trim()) ?? 'transfer_and_cash';
        _slots = slots
          ..sort((a, b) {
            final wd = a.weekday.compareTo(b.weekday);
            if (wd != 0) return wd;
            return a.startTime.compareTo(b.startTime);
          });
        _exceptions = exceptions..sort((a, b) => a.date.compareTo(b.date));
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
        _error = 'Kon agenda niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _showSlotDialog({TrainerAvailabilitySlot? slot}) async {
    final parentContext = context;
    int weekday = slot?.weekday ?? 1;
    final startController = TextEditingController(
      text: slot?.startTime ?? '09:00',
    );
    final endController = TextEditingController(text: slot?.endTime ?? '17:00');
    final isNew = slot == null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (_, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    20 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                        Text(
                          isNew ? 'Nieuw tijdslot' : 'Tijdslot bewerken',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 20,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Kies de dag en tijden. Je beschikbaarheid geldt automatisch voor alle weken.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Dag',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(7, (i) {
                            final value = i + 1;
                            final selected = weekday == value;
                            return FilterChip(
                              label: Text(_weekdayLabel(value)),
                              selected: selected,
                              onSelected: (_) => setModalState(() => weekday = value),
                              selectedColor: GymiesColors.primary.withValues(alpha: 0.3),
                              checkmarkColor: GymiesColors.darkBlue,
                            );
                          }),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Tijden',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: startController,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Start',
                                  suffixIcon: const Icon(Icons.access_time_rounded, size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onTap: () async {
                                  final selected = await _pickTimeFromInput(
                                    startController.text.trim(),
                                  );
                                  if (selected == null) return;
                                  startController.text = selected;
                                  setModalState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: endController,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Eind',
                                  suffixIcon: const Icon(Icons.access_time_rounded, size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onTap: () async {
                                  final selected = await _pickTimeFromInput(
                                    endController.text.trim(),
                                  );
                                  if (selected == null) return;
                                  endController.text = selected;
                                  setModalState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                        if (isNew) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Kopieer voor de aankomende',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Stel één keer in en pas toe op alle dagen. Geldt voor alle weken.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _CopyWeeksChip(
                                  label: '2 weken',
                                  onTap: () => _saveAndCopyToAllDays(
                                    parentContext: parentContext,
                                    start: startController.text.trim(),
                                    end: endController.text.trim(),
                                    weeksLabel: '2',
                                    navigator: Navigator.of(sheetContext),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CopyWeeksChip(
                                  label: '4 weken',
                                  onTap: () => _saveAndCopyToAllDays(
                                    parentContext: parentContext,
                                    start: startController.text.trim(),
                                    end: endController.text.trim(),
                                    weeksLabel: '4',
                                    navigator: Navigator.of(sheetContext),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CopyWeeksChip(
                                  label: '6 weken',
                                  onTap: () => _saveAndCopyToAllDays(
                                    parentContext: parentContext,
                                    start: startController.text.trim(),
                                    end: endController.text.trim(),
                                    weeksLabel: '6',
                                    navigator: Navigator.of(sheetContext),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Annuleren'),
                            ),
                            const Spacer(),
                            FilledButton(
                              onPressed: () async {
                                await _saveSlot(
                                  parentContext: parentContext,
                                  sheetContext: sheetContext,
                                  slot: slot,
                                  weekday: weekday,
                                  start: startController.text.trim(),
                                  end: endController.text.trim(),
                                  copyToWeekdays: null,
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: GymiesColors.primary,
                                foregroundColor: GymiesColors.darkBlue,
                              ),
                              child: Text(isNew ? 'Alleen deze dag' : 'Opslaan'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveSlot({
    required BuildContext parentContext,
    required BuildContext sheetContext,
    TrainerAvailabilitySlot? slot,
    required int weekday,
    required String start,
    required String end,
    List<int>? copyToWeekdays,
  }) async {
    if (_mutating) return;
    if (!_validTime(start) || !_validTime(end)) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('Voer geldige tijden in (bijv. 09:00)')),
      );
      return;
    }
    if (!_isStartBeforeEnd(start, end)) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('Eindtijd moet later zijn dan starttijd.')),
      );
      return;
    }
    Navigator.of(sheetContext).pop();
    final api = parentContext.read<GymiesApi>();
    final messenger = ScaffoldMessenger.maybeOf(parentContext);
    if (mounted) setState(() => _mutating = true);
    try {
      final weekdaysToSave = copyToWeekdays ?? [weekday];
      for (final wd in weekdaysToSave) {
        if (_hasSlotOverlap(
          weekday: wd,
          startTime: start,
          endTime: end,
          excludingSlotId: slot?.id,
        )) {
          continue;
        }
        if (slot != null && wd == weekday) {
          await api.updateTrainerAvailabilitySlot(
            slotId: slot.id,
            weekday: wd,
            startTime: start,
            endTime: end,
          );
        } else {
          await api.createTrainerAvailabilitySlot(
            weekday: wd,
            startTime: start,
            endTime: end,
          );
        }
      }
      if (!mounted) return;
      await _load();
      final count = weekdaysToSave.length;
      _showSuccess(
        slot != null
            ? 'Tijdslot bijgewerkt'
            : count > 1
                ? '$count tijdslots toegevoegd'
                : 'Tijdslot toegevoegd',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _saveAndCopyToAllDays({
    required BuildContext parentContext,
    required String start,
    required String end,
    required String weeksLabel,
    required NavigatorState navigator,
  }) async {
    if (_mutating) return;
    if (!_validTime(start) || !_validTime(end)) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('Voer eerst geldige tijden in.')),
      );
      return;
    }
    if (!_isStartBeforeEnd(start, end)) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('Eindtijd moet later zijn dan starttijd.')),
      );
      return;
    }
    navigator.pop();
    final api = parentContext.read<GymiesApi>();
    final messenger = ScaffoldMessenger.maybeOf(parentContext);
    if (mounted) setState(() => _mutating = true);
    try {
      for (var wd = 1; wd <= 7; wd++) {
        if (_hasSlotOverlap(weekday: wd, startTime: start, endTime: end)) {
          continue;
        }
        await api.createTrainerAvailabilitySlot(
          weekday: wd,
          startTime: start,
          endTime: end,
        );
      }
      if (!mounted) return;
      await _load();
      _showSuccess(
        'Beschikbaarheid toegevoegd voor alle dagen (geldt voor de komende $weeksLabel weken en daarna)',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _deleteSlot(TrainerAvailabilitySlot slot) async {
    if (_mutating) return;
    final api = context.read<GymiesApi>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tijdslot verwijderen'),
        content: Text(
          'Verwijder ${_weekdayLabel(slot.weekday)} ${slot.startTime}-${slot.endTime}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _mutating = true);
    try {
      await api.deleteTrainerAvailabilitySlot(slot.id);
      if (!mounted) return;
      await _load();
      _showSuccess('Tijdslot verwijderd');
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _showExceptionDialog() async {
    final parentContext = context;
    DateTime selectedDate = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final dateController = TextEditingController(text: _fmtDate(selectedDate));
    final reasonController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Uitzondering toevoegen'),
          content: StatefulBuilder(
            builder: (_, setModalState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Datum',
                    suffixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      firstDate: DateTime(2022),
                      lastDate: DateTime.now().add(
                        TimingConstants.twoYearRange,
                      ),
                      initialDate: selectedDate,
                    );
                    if (picked == null) return;
                    setModalState(() {
                      selectedDate = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                      );
                      dateController.text = _fmtDate(selectedDate);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reden (optioneel)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () async {
                if (_mutating) return;
                Navigator.of(dialogContext).pop();
                if (mounted) setState(() => _mutating = true);
                try {
                  await parentContext
                      .read<GymiesApi>()
                      .createTrainerAvailabilityException(
                        date: selectedDate,
                        reason: reasonController.text.trim(),
                      );
                  if (!mounted) return;
                  await _load();
                  _showSuccess('Blokkering toegevoegd');
                } on ApiException catch (e) {
                  if (!mounted) return;
                  if (!parentContext.mounted) return;
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                } finally {
                  if (mounted) setState(() => _mutating = false);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
              ),
              child: const Text('Opslaan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteException(TrainerAvailabilityException item) async {
    if (_mutating) return;
    final api = context.read<GymiesApi>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Blokkering verwijderen'),
        content: Text('Verwijder blokkering op ${_fmtDate(item.date)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _mutating = true);
    try {
      await api.deleteTrainerAvailabilityException(item.id);
      if (!mounted) return;
      await _load();
      _showSuccess('Blokkering verwijderd');
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  static const List<int> _advanceDaysOptions = [7, 14, 21, 28, 42, 56, 90];
  static const Map<String, String> _paymentMethodLabels = {
    'transfer_only': 'Accepteert alleen overboekingen',
    'transfer_and_cash': 'Accepteert overboekingen & cash',
    'cash_only': 'Accepteert alleen cash',
  };

  Future<void> _showAvailabilitySettings() async {
    final parentContext = context;
    int advanceDays = _bookingAdvanceDays;
    String paymentMethod = _paymentMethod;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (_, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    20 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                        Text(
                          'Beschikbaarheid-instellingen',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 20,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Deze instellingen worden getoond op je profiel zodat klanten weten hoe ver ze kunnen boeken en hoe ze kunnen betalen.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Boeken van tevoren',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hoeveel dagen van tevoren kan een klant een sessie boeken?',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _advanceDaysOptions.map((days) {
                            return FilterChip(
                              label: Text(
                                days == 7
                                    ? '1 week'
                                    : days == 14
                                        ? '2 weken'
                                        : days == 28
                                            ? '4 weken'
                                            : days == 42
                                                ? '6 weken'
                                                : days == 56
                                                    ? '8 weken'
                                                    : days == 90
                                                        ? '12 weken'
                                                        : '$days dagen',
                              ),
                              selected: advanceDays == days,
                              onSelected: (_) =>
                                  setModalState(() => advanceDays = days),
                              selectedColor:
                                  GymiesColors.primary.withValues(alpha: 0.3),
                              checkmarkColor: GymiesColors.darkBlue,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Betaalmethode',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Wat toon je op je profiel?',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        RadioGroup<String>(
                          groupValue: paymentMethod,
                          onChanged: (v) =>
                              setModalState(() => paymentMethod = v ?? paymentMethod),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _paymentMethodLabels.entries.map((e) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: RadioListTile<String>(
                                  value: e.key,
                                  title: Text(e.value),
                                  activeColor: GymiesColors.darkBlue,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Annuleren'),
                            ),
                            const Spacer(),
                            FilledButton(
                              onPressed: () async {
                                if (_mutating) return;
                                Navigator.of(sheetContext).pop();
                                final api = parentContext.read<GymiesApi>();
                                final messenger = ScaffoldMessenger.maybeOf(parentContext);
                                if (mounted) setState(() => _mutating = true);
                                try {
                                  await api.updateTrainerAvailabilitySettings(
                                    bookingAdvanceDays: advanceDays,
                                    paymentMethod: paymentMethod,
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    _bookingAdvanceDays = advanceDays;
                                    _paymentMethod = paymentMethod;
                                  });
                                  _showSuccess('Instellingen opgeslagen');
                                } on ApiException catch (e) {
                                  if (!mounted) return;
                                  messenger?.showSnackBar(
                                    SnackBar(
                                      content: Text(e.message),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } finally {
                                  if (mounted) setState(() => _mutating = false);
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
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _validTime(String value) {
    final parsed = _timeToMinutes(value);
    return parsed != null;
  }

  int? _timeToMinutes(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  bool _isStartBeforeEnd(String start, String end) {
    final startMinutes = _timeToMinutes(start);
    final endMinutes = _timeToMinutes(end);
    if (startMinutes == null || endMinutes == null) return false;
    return startMinutes < endMinutes;
  }

  bool _hasSlotOverlap({
    required int weekday,
    required String startTime,
    required String endTime,
    String? excludingSlotId,
  }) {
    final newStart = _timeToMinutes(startTime);
    final newEnd = _timeToMinutes(endTime);
    if (newStart == null || newEnd == null) return false;
    for (final s in _slots) {
      if (s.weekday != weekday) continue;
      if (excludingSlotId != null && s.id == excludingSlotId) continue;
      final currentStart = _timeToMinutes(s.startTime);
      final currentEnd = _timeToMinutes(s.endTime);
      if (currentStart == null || currentEnd == null) continue;
      if (newStart < currentEnd && currentStart < newEnd) return true;
    }
    return false;
  }

  Future<String?> _pickTimeFromInput(String initialValue) async {
    final baseMinutes = _timeToMinutes(initialValue);
    final initial = baseMinutes == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: baseMinutes ~/ 60, minute: baseMinutes % 60);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case 1:
        return 'Maandag';
      case 2:
        return 'Dinsdag';
      case 3:
        return 'Woensdag';
      case 4:
        return 'Donderdag';
      case 5:
        return 'Vrijdag';
      case 6:
        return 'Zaterdag';
      case 7:
        return 'Zondag';
      default:
        return 'Onbekend';
    }
  }

  String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTime _startOfWeek(DateTime d) {
    final weekday = d.weekday; // Monday=1
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: weekday - 1));
  }

  List<DateTime> _daysForSelectedWeek() {
    final now = DateTime.now();
    final base = _startOfWeek(now);
    final offsetDays = _weekView == 'next' ? 7 : 0;
    return List<DateTime>.generate(
      7,
      (i) => base.add(Duration(days: i + offsetDays)),
    );
  }

  bool _isBlockedDate(DateTime d) {
    return _exceptions.any(
      (e) =>
          e.date.year == d.year &&
          e.date.month == d.month &&
          e.date.day == d.day,
    );
  }

  List<TrainerAvailabilitySlot> _slotsForDate(DateTime d) {
    return _slots.where((s) => s.weekday == d.weekday).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  String _weekdayShort(int weekday) {
    switch (weekday) {
      case 1:
        return 'Ma';
      case 2:
        return 'Di';
      case 3:
        return 'Wo';
      case 4:
        return 'Do';
      case 5:
        return 'Vr';
      case 6:
        return 'Za';
      case 7:
        return 'Zo';
      default:
        return '?';
    }
  }

  /// Groepeert slots per weekdag (1=maandag t/m 7=zondag).
  Map<int, List<TrainerAvailabilitySlot>> _slotsByWeekday() {
    final map = <int, List<TrainerAvailabilitySlot>>{};
    for (final s in _slots) {
      map.putIfAbsent(s.weekday, () => []).add(s);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Agenda',
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Beschikbaarheid-instellingen',
            onPressed: _mutating ? null : _showAvailabilitySettings,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GymiesColors.primary,
          labelColor: GymiesColors.primary,
          tabs: const [
            Tab(text: 'Beschikbaarheid'),
            Tab(text: 'Uitzonderingen'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _mutating ? null : _showSlotDialog,
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
              icon: const Icon(Icons.add),
              label: const Text('Tijdslot'),
            )
          : FloatingActionButton.extended(
              onPressed: _mutating ? null : _showExceptionDialog,
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
              icon: const Icon(Icons.block),
              label: const Text('Blokkering'),
            ),
      body: _error != null
          ? TrainerErrorView(message: _error!, onRetry: _load)
          : _loading
          ? const TrainerLoadingView()
          : TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: _slots.isEmpty
                      ? ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            TrainerEmptyState(
                              icon: Icons.schedule_rounded,
                              title: 'Nog geen beschikbaarheid ingesteld',
                              subtitle:
                                  'Klanten zien alleen jouw vrije tijdslots als je ze hier instelt. Tik op "+ Tijdslot" hieronder om te beginnen.',
                              padding: const EdgeInsets.all(28),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'this',
                                  label: Text('Deze week'),
                                ),
                                ButtonSegment(
                                  value: 'next',
                                  label: Text('Volgende week'),
                                ),
                              ],
                              selected: {_weekView},
                              onSelectionChanged: (v) {
                                setState(() => _weekView = v.first);
                              },
                              style: ButtonStyle(
                                backgroundColor: WidgetStateProperty.resolveWith(
                                  (states) => states.contains(WidgetState.selected)
                                      ? GymiesColors.primary.withValues(
                                          alpha: 0.3,
                                        )
                                      : null,
                                ),
                                foregroundColor: WidgetStateProperty.resolveWith(
                                  (states) => states.contains(WidgetState.selected)
                                      ? GymiesColors.darkBlue
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._daysForSelectedWeek().map((day) {
                              final blocked = _isBlockedDate(day);
                              final daySlots = blocked
                                  ? <TrainerAvailabilitySlot>[]
                                  : _slotsForDate(day);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: blocked
                                        ? Colors.red.shade100
                                        : GymiesColors.primary.withValues(
                                            alpha: 0.25,
                                          ),
                                    child: Text(
                                      _weekdayShort(day.weekday),
                                      style: const TextStyle(
                                        color: GymiesColors.darkBlue,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    '${_weekdayLabel(day.weekday)} ${day.day.toString().padLeft(2, '0')}-${day.month.toString().padLeft(2, '0')}',
                                    style: GoogleFonts.fjallaOne(
                                      color: GymiesColors.darkBlue,
                                    ),
                                  ),
                                  subtitle: blocked
                                      ? const Text('Geblokkeerd (uitzondering)')
                                      : (daySlots.isEmpty
                                            ? const Text('Niet beschikbaar')
                                            : Text(
                                                daySlots
                                                    .map(
                                                      (s) =>
                                                          '${s.startTime}-${s.endTime}',
                                                    )
                                                    .join(' · '),
                                              )),
                                ),
                              );
                            }),
                            const SizedBox(height: 10),
                            Text(
                              'Wekelijkse tijdslots',
                              style: GoogleFonts.fjallaOne(
                                fontSize: 16,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...() {
                              final entries = _slotsByWeekday().entries.toList()
                                ..sort((a, b) => a.key.compareTo(b.key));
                              return entries.map((entry) {
                              final weekday = entry.key;
                              final daySlots = entry.value;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16, 12, 16, 4,
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: GymiesColors.primary
                                                .withValues(alpha: 0.25),
                                            child: Text(
                                              _weekdayShort(weekday),
                                              style: const TextStyle(
                                                color: GymiesColors.darkBlue,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _weekdayLabel(weekday),
                                            style: GoogleFonts.fjallaOne(
                                              fontSize: 16,
                                              color: GymiesColors.darkBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...daySlots.asMap().entries.map((e) {
                                      final slot = e.value;
                                      final isLast =
                                          e.key == daySlots.length - 1;
                                      return Column(
                                        children: [
                                          ListTile(
                                            dense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 0,
                                            ),
                                            title: Text(
                                              '${slot.startTime} – ${slot.endTime}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  onPressed: _mutating
                                                      ? null
                                                      : () =>
                                                          _showSlotDialog(
                                                            slot: slot,
                                                          ),
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 20,
                                                  ),
                                                ),
                                                IconButton(
                                                  onPressed: _mutating
                                                      ? null
                                                      : () => _deleteSlot(slot),
                                                  icon: Icon(
                                                    Icons.delete_outline,
                                                    size: 20,
                                                    color: Colors.red.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!isLast)
                                            Divider(
                                              height: 1,
                                              indent: 16,
                                              endIndent: 16,
                                              color: Colors.grey.shade300,
                                            ),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              );
                            });
                            }(),
                          ],
                        ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: _exceptions.isEmpty
                      ? ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            TrainerEmptyState(
                              icon: Icons.event_available_rounded,
                              title: 'Geen blokkeringen',
                              subtitle:
                                  'Voeg een blokkering toe voor dagen dat je niet beschikbaar bent, zoals vakantie of ziekte.',
                              padding: const EdgeInsets.all(28),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _exceptions.length,
                          itemBuilder: (_, i) {
                            final e = _exceptions[i];
                            return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: ListTile(
                                title: Text(
                                  _fmtDate(e.date),
                                  style: GoogleFonts.fjallaOne(
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                                subtitle: Text(
                                  e.reason?.isNotEmpty == true
                                      ? e.reason!
                                      : 'Geen reden opgegeven',
                                ),
                                trailing: IconButton(
                                  onPressed: _mutating
                                      ? null
                                      : () => _deleteException(e),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
