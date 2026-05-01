import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/gymies_segment_tab_bar.dart';

class TrainerClientDossierScreen extends StatefulWidget {
  const TrainerClientDossierScreen({
    super.key,
    required this.clientUserId,
    required this.clientName,
    required this.clientEmail,
  });

  final String clientUserId;
  final String clientName;
  final String clientEmail;

  @override
  State<TrainerClientDossierScreen> createState() =>
      _TrainerClientDossierScreenState();
}

class _TrainerClientDossierScreenState extends State<TrainerClientDossierScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _progress = {};
  Map<String, dynamic> _dossier = {};
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _videos = [];
  String _noteFilter = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime _asDate(Map<String, dynamic> item) {
    final raw = mapStr(item, ['session_at', 'created_at', 'date', 'at']);
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _dateFrom(Map<String, dynamic>? map, List<String> keys) {
    final raw = mapStr(map, keys).trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _fmtDate(DateTime? dt, {bool withTime = false}) {
    if (dt == null) return '-';
    final d =
        '${dt.day.toString().padLeft(2, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-${dt.year}';
    if (!withTime) return d;
    return '$d ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _lineValue(String body, String key) {
    final lowerKey = key.toLowerCase();
    final lines = body.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      final lower = trimmed.toLowerCase();
      if (!lower.startsWith(lowerKey)) continue;
      final idx = trimmed.indexOf(':');
      if (idx < 0 || idx + 1 >= trimmed.length) return '';
      return trimmed.substring(idx + 1).trim();
    }
    return '';
  }

  String _visibilityLabel(Map<String, dynamic> note) {
    final explicit = mapStr(note, ['visibility', 'scope']).toLowerCase().trim();
    if (explicit == 'internal') return 'Intern';
    if (explicit == 'shared') return 'Gedeeld';
    final body = mapStr(note, ['body', 'note', 'text']).toLowerCase();
    if (body.contains('visibility: internal')) return 'Intern';
    return 'Gedeeld';
  }

  Future<void> _load() async {
    Haptics.selection();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final results = await Future.wait<dynamic>([
        api.getTrainerClientProgress(widget.clientUserId),
        api.getTrainerClientDossier(widget.clientUserId),
        api.getTrainerClientSessionNotes(widget.clientUserId),
        api.getTrainerClientPayments(widget.clientUserId),
        api.getTrainerClientVideos(widget.clientUserId),
      ]);
      if (!mounted) return;
      final progress = results[0] is Map<String, dynamic>
          ? results[0] as Map<String, dynamic>
          : <String, dynamic>{};
      final dossier = results[1] is Map<String, dynamic>
          ? results[1] as Map<String, dynamic>
          : <String, dynamic>{};
      final notes = (results[2] is List ? results[2] as List : [])
          .whereType<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => _asDate(b).compareTo(_asDate(a)));
      final payments = (results[3] is List ? results[3] as List : [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final videos = (results[4] is List ? results[4] as List : [])
          .whereType<Map<String, dynamic>>()
          .toList();
      setState(() {
        _progress = progress;
        _dossier = dossier;
        _notes = notes;
        _payments = payments;
        _videos = videos;
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
        _error = 'Kon dossier niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _createSessionEntry() async {
    Haptics.selection();
    final focusCtrl = TextEditingController();
    final positiveCtrl = TextEditingController();
    final improveCtrl = TextEditingController();
    final homeworkCtrl = TextEditingController();
    final energyCtrl = TextEditingController(text: '3');
    final performanceCtrl = TextEditingController();
    bool shareWithClient = true;
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => GymiesDialog(
        title: 'Nieuwe sessie-entry',
        headerIcon: Icons.add_chart_rounded,
        content: StatefulBuilder(
          builder: (_, setModalState) => Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _templateChip('Kracht', Icons.fitness_center_rounded, focusCtrl),
                      _templateChip('Cardio', Icons.directions_run_rounded, focusCtrl),
                      _templateChip('Flexibiliteit', Icons.self_improvement_rounded, focusCtrl),
                      _templateChip('Herstel', Icons.healing_rounded, focusCtrl),
                      _templateChip('Voeding', Icons.restaurant_rounded, focusCtrl),
                      _templateChip('Assessment', Icons.assignment_rounded, focusCtrl),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: focusCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Focus van sessie',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Focus is verplicht'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: positiveCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Wat ging goed?',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vul minimaal 1 positief punt in'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: improveCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Aandachtspunt',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vul een aandachtspunt in'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: homeworkCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Huiswerk / actiepunt',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: energyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Energie (1-5)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: performanceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Performance score',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: shareWithClient,
                    title: const Text('Deel met klant'),
                    subtitle: const Text('Uit = intern trainer-only notitie'),
                    onChanged: (v) => setModalState(() => shareWithClient = v),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          GymiesDialogAction(
            label: 'Annuleren',
            returnValue: false,
          ),
          GymiesDialogAction(
            label: 'Opslaan',
            isPrimary: true,
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
            },
            returnValue: true,
          ),
        ],
      ),
    );
    if (submit != true) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final api = context.read<GymiesApi>();
      final now = DateTime.now().toIso8601String();
      final noteBody =
          'Focus: ${focusCtrl.text.trim()}\n'
          'Goed: ${positiveCtrl.text.trim()}\n'
          'Aandachtspunt: ${improveCtrl.text.trim()}\n'
          'Huiswerk: ${homeworkCtrl.text.trim().isEmpty ? '-' : homeworkCtrl.text.trim()}\n'
          'Energie: ${energyCtrl.text.trim().isEmpty ? '-' : energyCtrl.text.trim()}/5\n'
          'Performance: ${performanceCtrl.text.trim().isEmpty ? '-' : performanceCtrl.text.trim()}\n'
          'Visibility: ${shareWithClient ? 'shared' : 'internal'}';
      await api.createTrainerClientSessionNote(
        clientUserId: widget.clientUserId,
        title:
            'Sessie-entry ${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}',
        body: noteBody,
      );
      await api.saveTrainerClientProgress(
        clientUserId: widget.clientUserId,
        progress: {
          'client_user_id': widget.clientUserId,
          'updated_at': now,
          'last_focus': focusCtrl.text.trim(),
          'last_energy': int.tryParse(energyCtrl.text.trim()),
          'last_performance': performanceCtrl.text.trim(),
          'summary': improveCtrl.text.trim(),
        },
      );
      await api.updateTrainerClientDossier(
        clientUserId: widget.clientUserId,
        dossier: {
          'client_user_id': widget.clientUserId,
          'last_session_entry_at': now,
          'last_homework': homeworkCtrl.text.trim(),
          'last_visibility': shareWithClient ? 'shared' : 'internal',
          'last_positive': positiveCtrl.text.trim(),
          'last_improve': improveCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessie-entry opgeslagen'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editNote(Map<String, dynamic> note) async {
    Haptics.selection();
    final body = mapStr(note, ['body', 'note', 'text']);
    final focusCtrl = TextEditingController(text: _lineValue(body, 'Focus'));
    final wentWellCtrl = TextEditingController(text: _lineValue(body, 'Goed'));
    final actionCtrl = TextEditingController(text: _lineValue(body, 'Aandachtspunt'));
    final homeworkCtrl = TextEditingController(text: _lineValue(body, 'Huiswerk'));
    final energyCtrl = TextEditingController(text: _lineValue(body, 'Energie').replaceAll('/5', '').trim());
    final performanceCtrl = TextEditingController(text: _lineValue(body, 'Performance'));
    bool shareWithClient = _visibilityLabel(note) == 'Gedeeld';
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => GymiesDialog(
        title: 'Notitie bewerken',
        headerIcon: Icons.edit_rounded,
        content: StatefulBuilder(
          builder: (_, setModalState) => Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _templateChip('Kracht', Icons.fitness_center_rounded, focusCtrl),
                      _templateChip('Cardio', Icons.directions_run_rounded, focusCtrl),
                      _templateChip('Flexibiliteit', Icons.self_improvement_rounded, focusCtrl),
                      _templateChip('Herstel', Icons.healing_rounded, focusCtrl),
                      _templateChip('Voeding', Icons.restaurant_rounded, focusCtrl),
                      _templateChip('Assessment', Icons.assignment_rounded, focusCtrl),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: focusCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Focus van sessie',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Focus is verplicht'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: wentWellCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Wat ging goed?',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vul minimaal 1 positief punt in'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: actionCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Aandachtspunt',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vul een aandachtspunt in'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: homeworkCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Huiswerk / actiepunt',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: energyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Energie (1-5)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: performanceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Performance score',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: shareWithClient,
                    title: const Text('Deel met klant'),
                    subtitle: const Text('Uit = intern trainer-only notitie'),
                    onChanged: (v) => setModalState(() => shareWithClient = v),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          GymiesDialogAction(
            label: 'Annuleren',
            returnValue: false,
          ),
          GymiesDialogAction(
            label: 'Opslaan',
            isPrimary: true,
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
            },
            returnValue: true,
          ),
        ],
      ),
    );
    if (submit != true) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final api = context.read<GymiesApi>();
      final noteId = mapStr(note, ['id']);
      final noteBody =
          'Focus: ${focusCtrl.text.trim()}\n'
          'Goed: ${wentWellCtrl.text.trim()}\n'
          'Aandachtspunt: ${actionCtrl.text.trim()}\n'
          'Huiswerk: ${homeworkCtrl.text.trim().isEmpty ? '-' : homeworkCtrl.text.trim()}\n'
          'Energie: ${energyCtrl.text.trim().isEmpty ? '-' : energyCtrl.text.trim()}/5\n'
          'Performance: ${performanceCtrl.text.trim().isEmpty ? '-' : performanceCtrl.text.trim()}\n'
          'Visibility: ${shareWithClient ? 'shared' : 'internal'}';
      // NOTE: updateTrainerClientSessionNote does not exist in GymiesApi.
      // The method below is a placeholder until the API endpoint is implemented.
      // For now, this edit feature is unavailable.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bewerken wordt binnenkort beschikbaar'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _templateChip(String label, IconData icon, TextEditingController focusCtrl) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        focusCtrl.text = label;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: GymiesColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GymiesColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: GymiesColors.darkBlue),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.sora(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GymiesColors.darkBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewTab() {
    final streak = mapInt(_progress, ['streak', 'streak_days', 'current_streak']);
    final attendance = mapInt(_progress, ['attendance', 'attendance_rate']);
    final goalsDone = mapInt(_progress, ['goals_done', 'goals_completed']);
    final goalsTotal = mapInt(_progress, ['goals_total']);
    final riskFlags = mapInt(_dossier, ['risk_flags', 'riskFlags']);
    final lastUpdate =
        _dateFrom(_dossier, ['last_session_entry_at', 'updated_at']) ??
        _dateFrom(_progress, ['updated_at']) ??
        (_notes.isNotEmpty ? _asDate(_notes.first) : null);
    final sharedCount = _notes
        .where((n) => _visibilityLabel(n) == 'Gedeeld')
        .length;
    final internalCount = _notes.length - sharedCount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── KPI grid ──
        Row(
          children: [
            Expanded(child: _kpiCardNew('Streak', '$streak', Icons.local_fire_department, Colors.red.shade600)),
            const SizedBox(width: 8),
            Expanded(child: _kpiCardNew('Attendance', '$attendance%', Icons.event_available, Colors.green.shade700)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _kpiCardNew('Doelen', goalsTotal > 0 ? '$goalsDone/$goalsTotal' : '$goalsDone', Icons.flag_outlined, Colors.amber.shade700)),
            const SizedBox(width: 8),
            Expanded(child: _kpiCardNew('Flags', '$riskFlags', Icons.shield_outlined, riskFlags == 0 ? Colors.green.shade700 : Colors.red.shade700)),
          ],
        ),
        const SizedBox(height: 12),
        // ── Dossier status (Container+boxShadow) ──
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: GymiesColors.darkBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.description_outlined, color: GymiesColors.darkBlue, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Dossier status',
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_notes.length} entries',
                    style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _statusChip(
                    icon: Icons.schedule_rounded,
                    label: 'Bijgewerkt ${_fmtDate(lastUpdate, withTime: false)}',
                    bg: Colors.blue.shade50,
                    fg: Colors.blue.shade800,
                  ),
                  _statusChip(
                    icon: Icons.visibility_rounded,
                    label: '$sharedCount gedeeld',
                    bg: Colors.green.shade50,
                    fg: Colors.green.shade800,
                  ),
                  _statusChip(
                    icon: Icons.lock_outline_rounded,
                    label: '$internalCount intern',
                    bg: Colors.orange.shade50,
                    fg: Colors.orange.shade800,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Coach Radar (Container+boxShadow) ──
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.radar_rounded, color: Colors.amber.shade700, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Coach radar',
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _radarRow(
                icon: Icons.trending_up_rounded,
                text:
                    mapStr(_progress, [
                      'next_best_action',
                      'next_action',
                    ]).isNotEmpty
                    ? mapStr(_progress, ['next_best_action', 'next_action'])
                    : 'Get started!',
              ),
              _radarRow(
                icon: Icons.task_alt_rounded,
                text: mapStr(_dossier, ['last_homework', 'homework']).isNotEmpty
                    ? 'Huiswerk: ${mapStr(_dossier, ['last_homework', 'homework'])}'
                    : 'Nog geen huiswerk geregistreerd.',
              ),
              _radarRow(
                icon: Icons.visibility_rounded,
                text: mapStr(_dossier, ['last_visibility']).isNotEmpty
                    ? 'Zichtbaarheid: ${mapStr(_dossier, ['last_visibility'])}'
                    : 'Nog geen visibility policy.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timelineTab() {
    final filteredNotes = _notes
        .where((n) =>
            _noteFilter.isEmpty ||
            _lineValue(mapStr(n, ['body', 'note', 'text']), 'Focus')
                .toLowerCase()
                .contains(_noteFilter))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Zoek in notities...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (q) => setState(() => _noteFilter = q.toLowerCase()),
          ),
        ),
        if (filteredNotes.isEmpty)
          const Expanded(
            child: Center(child: Text('Nog geen sessie-entries.')),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: filteredNotes.length,
              itemBuilder: (_, i) {
                final n = filteredNotes[i];
                final title = mapStr(n, ['title', 'type']).isNotEmpty
                    ? mapStr(n, ['title', 'type'])
                    : 'Sessie-entry';
                final body = mapStr(n, ['body', 'note', 'text']);
                final date = _dateFrom(n, ['session_at', 'created_at', 'date', 'at']);
                final visibility = _visibilityLabel(n);
                final focus = _lineValue(body, 'Focus');
                final homework = _lineValue(body, 'Huiswerk');
                final energy = _lineValue(body, 'Energie');
                final performance = _lineValue(body, 'Performance');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: GoogleFonts.sora(fontWeight: FontWeight.w700),
                              ),
                            ),
                            _statusChip(
                              icon: visibility == 'Intern'
                                  ? Icons.lock_outline_rounded
                                  : Icons.visibility_rounded,
                              label: visibility,
                              bg: visibility == 'Intern'
                                  ? Colors.orange.shade100
                                  : Colors.green.shade100,
                              fg: visibility == 'Intern'
                                  ? Colors.orange.shade800
                                  : Colors.green.shade800,
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 20),
                              onPressed: () => _editNote(n),
                              tooltip: 'Bewerken',
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                        if (date != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _fmtDate(date, withTime: true),
                            style: GoogleFonts.sora(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (focus.isNotEmpty || homework.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (focus.isNotEmpty)
                                _statusChip(
                                  icon: Icons.my_location_rounded,
                                  label: 'Focus: $focus',
                                  bg: Colors.purple.shade50,
                                  fg: Colors.purple.shade800,
                                ),
                              if (homework.isNotEmpty && homework != '-')
                                _statusChip(
                                  icon: Icons.assignment_turned_in_outlined,
                                  label: 'Huiswerk: $homework',
                                  bg: Colors.teal.shade50,
                                  fg: Colors.teal.shade800,
                                ),
                            ],
                          ),
                        ],
                        if (energy.isNotEmpty || performance.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (energy.isNotEmpty && energy != '-')
                                _statusChip(
                                  icon: Icons.bolt_rounded,
                                  label: 'Energie: $energy',
                                  bg: Colors.amber.shade50,
                                  fg: Colors.amber.shade800,
                                ),
                              if (performance.isNotEmpty && performance != '-')
                                _statusChip(
                                  icon: Icons.speed_rounded,
                                  label: 'Performance: $performance',
                                  bg: Colors.blue.shade50,
                                  fg: Colors.blue.shade800,
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          body.isEmpty ? '-' : body,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _goalsTab() {
    final goalsRaw = mapPick(_dossier, ['goals', 'goal_list', 'targets']);
    final goals = goalsRaw is List
        ? goalsRaw.map((e) => (e as Map).cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text('Doelenstatus', style: GoogleFonts.sora()),
            subtitle: Text(
              goals.isEmpty
                  ? 'Nog geen doelen ingesteld.'
                  : '${goals.length} actief doel(en)',
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (goals.isEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            padding: const EdgeInsets.all(12),
            child: Text(
              'Voeg doelen toe via backend of volgende iteratie UI.',
              style: GoogleFonts.sora(),
            ),
          )
        else
          ...goals.map(
            (g) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: ListTile(
                title: Text(
                  mapStr(g, ['title', 'name']).isNotEmpty
                      ? mapStr(g, ['title', 'name'])
                      : 'Doel',
                  style: GoogleFonts.sora(),
                ),
                subtitle: Text(
                  mapStr(g, ['status', 'progress']).isNotEmpty
                      ? mapStr(g, ['status', 'progress'])
                      : g.toString(),
                  style: GoogleFonts.sora(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _uploadingVideo = false;

  Future<void> _addClientVideo() async {
    Haptics.selection();
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final path = file.path;
    if (path.isEmpty) return;
    setState(() => _uploadingVideo = true);
    try {
      await context.read<GymiesApi>().postTrainerClientVideo(
        clientUserId: widget.clientUserId,
        filePath: path,
        title: file.name,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video toegevoegd'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _deleteClientVideo(String videoId) async {
    Haptics.heavy();
    final confirm = await GymiesDialog.destructive(
      context,
      title: 'Video verwijderen',
      message: 'Weet je zeker dat je deze video wilt verwijderen?',
      confirmLabel: 'Verwijderen',
      cancelLabel: 'Annuleren',
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<GymiesApi>().deleteTrainerClientVideo(
        clientUserId: widget.clientUserId,
        videoId: videoId,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video verwijderd')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Widget _videosTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Instructievideo\'s voor ${widget.clientName}',
                      style: GoogleFonts.sora(
                        fontSize: 18,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _uploadingVideo ? null : _addClientVideo,
                    icon: _uploadingVideo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: Text(_uploadingVideo ? 'Uploaden...' : 'Video toevoegen'),
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Alleen deze klant kan deze video\'s bekijken in zijn dossier.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_videos.isEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.videocam_off_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'Nog geen video\'s',
                  style: GoogleFonts.sora(fontSize: 16, color: GymiesColors.darkBlue),
                ),
                const SizedBox(height: 4),
                Text(
                  'Voeg instructievideo\'s toe die alleen deze klant kan bekijken.',
                  style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ..._videos.map((v) {
            final id = mapStr(v, ['id']);
            final title = mapStr(v, ['title', 'name']).isNotEmpty
                ? mapStr(v, ['title', 'name'])
                : 'Video';
            final url = mapStr(v, ['url', 'video_url', 'src']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.play_circle_outline, color: GymiesColors.darkBlue, size: 20),
                  ),
                  title: Text(title, style: GoogleFonts.sora()),
                  subtitle: url.isNotEmpty
                      ? Text(
                          'Bekijk in dossier',
                          style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                        )
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteClientVideo(id),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _betalingenTab() {
    if (_payments.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.payment_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'Geen betaalde sessies',
                  style: GoogleFonts.sora(fontSize: 18, color: GymiesColors.darkBlue),
                ),
                const SizedBox(height: 4),
                Text(
                  'Betaalde sessies van deze klant verschijnen hier.',
                  style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _payments.length,
      itemBuilder: (_, i) {
        final p = _payments[i];
        final amountCents = mapInt(p, ['amount_cents', 'amountCents']);
        final paidAt = mapStr(p, ['paid_at', 'paidAt']);
        final sessionDate = mapStr(p, ['session_date', 'sessionDate']);
        final ref = mapStr(p, ['reference_id', 'referenceId']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.euro, color: GymiesColors.darkBlue, size: 20),
              ),
              title: Text(
                '€ ${(amountCents / 100).toStringAsFixed(2)}',
                style: GoogleFonts.sora(fontSize: 16, color: GymiesColors.darkBlue),
              ),
              subtitle: Text(
                [
                  if (sessionDate.isNotEmpty) 'Sessie: $sessionDate',
                  if (paidAt.isNotEmpty) 'Betaald: ${_fmtDate(DateTime.tryParse(paidAt))}',
                  if (ref.isNotEmpty) 'Ref: $ref',
                ].where((s) => s.isNotEmpty).join(' • '),
                style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        );
      },
    );
  }

  Widget _internalTab() {
    final summary = mapStr(_dossier, ['summary', 'notes', 'internal_notes']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Interne trainernotities',
                style: GoogleFonts.sora(
                  fontSize: 18,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                summary.isEmpty ? 'Nog geen interne notities.' : summary,
                style: GoogleFonts.sora(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon) {
    return _kpiCardNew(label, value, icon, GymiesColors.darkBlue);
  }

  Widget _kpiCardNew(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: color, size: 13),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: GoogleFonts.sora(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: GymiesColors.darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _radarRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: GymiesColors.darkBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 12, color: GymiesColors.darkBlue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<SubscriptionEntitlementsService>().coachToolsEnabled;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: GymiesColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  widget.clientName.length >= 2
                      ? '${widget.clientName[0]}${widget.clientName.split(' ').length > 1 ? widget.clientName.split(' ').last[0] : widget.clientName[1]}'.toUpperCase()
                      : (widget.clientName.isNotEmpty ? widget.clientName[0].toUpperCase() : '?'),
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.clientName,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.clientEmail.isNotEmpty)
                    Text(
                      widget.clientEmail,
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        bottom: GymiesSegmentTabBar(
          controller: _tabController,
          tabs: const ['Overzicht', 'Timeline', 'Doelen', 'Video\'s', 'Betalingen', 'Intern'],
          isScrollable: true,
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _createSessionEntry,
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
              icon: const Icon(Icons.add_chart_rounded),
              label: Text(_saving ? 'Opslaan...' : 'Nieuwe entry'),
            )
          : null,
      body: _error != null
          ? Center(child: Text(_error!))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!canEdit)
                  Material(
                    color: Colors.amber.shade100,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.amber.shade900,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Dossier is alleen-lezen. Upgrade naar Pro om te bewerken.',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _overviewTab(),
                      _timelineTab(),
                      _goalsTab(),
                      _videosTab(),
                      _betalingenTab(),
                      _internalTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
