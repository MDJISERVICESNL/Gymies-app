import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gymies_theme.dart';
import '../../utils/haptics.dart';

/// Unified segment-style tab bar used across all GYMIES screens.
///
/// Renders as a row of rounded segment buttons inside the AppBar bottom.
/// Active tab gets a subtle gold tint with border; inactive tabs are transparent.
///
/// Usage:
/// ```dart
/// GymiesAppBar(
///   title: 'Screen',
///   bottom: GymiesSegmentTabBar(
///     controller: _tabController,
///     tabs: const ['Tab 1', 'Tab 2', 'Tab 3'],
///   ),
/// ),
/// ```
class GymiesSegmentTabBar extends StatelessWidget implements PreferredSizeWidget {
  const GymiesSegmentTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.badges,
    this.onChanged,
    this.isScrollable = false,
  });

  /// The TabController that drives the tab selection.
  final TabController controller;

  /// Tab labels.
  final List<String> tabs;

  /// Optional badge counts per tab (same length as [tabs], null = no badge).
  final List<int?>? badges;

  /// Optional callback when a tab is tapped.
  final ValueChanged<int>? onChanged;

  /// If true, tabs scroll horizontally instead of filling the row equally.
  final bool isScrollable;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final children = <Widget>[];
        for (var i = 0; i < tabs.length; i++) {
          if (i > 0) children.add(const SizedBox(width: 6));
          final badge = (badges != null && i < badges!.length) ? badges![i] : null;
          children.add(
            isScrollable
                ? _SegmentTab(
                    label: tabs[i],
                    active: controller.index == i,
                    badge: badge,
                    onTap: () => _onTap(i),
                  )
                : Expanded(
                    child: _SegmentTab(
                      label: tabs[i],
                      active: controller.index == i,
                      badge: badge,
                      onTap: () => _onTap(i),
                    ),
                  ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: isScrollable
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: children),
                )
              : Row(children: children),
        );
      },
    );
  }

  void _onTap(int index) {
    Haptics.selection();
    controller.animateTo(index);
    onChanged?.call(index);
  }
}

// ── Individual segment tab ──────────────────────────────────────────
class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 32,
        decoration: BoxDecoration(
          color: active
              ? GymiesColors.primary.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: active
              ? Border.all(color: GymiesColors.primary.withOpacity(0.3))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge == null || !active)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: GoogleFonts.sora(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active
                          ? GymiesColors.primary
                          : Colors.white.withOpacity(0.55),
                    ),
                  ),
                ),
              ),
            if (badge == null || !active) const SizedBox.shrink(),
            if (badge != null && active) ...[
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: GymiesColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: GoogleFonts.sora(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (badge != null && !active) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: GoogleFonts.sora(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}
