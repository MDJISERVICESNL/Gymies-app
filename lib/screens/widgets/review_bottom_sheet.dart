import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/gymies_theme.dart';
import '../../utils/haptics.dart';

/// ──────────────────────────────────────────────────────────────
/// Feature flag: zet op `true` om foto-upload bij reviews weer
/// in te schakelen. Backend + API ondersteunen het al volledig,
/// maar moderatie is nog niet gebouwd.
/// ──────────────────────────────────────────────────────────────
const bool _kPhotoUploadEnabled = false;

/// Labels die bij elke sterrenscore horen.
const _ratingLabels = <int, String>{
  1: 'Slecht',
  2: 'Matig',
  3: 'Oké',
  4: 'Goed',
  5: 'Heel goed!',
};

/// Resultaat dat terugkomt na het sluiten van de bottom sheet.
class ReviewResult {
  const ReviewResult({
    required this.rating,
    this.message,
    this.isAnonymous = false,
    this.photoPath,
  });

  final int rating;
  final String? message;
  final bool isAnonymous;
  final String? photoPath;
}

/// Toont een gepolijste bottom sheet waarmee de klant een review kan schrijven
/// met een geanimeerde sterrenpicker, tekstveld, foto-upload en anoniem-toggle.
///
/// Geeft `null` terug als de gebruiker annuleert, anders een [ReviewResult].
Future<ReviewResult?> showReviewBottomSheet(
  BuildContext context, {
  required String trainerName,
}) {
  return showModalBottomSheet<ReviewResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReviewSheet(trainerName: trainerName),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.trainerName});
  final String trainerName;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet>
    with SingleTickerProviderStateMixin {
  int _rating = 5;
  bool _isAnonymous = false;
  String? _photoPath;
  final _textController = TextEditingController();
  late final AnimationController _starBounce;

  @override
  void initState() {
    super.initState();
    _starBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _starBounce.dispose();
    super.dispose();
  }

  void _setRating(int star) {
    Haptics.selection();
    setState(() => _rating = star);
    _starBounce.forward(from: 0.0);
  }

  Future<void> _pickPhoto() async {
    Haptics.selection();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: Text(S.of(ctx).cameraLabel, style: GoogleFonts.sora()),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(S.of(ctx).galleryLabel, style: GoogleFonts.sora()),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 80,
    );
    if (picked != null && mounted) {
      setState(() => _photoPath = picked.path);
    }
  }

  void _removePhoto() {
    Haptics.selection();
    setState(() => _photoPath = null);
  }

  void _submit() {
    Haptics.selection();
    final msg = _textController.text.trim();
    Navigator.of(context).pop(
      ReviewResult(
        rating: _rating,
        message: msg.isEmpty ? null : msg,
        isAnonymous: _isAnonymous,
        photoPath: _kPhotoUploadEnabled ? _photoPath : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle + header ──
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: GymiesColors.darkBlue,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        S.of(context).giveRating,
                        style: GoogleFonts.sora(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sessie bij ${widget.trainerName}',
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Body ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Vraag
                  Text(
                    S.of(context).howWasYourSession,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Sterren picker ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final star = i + 1;
                      final isSelected = star <= _rating;
                      return GestureDetector(
                        onTap: () => _setRating(star),
                        child: _BouncingStar(
                          animation: _starBounce,
                          star: star,
                          isSelected: isSelected,
                          currentRating: _rating,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _ratingLabels[_rating] ?? '',
                      key: ValueKey(_rating),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Tekstveld ──
                  TextField(
                    controller: _textController,
                    maxLines: 3,
                    maxLength: 500,
                    style: GoogleFonts.sora(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: S.of(context).complimentOptional,
                      hintStyle: GoogleFonts.sora(
                        fontSize: 14,
                        color: Colors.grey.shade400,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: GymiesColors.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                      counterStyle: GoogleFonts.sora(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Foto upload (achter feature flag) ──
                  if (_kPhotoUploadEnabled) ...[
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _pickPhoto,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 1.5,
                                strokeAlign: BorderSide.strokeAlignInside,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.camera_alt_rounded,
                                  size: 24,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  S.of(context).photoLabel,
                                  style: GoogleFonts.sora(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_photoPath != null) ...[
                          const SizedBox(width: 10),
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(_photoPath!),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: _removePhoto,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Anoniem toggle ──
                  GestureDetector(
                    onTap: () {
                      Haptics.selection();
                      setState(() => _isAnonymous = !_isAnonymous);
                    },
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _isAnonymous
                                ? GymiesColors.darkBlue
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _isAnonymous
                                  ? GymiesColors.darkBlue
                                  : Colors.grey.shade400,
                              width: 1.5,
                            ),
                          ),
                          child: _isAnonymous
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.of(context).postAnonymously,
                                style: GoogleFonts.sora(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              Text(
                                S.of(context).nameNotShownOnReview,
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
                  ),
                  const SizedBox(height: 24),

                  // ── Versturen knop ──
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GymiesColors.primary,
                        foregroundColor: GymiesColors.darkBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(S.of(context).submitActionLabel),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Een ster met bounce-animatie wanneer de huidige rating verandert.
class _BouncingStar extends AnimatedWidget {
  const _BouncingStar({
    required Animation<double> animation,
    required this.star,
    required this.isSelected,
    required this.currentRating,
  }) : super(listenable: animation);

  final int star;
  final bool isSelected;
  final int currentRating;

  @override
  Widget build(BuildContext context) {
    final anim = listenable as Animation<double>;
    // Bounce alleen de ster die net geselecteerd is
    final isBouncing = star == currentRating;
    final scale = isBouncing ? 1.0 + (0.15 * (1.0 - anim.value)) : 1.0;
    return Transform.scale(
      scale: scale,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(
          isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 42,
          color: isSelected ? GymiesColors.primary : Colors.grey.shade300,
        ),
      ),
    );
  }
}
