import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/ui_constants.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';

/// Scherm voor waitlist aanbiedingen - toont een pop-up slot dat beschikbaar is gekomen
/// en biedt de gebruiker 15 minuten om het in te claimen.
class WaitlistOfferScreen extends StatefulWidget {
  final String waitlistId;
  final String trainerName;
  final String sessionDate;
  final String sessionTime;
  final DateTime expiresAt;

  const WaitlistOfferScreen({
    Key? key,
    required this.waitlistId,
    required this.trainerName,
    required this.sessionDate,
    required this.sessionTime,
    required this.expiresAt,
  }) : super(key: key);

  @override
  State<WaitlistOfferScreen> createState() => _WaitlistOfferScreenState();
}

class _WaitlistOfferScreenState extends State<WaitlistOfferScreen> {
  late Timer _countdownTimer;
  late Duration _remainingTime;
  bool _isClaimingSession = false;
  bool _offerExpired = false;

  @override
  void initState() {
    super.initState();
    _updateRemainingTime();
    _startCountdownTimer();
  }

  void _updateRemainingTime() {
    final now = DateTime.now();
    _remainingTime = widget.expiresAt.difference(now);

    if (_remainingTime.isNegative) {
      _remainingTime = Duration.zero;
      _offerExpired = true;
    }
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() {
            _updateRemainingTime();
            if (_remainingTime.inSeconds <= 0) {
              _offerExpired = true;
            }
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer.cancel();
    super.dispose();
  }

  Future<void> _claimOffer() async {
    if (_offerExpired || _isClaimingSession) return;

    final api = context.read<GymiesApi>();
    setState(() => _isClaimingSession = true);
    Haptics.lightImpact();

    try {
      await api.claimGroupSessionWaitlist(widget.waitlistId);

      // Haptic feedback on success
      Haptics.successImpact();

      if (mounted) {
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Je plek is geclaimd! Tot zo.'),
            backgroundColor: GymiesColors.primary,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );

        // Pop after a brief delay
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } on ApiException catch (e) {
      Haptics.errorImpact();

      if (mounted) {
        setState(() => _isClaimingSession = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Fout bij claimen van plek'),
            backgroundColor: UiConstants.errorRed,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      Haptics.errorImpact();

      if (mounted) {
        setState(() => _isClaimingSession = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Er is iets fout gegaan. Probeer het later opnieuw.'),
            backgroundColor: UiConstants.errorRed,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double _getProgressValue() {
    final totalSeconds = widget.expiresAt.difference(
      widget.expiresAt.subtract(const Duration(minutes: 15)),
    ).inSeconds;
    final remainingSeconds = _remainingTime.inSeconds;

    if (totalSeconds == 0) return 0;
    return (remainingSeconds / totalSeconds).clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(
        title: 'Wachtlijstaanbod',
        showBackButton: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Celebration header
                _buildCelebrationHeader(),
                const SizedBox(height: 32),

                // Session details card
                _buildSessionCard(),
                const SizedBox(height: 32),

                // Countdown timer with progress
                _buildCountdownSection(),
                const SizedBox(height: 40),

                // Action buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrationHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: GymiesColors.accentLight,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '🎉',
              style: Theme.of(context).textTheme.displayLarge,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Er is een plek vrijgekomen!',
          style: GymiesTextStyles.h1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Je bent gekozen voor deze training',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade700,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSessionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trainer info
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: GymiesColors.accentLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '👤',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trainer',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.trainerName,
                      style: GymiesTextStyles.h3,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Session date
          _buildDetailRow(
            icon: '📅',
            label: 'Datum',
            value: widget.sessionDate,
          ),
          const SizedBox(height: 16),

          // Session time
          _buildDetailRow(
            icon: '🕐',
            label: 'Tijd',
            value: widget.sessionTime,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownSection() {
    if (_offerExpired) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
          border: Border.all(
            color: UiConstants.errorRed.withOpacity(0.3),
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                'Aanbieding verlopen',
                style: GymiesTextStyles.h3.copyWith(
                  color: UiConstants.errorRed,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Helaas is de aanbiedingstijd voorbij',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Nog tijd beschikbaar',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),

          // Circular countdown timer
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade100,
                  ),
                ),

                // Progress ring
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: _getProgressValue(),
                    strokeWidth: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      GymiesColors.primary,
                    ),
                  ),
                ),

                // Timer text in center
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _formatDuration(_remainingTime),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: GymiesColors.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'MM:SS',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Claim je plek nu!',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: GymiesColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Claim button (primary/gold)
        FilledButton(
          onPressed: _offerExpired || _isClaimingSession ? null : _claimOffer,
          style: FilledButton.styleFrom(
            backgroundColor: _offerExpired
                ? Colors.grey.shade400
                : GymiesColors.primary,
            foregroundColor: GymiesColors.darkBlue,
            padding: const EdgeInsets.symmetric(vertical: 16),
            disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(UiConstants.cardBorderRadius),
            ),
          ),
          child: _isClaimingSession
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      GymiesColors.darkBlue,
                    ),
                  ),
                )
              : Text(
                  _offerExpired ? 'Aanbieding verlopen' : 'Plek Claimen',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: GymiesColors.darkBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: 12),

        // Decline button (outline)
        OutlinedButton(
          onPressed: _isClaimingSession ? null : () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: GymiesColors.darkBlue,
            side: const BorderSide(
              color: GymiesColors.darkBlue,
              width: 2,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(UiConstants.cardBorderRadius),
            ),
          ),
          child: Text(
            'Nee, bedankt',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: GymiesColors.darkBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
