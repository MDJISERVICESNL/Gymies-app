import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gymies_theme.dart';
import '../../utils/haptics.dart';

/// Reusable action icon button for GymiesAppBar.
///
/// Renders as a 34×34 rounded-square with a subtle gold-tinted background
/// and a gold icon. Used for context-specific actions (add, search, filter, …).
class GymiesAppBarAction extends StatelessWidget {
  const GymiesAppBarAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: GymiesColors.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: GymiesColors.primary),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/// Standaard AppBar voor alle Gymies-schermen.
/// Vervangt de herhaalde AppBar-boilerplate (backgroundColor, foregroundColor,
/// titel-stijl) die in elk scherm identiek was.
class GymiesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GymiesAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.actions,
    this.bottom,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.onAvatarTap,
    this.avatarLabel,
  });

  final String title;

  /// Optionele custom widget als titel (bijv. met subtitel of status indicator).
  /// Als opgegeven wordt deze gebruikt in plaats van de standaard Text(title).
  final Widget? titleWidget;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// Als opgegeven, wordt een avatar-knop rechts in de AppBar getoond.
  /// De eerste letter van [avatarLabel] wordt als initiaal gebruikt.
  final VoidCallback? onAvatarTap;
  final String? avatarLabel;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final allActions = [
      if (actions != null) ...actions!,
      if (onAvatarTap != null)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 17,
              backgroundColor: GymiesColors.primary,
              child: Text(
                (avatarLabel?.isNotEmpty == true ? avatarLabel![0] : '?')
                    .toUpperCase(),
                style: const TextStyle(
                  color: GymiesColors.darkBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
    ];

    return AppBar(
      backgroundColor: GymiesColors.darkBlue,
      foregroundColor: GymiesColors.primary,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      title: titleWidget ?? Text(
        title,
        style: GoogleFonts.sora(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: allActions.isEmpty ? null : allActions,
      bottom: bottom,
    );
  }
}
