import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/gymies_theme.dart';

/// Vervangt het herhaalde patroon:
///   body: _error != null ? ErrorView() : _loading ? LoadingView() : RefreshIndicator(...)
/// Gebruik in elk scherm als directe body-waarde.
class GymiesListBody extends StatelessWidget {
  const GymiesListBody({
    super.key,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.child,
    this.onLogout,
  });

  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final Widget child;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return TrainerErrorView(
        message: error!,
        onRetry: onRefresh,
        onLogout: onLogout,
      );
    }
    if (loading) return const TrainerLoadingView();
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: GymiesColors.primary,
      child: child,
    );
  }
}

class TrainerLoadingView extends StatelessWidget {
  const TrainerLoadingView({
    super.key,
    this.padding = const EdgeInsets.all(24),
  });

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: const Center(
        child: CircularProgressIndicator(color: GymiesColors.primary),
      ),
    );
  }
}

class TrainerErrorView extends StatelessWidget {
  const TrainerErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.onLogout,
    this.padding = const EdgeInsets.all(24),
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onLogout;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            if (onLogout != null)
              FilledButton(
                onPressed: onLogout,
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                ),
                child: Text(S.of(context).logInAgain),
              ),
            if (onLogout != null) const SizedBox(height: 8),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
              ),
              child: Text(S.of(context).retryAction),
            ),
          ],
        ),
      ),
    );
  }
}

class TrainerEmptyState extends StatelessWidget {
  const TrainerEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.actionIcon = Icons.refresh_rounded,
    this.onAction,
    this.secondaryActionLabel,
    this.secondaryActionIcon = Icons.open_in_new_rounded,
    this.onSecondaryAction,
    this.padding = const EdgeInsets.all(28),
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final IconData secondaryActionIcon;
  final VoidCallback? onSecondaryAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 16,
              color: GymiesColors.darkBlue,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
              ),
              icon: Icon(actionIcon),
              label: Text(actionLabel!),
            ),
          ],
          if (secondaryActionLabel != null && onSecondaryAction != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onSecondaryAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: GymiesColors.darkBlue,
                side: BorderSide(color: GymiesColors.darkBlue.withOpacity(0.4)),
              ),
              icon: Icon(secondaryActionIcon, size: 18),
              label: Text(secondaryActionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
