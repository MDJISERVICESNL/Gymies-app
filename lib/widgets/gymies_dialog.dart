import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/ui_constants.dart';
import '../theme/gymies_theme.dart';
import '../l10n/generated/app_localizations.dart';

/// GymiesDialog — standardized dialog widget for the GYMIES app
/// Provides consistent styling, animations, and interaction patterns
class GymiesDialog extends StatelessWidget {
  const GymiesDialog({
    super.key,
    required this.title,
    required this.content,
    this.icon,
    this.iconColor,
    this.actions = const [],
    this.onClose,
    this.isDangerous = false,
  });

  /// Create a confirmation dialog (simple yes/no)
  /// Returns [true] if confirmed, [false] if cancelled
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String content,
    String confirmLabel = S.of(context).bevestigen,
    String cancelLabel = S.of(context).annuleren,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GymiesDialog(
        title: title,
        content: content,
        icon: icon,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Create a destructive action dialog (delete, logout, etc)
  /// Returns [true] if confirmed, [false] if cancelled
  static Future<bool?> destructive(
    BuildContext context, {
    required String title,
    required String content,
    String confirmLabel = S.of(context).verwijderen,
    String cancelLabel = S.of(context).annuleren,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GymiesDialog(
        title: title,
        content: content,
        icon: icon,
        isDangerous: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: UiConstants.errorRed,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Create an informational dialog (no actions, just dismiss)
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String content,
    String dismissLabel = 'Sluiten',
    IconData? icon,
    Color? iconColor,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => GymiesDialog(
        title: title,
        content: content,
        icon: icon,
        iconColor: iconColor,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(dismissLabel),
          ),
        ],
      ),
    );
  }

  final String title;
  final String content;
  final IconData? icon;
  final Color? iconColor;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final bool isDangerous;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: iconColor ?? (isDangerous ? UiConstants.errorRed : GymiesColors.darkBlue),
              size: 24,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.sora(
                fontSize: UiConstants.fontSizeDialogTitle,
                fontWeight: FontWeight.w700,
                color: GymiesColors.darkBlue,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        content,
        style: TextStyle(
          fontSize: UiConstants.fontSizeBody,
          color: Colors.grey.shade800,
          height: 1.5,
        ),
      ),
      actions: actions,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.dialogBorderRadius),
      ),
      backgroundColor: Colors.white,
      elevation: 8,
      actionsPadding: UiConstants.dialogActionsPadding,
    );
  }
}
