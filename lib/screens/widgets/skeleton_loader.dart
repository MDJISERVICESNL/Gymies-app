import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer skeleton loader voor verschillende content types.
///
/// ```dart
/// isLoading ? const SkeletonTrainerCard() : TrainerCard(trainer)
/// ```

/// Helper: shimmer kleuren
Color _baseColor(BuildContext context) => Colors.grey.shade200;

Color _highlightColor(BuildContext context) => Colors.grey.shade50;

Color _placeholderColor(BuildContext context) => Colors.white;

/// Skeleton voor een trainer kaart
class SkeletonTrainerCard extends StatelessWidget {
  const SkeletonTrainerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final placeholder = _placeholderColor(context);
    return Shimmer.fromColors(
      baseColor: _baseColor(context),
      highlightColor: _highlightColor(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: placeholder,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: placeholder,
                borderRadius: BorderRadius.circular(32),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 140, color: placeholder),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 200, color: placeholder),
                  const SizedBox(height: 6),
                  Container(height: 12, width: 100, color: placeholder),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton voor een lijst van trainer kaarten
class SkeletonTrainerList extends StatelessWidget {
  const SkeletonTrainerList({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: count,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (_, _) => const SkeletonTrainerCard(),
    );
  }
}

/// Skeleton voor een booking kaart
class SkeletonBookingCard extends StatelessWidget {
  const SkeletonBookingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final placeholder = _placeholderColor(context);
    return Shimmer.fromColors(
      baseColor: _baseColor(context),
      highlightColor: _highlightColor(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: placeholder,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(height: 14, width: 120, color: placeholder),
                Container(height: 14, width: 60, color: placeholder),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 12, width: double.infinity, color: placeholder),
            const SizedBox(height: 8),
            Container(height: 12, width: 180, color: placeholder),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(height: 32, width: 80,
                  decoration: BoxDecoration(color: placeholder, borderRadius: BorderRadius.circular(16)),
                ),
                const SizedBox(width: 8),
                Container(height: 32, width: 80,
                  decoration: BoxDecoration(color: placeholder, borderRadius: BorderRadius.circular(16)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic skeleton placeholder (rechthoek)
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _baseColor(context),
      highlightColor: _highlightColor(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: _placeholderColor(context),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
