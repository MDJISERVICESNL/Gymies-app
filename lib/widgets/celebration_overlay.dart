import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/milestone_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';

/// CelebrationOverlay
/// ──────────────────
/// Fullscreen confetti + achievement popup bij het bereiken van
/// een mijlpaal. Animateert confetti particles en toont een
/// mooi kaartje met de achievement info.
///
/// Gebruik:
/// ```dart
/// CelebrationOverlay.show(context, milestone);
/// ```
class CelebrationOverlay {
  CelebrationOverlay._();

  /// Toon de celebration overlay als een dialog.
  static Future<void> show(BuildContext context, Milestone milestone) async {
    Haptics.celebration();
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Celebration',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => _CelebrationDialog(milestone: milestone),
      transitionBuilder: (_, animation, __, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          child: child,
        );
      },
    );
  }
}

class _CelebrationDialog extends StatefulWidget {
  const _CelebrationDialog({required this.milestone});
  final Milestone milestone;

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _confettiController;
  late final AnimationController _cardController;
  final List<_ConfettiParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(() => setState(() {}));

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Genereer confetti particles
    for (int i = 0; i < 60; i++) {
      _particles.add(_ConfettiParticle(
        x: _random.nextDouble(),
        y: -_random.nextDouble() * 0.3,
        speed: 0.3 + _random.nextDouble() * 0.7,
        size: 4 + _random.nextDouble() * 8,
        color: _confettiColors[_random.nextInt(_confettiColors.length)],
        rotation: _random.nextDouble() * 360,
        rotationSpeed: (_random.nextDouble() - 0.5) * 10,
        drift: (_random.nextDouble() - 0.5) * 0.3,
      ));
    }

    _confettiController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _cardController.forward();
    });

    // Auto-dismiss na 4 seconden
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  static const _confettiColors = [
    Color(0xFFFEBE23), // Gymies goud
    Color(0xFF1E3A5F), // Gymies dark blue
    Color(0xFFFF6B6B), // Rood
    Color(0xFF4ECDC4), // Teal
    Color(0xFFFFE66D), // Licht goud
    Color(0xFFFF8C42), // Oranje
    Color(0xFFA8E6CF), // Mint
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Confetti layer
          ...(_confettiController.isAnimating
              ? _particles.map((p) => _buildParticle(p))
              : []),

          // Achievement card
          Center(
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _cardController,
                curve: Curves.elasticOut,
              ),
              child: _buildCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticle(_ConfettiParticle p) {
    final progress = _confettiController.value;
    final y = p.y + progress * p.speed * 1.5;
    final x = p.x + progress * p.drift;
    final rotation = p.rotation + progress * p.rotationSpeed * 360;
    final opacity = progress < 0.7 ? 1.0 : (1.0 - (progress - 0.7) / 0.3);

    return Positioned(
      left: x * MediaQuery.of(context).size.width,
      top: y * MediaQuery.of(context).size.height,
      child: Transform.rotate(
        angle: rotation * pi / 180,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Container(
            width: p.size,
            height: p.size * 0.6,
            decoration: BoxDecoration(
              color: p.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: GymiesColors.primary.withOpacity(0.3),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.milestone.emoji,
            style: const TextStyle(fontSize: 48),
          ),
          const SizedBox(height: 12),
          Text(
            widget.milestone.title,
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: GymiesColors.darkBlue,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.milestone.subtitle,
            style: GoogleFonts.sora(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: GymiesColors.accentLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'GYMIES',
              style: GoogleFonts.sora(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: GymiesColors.accent,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiParticle {
  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
    required this.drift,
  });

  final double x;
  final double y;
  final double speed;
  final double size;
  final Color color;
  final double rotation;
  final double rotationSpeed;
  final double drift;
}
