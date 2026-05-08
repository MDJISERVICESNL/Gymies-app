

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/trainer.dart';
import '../utils/haptics.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/trainer_state_views.dart';
/// Scherm met alle reviews van een trainer.
class ClientTrainerReviewsScreen extends StatefulWidget {
  const ClientTrainerReviewsScreen({
    super.key,
    required this.trainer,
  });

  final Trainer trainer;

  @override
  State<ClientTrainerReviewsScreen> createState() =>
      _ClientTrainerReviewsScreenState();
}

class _ClientTrainerReviewsScreenState extends State<ClientTrainerReviewsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reviews = [];
  double? _ratingAvg;
  int _count = 0;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getTrainerReviews(widget.trainer.userId);
      if (!mounted) return;
      final data = res['data'];
      final list = data is List
          ? data.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _reviews = list;
        final rawAvg = res['rating_avg'] != null
            ? (res['rating_avg'] is num
                ? (res['rating_avg'] as num).toDouble()
                : double.tryParse(res['rating_avg'].toString()))
            : null;
        _ratingAvg = rawAvg?.clamp(0.0, 5.0);
        _count = res['count'] is int ? res['count'] as int : list.length;
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
        _error = S.of(context).konReviewsNietLaden;
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
    final trainerName = widget.trainer.displayName.trim().isNotEmpty
        ? widget.trainer.displayName.trim()
        : S.of(context).trainer;
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
                      child: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Reviews – $trainerName',
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
                      // ── Rating summary card ──
                      if (_ratingAvg != null || _count > 0)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                if (_ratingAvg != null) ...[
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.star_rounded,
                                      size: 30,
                                      color: Colors.amber.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _ratingAvg!.toStringAsFixed(1),
                                        style: GoogleFonts.sora(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: GymiesColors.darkBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$_count review${_count == 1 ? '' : 's'}',
                                        style: GoogleFonts.sora(
                                          color: Colors.grey.shade600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  // Mini star bar
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(5, (i) {
                                          final star = i + 1;
                                          return Padding(
                                            padding: const EdgeInsets.only(left: 2),
                                            child: Icon(
                                              star <= _ratingAvg!.round()
                                                  ? Icons.star_rounded
                                                  : Icons.star_outline_rounded,
                                              color: Colors.amber.shade600,
                                              size: 18,
                                            ),
                                          );
                                        }),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (_reviews.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                          child: Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: GymiesColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.rate_review_outlined,
                                  size: 34,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                S.of(context).nogGeenReviews,
                                style: GoogleFonts.sora(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: GymiesColors.darkBlue,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                S.of(context).weesDeEersteDieEenBeoordelingAchterlaatNaEenSessie,
                                style: GoogleFonts.sora(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        ..._reviews.map((r) => _ReviewCard(review: r)),
                      ],
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = mapInt(review, ['rating']).clamp(0, 5);
    final message = mapStr(review, ['message', 'body', 'text']);
    final isAnonymous = review['is_anonymous'] == true;
    final clientName = isAnonymous ? 'Anoniem' : mapStr(review, ['client_name', 'clientName', 'author']);
    if (clientName.isEmpty && !isAnonymous) {
      // fallback
    }
    final displayName = clientName.isEmpty ? 'Anoniem' : clientName;
    final createdAt = mapStr(review, ['created_at', 'createdAt', 'date']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar circle with initial
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: GymiesColors.primary.withOpacity(0.2),
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.sora(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                        if (createdAt.isNotEmpty)
                          Text(
                            _formatDate(createdAt),
                            style: GoogleFonts.sora(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: Colors.amber.shade600,
                      size: 18,
                    ),
                  );
                }),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  style: GoogleFonts.sora(
                    color: Colors.grey.shade800,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              // ── Review foto ──
              if (_photoUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _showFullPhoto(context, _photoUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _photoUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _photoUrl {
    final raw = review['photo_url'];
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    // Relatief pad → absoluut maken met base URL
    if (s.startsWith('http')) return s;
    return s; // Flutter's Image.network zal het pad gebruiken
  }

  static void _showFullPhoto(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return raw;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
  }
}
