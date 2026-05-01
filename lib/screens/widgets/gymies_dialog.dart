import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/ui_constants.dart';
import '../../theme/gymies_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GymiesDialog — herbruikbare gestylede dialog voor de hele app
// ─────────────────────────────────────────────────────────────────────────────
// Vervangt alle plain AlertDialog() calls met een consistent design:
//   • Header: icon container (40×40) + titel + sluit-knop
//   • Optionele subtitle
//   • Content area (vrij widget)
//   • Action buttons (filled primary + text secondary)
//
// Gebruik de static helpers voor veelgebruikte patronen:
//   GymiesDialog.confirm(...)   → ja/nee bevestiging
//   GymiesDialog.destructive(...) → rode verwijder-actie
//   GymiesDialog.info(...)      → informatief met één knop
//   GymiesDialog.form(...)      → dialog met formulier-content
// ─────────────────────────────────────────────────────────────────────────────

/// Actie-knop definitie voor GymiesDialog.
class GymiesDialogAction {
  const GymiesDialogAction({
    required this.label,
    this.onPressed,
    this.returnValue,
    this.isPrimary = false,
    this.isDestructive = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final dynamic returnValue;
  final bool isPrimary;
  final bool isDestructive;
  final IconData? icon;
}

class GymiesDialog extends StatelessWidget {
  const GymiesDialog({
    super.key,
    this.headerIcon,
    required this.title,
    this.subtitle,
    this.content,
    this.actions,
    this.showCloseButton = true,
    this.headerIconColor,
    this.headerIconBgColor,
    this.maxContentHeight,
  });

  final IconData? headerIcon;
  final String title;
  final String? subtitle;
  final Widget? content;
  final List<GymiesDialogAction>? actions;
  final bool showCloseButton;
  final Color? headerIconColor;
  final Color? headerIconBgColor;
  final double? maxContentHeight;

  // ═══════════════════════════════════════════════════════════════════════════
  // Static helper: confirm dialog (ja/nee)
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.help_outline_rounded,
    String confirmLabel = 'Bevestigen',
    String cancelLabel = 'Annuleren',
    IconData? confirmIcon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GymiesDialog(
        headerIcon: icon,
        title: title,
        subtitle: message,
        actions: [
          GymiesDialogAction(
            label: confirmLabel,
            isPrimary: true,
            icon: confirmIcon,
            returnValue: true,
          ),
          GymiesDialogAction(
            label: cancelLabel,
            returnValue: false,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Static helper: destructive dialog (verwijderen/uitloggen)
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<bool?> destructive(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.warning_amber_rounded,
    String confirmLabel = 'Verwijderen',
    String cancelLabel = 'Annuleren',
    IconData? confirmIcon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GymiesDialog(
        headerIcon: icon,
        title: title,
        subtitle: message,
        headerIconColor: UiConstants.errorRed,
        headerIconBgColor: UiConstants.errorRed.withValues(alpha: 0.1),
        actions: [
          GymiesDialogAction(
            label: confirmLabel,
            isPrimary: true,
            isDestructive: true,
            icon: confirmIcon,
            returnValue: true,
          ),
          GymiesDialogAction(
            label: cancelLabel,
            returnValue: false,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Static helper: info dialog (één knop)
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
    String buttonLabel = 'Begrepen',
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => GymiesDialog(
        headerIcon: icon,
        title: title,
        subtitle: message,
        actions: [
          GymiesDialogAction(
            label: buttonLabel,
            isPrimary: true,
            returnValue: true,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Static helper: success dialog (groen icoon)
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> success(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.check_circle_outline_rounded,
    String buttonLabel = 'Top!',
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => GymiesDialog(
        headerIcon: icon,
        title: title,
        subtitle: message,
        headerIconColor: const Color(0xFF2E7D32),
        headerIconBgColor: const Color(0xFF2E7D32).withValues(alpha: 0.1),
        actions: [
          GymiesDialogAction(
            label: buttonLabel,
            isPrimary: true,
            returnValue: true,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Static helper: form dialog (custom content + knoppen)
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<T?> form<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    required Widget content,
    IconData icon = Icons.edit_rounded,
    String confirmLabel = 'Opslaan',
    String cancelLabel = 'Annuleren',
    IconData? confirmIcon,
    VoidCallback? onConfirm,
    double? maxContentHeight,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => GymiesDialog(
        headerIcon: icon,
        title: title,
        subtitle: subtitle,
        content: content,
        maxContentHeight: maxContentHeight,
        actions: [
          GymiesDialogAction(
            label: confirmLabel,
            isPrimary: true,
            icon: confirmIcon,
            onPressed: onConfirm,
          ),
          GymiesDialogAction(
            label: cancelLabel,
            returnValue: null,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Static helper: custom dialog (volledig zelf samenstellen)
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<T?> custom<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? content,
    IconData? icon,
    Color? iconColor,
    Color? iconBgColor,
    List<GymiesDialogAction>? actions,
    bool showCloseButton = true,
    double? maxContentHeight,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => GymiesDialog(
        headerIcon: icon,
        title: title,
        subtitle: subtitle,
        content: content,
        actions: actions,
        showCloseButton: showCloseButton,
        headerIconColor: iconColor,
        headerIconBgColor: iconBgColor,
        maxContentHeight: maxContentHeight,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final iconFg = headerIconColor ?? GymiesColors.primary;
    final iconBg =
        headerIconBgColor ?? GymiesColors.primary.withValues(alpha: 0.1);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(UiConstants.dialogBorderRadius),
      ),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header: icon + title + close ──
            Row(
              children: [
                if (headerIcon != null)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(headerIcon, color: iconFg, size: 20),
                  ),
                if (headerIcon != null) const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.sora(
                      fontSize: UiConstants.fontSizeH2,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
                if (showCloseButton)
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),

            // ── Subtitle ──
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle!,
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.45,
                  ),
                ),
              ),
            ],

            // ── Content ──
            if (content != null) ...[
              const SizedBox(height: 16),
              if (maxContentHeight != null)
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: maxContentHeight!),
                  child: SingleChildScrollView(child: content),
                )
              else
                content!,
            ],

            // ── Actions ──
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 20),
              ...actions!.map((a) => Padding(
                    padding: EdgeInsets.only(
                      bottom: a == actions!.last ? 0 : 10,
                    ),
                    child: SizedBox(
                      width: double.maxFinite,
                      child: _buildAction(context, a),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context, GymiesDialogAction action) {
    if (action.isPrimary) {
      final bg = action.isDestructive
          ? UiConstants.errorRed
          : GymiesColors.darkBlue;
      return FilledButton(
        onPressed: () {
          action.onPressed?.call();
          if (action.returnValue != null || action.onPressed == null) {
            Navigator.of(context).pop(action.returnValue);
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action.icon != null) ...[
              Icon(action.icon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              action.label,
              style: GoogleFonts.sora(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Secondary (text) button
    return TextButton(
      onPressed: () {
        action.onPressed?.call();
        Navigator.of(context).pop(action.returnValue);
      },
      style: TextButton.styleFrom(
        foregroundColor: action.isDestructive
            ? UiConstants.errorRed
            : GymiesColors.darkBlue,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.icon != null) ...[
            Icon(action.icon, size: 18),
            const SizedBox(width: 8),
          ],
          Text(
            action.label,
            style: GoogleFonts.sora(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
