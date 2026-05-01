import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gymies_theme.dart';

/// Standaard AppBar voor alle Gymies-schermen.
/// Vervangt de herhaalde AppBar-boilerplate (backgroundColor, foregroundColor,
/// titel-stijl) die in elk scherm identiek was.
class GymiesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GymiesAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.onAvatarTap,
    this.avatarLabel,
  });

  final String title;
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
      title: Text(
        title,
        style: GoogleFonts.fjallaOne(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: allActions.isEmpty ? null : allActions,
      bottom: bottom,
    );
  }
}
