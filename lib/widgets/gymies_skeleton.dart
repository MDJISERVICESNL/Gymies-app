import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/gymies_theme.dart';

/// GymiesSkeleton
/// ──────────────
/// Herbruikbare shimmer/skeleton loading widgets voor de hele app.
/// Vervangt spinners met content-placeholders die 2x sneller aanvoelen.
///
/// Gebruik:
/// ```dart
/// if (_loading) return GymiesSkeletonList(itemCount: 3);
/// // of:
/// if (_loading) return GymiesSkeletonCard();
/// ```

// ── Base shimmer wrapper ──────────────────────────────────────────────

class GymiesShimmer extends StatelessWidget {
  const GymiesShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade50,
      period: const Duration(milliseconds: 1200),
      child: child,
    );
  }
}

// ── Skeleton bone (een enkele placeholder balk) ───────────────────────

class _Bone extends StatelessWidget {
  const _Bone({
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

// ── Skeleton: Booking/Sessie kaart ────────────────────────────────────

class GymiesSkeletonCard extends StatelessWidget {
  const GymiesSkeletonCard({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    return GymiesShimmer(
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Bone(width: 40, height: 40, borderRadius: 20), // Avatar
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _Bone(width: 140, height: 14),
                      SizedBox(height: 6),
                      _Bone(width: 90, height: 12),
                    ],
                  ),
                ),
                const _Bone(width: 60, height: 24, borderRadius: 12), // Badge
              ],
            ),
            const SizedBox(height: 12),
            const _Bone(width: double.infinity, height: 12),
            const SizedBox(height: 6),
            const _Bone(width: 200, height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton: Lijst van kaarten ───────────────────────────────────────

class GymiesSkeletonList extends StatelessWidget {
  const GymiesSkeletonList({
    super.key,
    this.itemCount = 4,
    this.cardHeight = 120,
  });

  final int itemCount;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (_, __) => GymiesSkeletonCard(height: cardHeight),
    );
  }
}

// ── Skeleton: Trainer profiel pagina ──────────────────────────────────

class GymiesSkeletonProfile extends StatelessWidget {
  const GymiesSkeletonProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return GymiesShimmer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + naam
            Row(
              children: [
                const _Bone(width: 72, height: 72, borderRadius: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _Bone(width: 180, height: 18),
                      SizedBox(height: 8),
                      _Bone(width: 120, height: 14),
                      SizedBox(height: 6),
                      _Bone(width: 90, height: 14),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Bio
            const _Bone(width: double.infinity, height: 14),
            const SizedBox(height: 6),
            const _Bone(width: double.infinity, height: 14),
            const SizedBox(height: 6),
            const _Bone(width: 250, height: 14),
            const SizedBox(height: 20),
            // Tags
            Row(
              children: const [
                _Bone(width: 80, height: 28, borderRadius: 14),
                SizedBox(width: 8),
                _Bone(width: 100, height: 28, borderRadius: 14),
                SizedBox(width: 8),
                _Bone(width: 70, height: 28, borderRadius: 14),
              ],
            ),
            const SizedBox(height: 20),
            // Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _Bone(width: 80, height: 60, borderRadius: 12),
                _Bone(width: 80, height: 60, borderRadius: 12),
                _Bone(width: 80, height: 60, borderRadius: 12),
              ],
            ),
            const SizedBox(height: 20),
            // Beschikbaarheid slots
            const _Bone(width: 160, height: 16),
            const SizedBox(height: 12),
            Row(
              children: const [
                _Bone(width: 70, height: 36, borderRadius: 8),
                SizedBox(width: 8),
                _Bone(width: 70, height: 36, borderRadius: 8),
                SizedBox(width: 8),
                _Bone(width: 70, height: 36, borderRadius: 8),
                SizedBox(width: 8),
                _Bone(width: 70, height: 36, borderRadius: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton: Dashboard stat cards ────────────────────────────────────

class GymiesSkeletonStats extends StatelessWidget {
  const GymiesSkeletonStats({super.key, this.cardCount = 3});

  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return GymiesShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            cardCount,
            (_) => SizedBox(
              width: (MediaQuery.of(context).size.width - 44) / 2,
              child: Container(
                height: 80,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _Bone(width: 60, height: 10),
                    SizedBox(height: 8),
                    _Bone(width: 80, height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Skeleton: Volledige pagina ─────────────────────────────────────────

class GymiesSkeletonPage extends StatelessWidget {
  const GymiesSkeletonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const GymiesSkeletonStats(),
          const SizedBox(height: 20),
          GymiesShimmer(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const _Bone(width: 150, height: 18),
            ),
          ),
          const SizedBox(height: 12),
          const GymiesSkeletonList(itemCount: 3),
        ],
      ),
    );
  }
}
