import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../utils/haptics.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/trainer_state_views.dart';

/// Klant-scherm voor dossier, doelen en gedeelde coach-notes.
/// Pro/Elite-trainers delen deze info met hun klanten.
class ClientDossierScreen extends StatefulWidget {
  const ClientDossierScreen({super.key});

  @override
  State<ClientDossierScreen> createState() => _ClientDossierScreenState();
}

class _ClientDossierScreenState extends State<ClientDossierScreen> {
  static const _metricWeight = 'weight';
  static const _metricPerformance = 'performance';
  static const _metricAttendance = 'attendance';

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _sharedDossier = {};
  Map<String, dynamic> _progress = {};
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _videos = [];
  String _selectedMetric = _metricWeight;

  DateTime? _dateFrom(Map<String, dynamic>? map, List<String> keys) {
    final raw = mapStr(map, keys);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  List<_ChartPoint> _pointsFromRaw(dynamic raw) {
    if (raw is List) {
      final points = <_ChartPoint>[];
      for (final v in raw) {
        if (v is num) {
          points.add(_ChartPoint(label: '', value: v.toDouble()));
        }
        if (v is Map) {
          final vMap = Map<String, dynamic>.from(v);
          final candidate = mapPick(vMap, ['value', 'score', 'weight']);
          final dateRaw =
              (mapStr(vMap, ['date', 'at', 'created_at'])).toString();
          final parsed = DateTime.tryParse(dateRaw);
          final label = parsed == null
              ? ''
              : '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}';
          if (candidate is num) {
            points.add(_ChartPoint(label: label, value: candidate.toDouble()));
          }
        }
      }
      if (points.isNotEmpty) {
        final picked = points.take(8).toList();
        if (picked.every((p) => p.label.isEmpty)) {
          for (var i = 0; i < picked.length; i++) {
            picked[i] = _ChartPoint(
              label: 'P${i + 1}',
              value: picked[i].value,
            );
          }
        }
        return picked;
      }
    }
    return const [];
  }

  List<_ChartPoint> _progressPoints() {
    dynamic raw;
    switch (_selectedMetric) {
      case _metricPerformance:
        raw =
            mapPick(_progress, ['performance_history', 'performance_series', 'performance_points']);
        break;
      case _metricAttendance:
        raw =
            mapPick(_progress, ['attendance_history', 'attendance_series', 'attendance_points']);
        break;
      default:
        raw =
            mapPick(_progress, ['weight_history', 'weight_series', 'history', 'series', 'points']);
    }
    final parsed = _pointsFromRaw(raw);
    if (parsed.isNotEmpty) return parsed;
    // Geen placeholder: toon lege chart als API geen data heeft.
    return const [];
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      Map<String, dynamic> sharedDossier = {};
      Map<String, dynamic> progress = {};
      List<Map<String, dynamic>> notes = [];
      try {
        sharedDossier = await api.getMySharedDossier();
      } on ApiException {
        sharedDossier = {};
      }
      try {
        progress = await api.getMyProgressSnapshot();
      } on ApiException {
        progress = {};
      }
      try {
        notes = await api.getMyCoachNotes();
      } on ApiException {
        notes = [];
      }
      List<Map<String, dynamic>> videos = [];
      try {
        videos = await api.getMyClientVideos();
      } on ApiException {
        videos = [];
      }
      if (!mounted) return;
      final sortedNotes = notes
        ..sort((a, b) {
          final da = _dateFrom(a, ['created_at', 'createdAt', 'date']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final db = _dateFrom(b, ['created_at', 'createdAt', 'date']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
      setState(() {
        _sharedDossier = sharedDossier;
        _progress = progress;
        _notes = sortedNotes;
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

  @override
  void initState() {
    super.initState();
    _load();
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
                        'Mijn dossier',
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
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildProgressCard(),
                  const SizedBox(height: 12),
                  _buildGoalsCard(),
                  const SizedBox(height: 12),
                  _buildVideosCard(),
                  const SizedBox(height: 12),
                  _buildCoachNotesCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final streak = mapInt(_progress, ['streak_days', 'streak', 'current_streak']);
    final goalsDone = mapInt(_progress, ['goals_done', 'goals_completed', 'goalsDone']);
    final goalsTotal = mapInt(_progress, ['goals_total', 'goalsTotal']);
    final attendance = mapInt(_progress, ['attendance', 'attendance_rate']);
    final nextAction = mapStr(_progress, ['next_best_action', 'nextAction']);
    final weight = mapStr(_progress, ['weight', 'weight_kg']);
    final fromDossier = mapInt(_sharedDossier, ['risk_flags', 'riskFlags']);

    final hasAny =
        streak > 0 || goalsTotal > 0 || attendance > 0 || fromDossier > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.trending_up_rounded, color: GymiesColors.darkBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Progressie & ritme',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasAny && nextAction.isEmpty)
              Text(
                'Je trainer deelt nog geen progressie. Bij Pro-trainers zie je hier je streak, doelen en ontwikkeling.',
                style: GoogleFonts.sora(color: Colors.grey.shade700, fontSize: 14),
              )
            else ...[
              if (streak > 0)
                _Line(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Streak',
                  value: '$streak ${streak == 1 ? 'dag' : 'dagen'}',
                ),
              if (goalsTotal > 0)
                _Line(
                  icon: Icons.flag_outlined,
                  label: 'Doelen',
                  value: '$goalsDone / $goalsTotal voltooid',
                ),
              if (weight.isNotEmpty)
                _Line(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Laatste meting',
                  value: weight,
                ),
              if (nextAction.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, size: 18, color: GymiesColors.darkBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          nextAction,
                          style: GoogleFonts.sora(
                            fontWeight: FontWeight.w600,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: _metricWeight, label: Text('Gewicht')),
                  ButtonSegment(value: _metricPerformance, label: Text('Prestatie')),
                  ButtonSegment(value: _metricAttendance, label: Text('Aanwezigheid')),
                ],
                selected: {_selectedMetric},
                onSelectionChanged: (v) {
                  Haptics.light();
                  setState(() => _selectedMetric = v.first);
                },
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(
                    GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (_) {
                  final points = _progressPoints();
                  if (points.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Geen grafiekdata voor deze metriek. Je trainer kan dit invullen via het dossier.',
                        style: GoogleFonts.sora(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }
                  return _ProgressMiniChart(points: points);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoalsCard() {
    final goalsRaw = mapPick(_sharedDossier, ['goals', 'goal_list', 'targets']) ??
        mapPick(_progress, ['goals', 'goal_list']);
    final goals = goalsRaw is List
        ? goalsRaw.map((e) => (e as Map).cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.flag_rounded, color: GymiesColors.darkBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Doelen',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (goals.isEmpty)
              Text(
                'Nog geen doelen ingesteld door je trainer. Doelen verschijnen hier zodra je trainer ze voor je invult.',
                style: GoogleFonts.sora(color: Colors.grey.shade700, fontSize: 14),
              )
            else
              ...goals.map(
                (g) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
                      child: Icon(
                        Icons.flag_outlined,
                        color: GymiesColors.darkBlue,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      mapStr(g, ['title', 'name']).isNotEmpty
                          ? mapStr(g, ['title', 'name'])
                          : 'Doel',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                    ),
                    subtitle: mapStr(g, ['status', 'progress']).isNotEmpty
                        ? Text(mapStr(g, ['status', 'progress']))
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showVideoPlayer(BuildContext context, String url, String title) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ClientVideoPlayerDialog(url: url, title: title),
    );
  }

  Widget _buildVideosCard() {
    if (_videos.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.videocam_rounded, color: GymiesColors.darkBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Video\'s van je trainer',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Instructievideo\'s die je trainer speciaal voor jou heeft toegevoegd.',
              style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ..._videos.map((v) {
              final title = mapStr(v, ['title', 'name']).isNotEmpty
                  ? mapStr(v, ['title', 'name'])
                  : 'Video';
              final url = mapStr(v, ['url', 'video_url', 'src']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.play_circle_outline,
                      color: GymiesColors.darkBlue,
                      size: 24,
                    ),
                  ),
                  title: Text(title, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                  trailing: url.isNotEmpty
                      ? const Icon(Icons.play_arrow_rounded, color: GymiesColors.primary)
                      : null,
                  onTap: url.isNotEmpty
                      ? () {
                        Haptics.light();
                        _showVideoPlayer(context, url, title);
                      }
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachNotesCard() {
    // Toon alleen notities die expliciet 'shared' zijn, of waarvan
    // visibility leeg is (API stuurt dan alleen gedeelde notities).
    final notes = _notes.where((n) {
      final vis = mapStr(n, ['visibility', 'shared']).toLowerCase();
      return vis.isEmpty || vis == 'shared' || vis == 'client';
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.note_rounded, color: GymiesColors.darkBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Coach notes',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Feedback en notities van je trainer na een sessie.',
              style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (notes.isEmpty)
              Text(
                'Nog geen coach notes. Je trainer kan na een sessie notities met je delen.',
                style: GoogleFonts.sora(color: Colors.grey.shade700, fontSize: 14),
              )
            else
              ...notes.take(10).map((n) {
                final title = mapStr(n, ['title', 'type', 'session_type']);
                final body = mapStr(n, ['body', 'note', 'text', 'message']);
                final created = _dateFrom(n, ['created_at', 'createdAt', 'date']);
                final trainer = mapStr(n, ['trainer_name', 'trainerName']);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Coach note' : title,
                        style: GoogleFonts.sora(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          body,
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (trainer.isNotEmpty || (created != null && created.year > 2000)) ...[
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (trainer.isNotEmpty) '— $trainer',
                            if (created != null && created.year > 2000)
                              '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}',
                          ].join(' · '),
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ChartPoint {
  const _ChartPoint({required this.label, required this.value});
  final String label;
  final double value;
}

class _ProgressMiniChart extends StatelessWidget {
  const _ProgressMiniChart({required this.points});
  final List<_ChartPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final values = points.map((e) => e.value).toList();
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: points.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final normalized = (p.value / safeMax).clamp(0.08, 1.0);
            final isLast = i == points.length - 1;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      p.value.toStringAsFixed(p.value == p.value.roundToDouble() ? 0 : 1),
                      style: GoogleFonts.sora(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isLast ? GymiesColors.darkBlue : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 82 * normalized,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: isLast
                              ? [GymiesColors.primary, GymiesColors.primary.withValues(alpha: 0.7)]
                              : [GymiesColors.primary.withValues(alpha: 0.6), GymiesColors.primary.withValues(alpha: 0.3)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      p.label,
                      style: GoogleFonts.sora(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: GymiesColors.darkBlue),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: GoogleFonts.sora(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.sora(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Videospeler in-app dialoog – alles blijft binnen de app.
class _ClientVideoPlayerDialog extends StatefulWidget {
  const _ClientVideoPlayerDialog({required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<_ClientVideoPlayerDialog> createState() => _ClientVideoPlayerDialogState();
}

class _ClientVideoPlayerDialogState extends State<_ClientVideoPlayerDialog> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _controller.play();
      }
    }).catchError((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () {
                    Haptics.selection();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: _controller.value.isInitialized
                ? _controller.value.aspectRatio
                : 16 / 9,
            child: _controller.value.isInitialized
                ? GestureDetector(
                    onTap: () {
                      Haptics.light();
                      _controller.value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                    },
                    child: VideoPlayer(_controller),
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                  onPressed: _controller.value.isInitialized
                      ? () {
                          Haptics.light();
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
