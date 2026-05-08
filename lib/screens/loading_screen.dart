import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../config/timing_constants.dart';
import '../theme/gymies_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/force_update_service.dart';
import 'client_sessions_screen.dart';
import 'client_trainer_profile_screen.dart';
import 'login_register_screen.dart';
import 'shells/trainer_shell.dart';
import 'shells/client_shell.dart';
import 'trainer_subscription_screen.dart';
import 'trainer_onboarding_screen.dart';
import 'control_tower_screen.dart';
import 'shells/gym_shell.dart';
import '../services/deep_link_service.dart';
import '../l10n/generated/app_localizations.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    this.initialPaymentBookingId,
    this.initialTrainerSlug,
    this.initialBuddyUri,
    this.initialDashboardUri,
    this.initialPasswordResetUri,
    this.initialGymRegisterUri,
    this.initialSubscriptionTier,
    this.initialMollieConnectSuccess = false,
    this.initialMandaatComplete = false,
  });

  /// Bij cold start via gymies://payment/complete?booking_id=X
  final String? initialPaymentBookingId;

  /// Bij cold start via gymies.nl/t/{slug} of gymies://t/{slug}
  final String? initialTrainerSlug;

  /// Bij cold start via gymies://buddy/join?booking_id=X&trainer_id=Y
  final Uri? initialBuddyUri;

  /// Bij cold start via gymies://trainer/sessions, gymies://client/messages, etc.
  final Uri? initialDashboardUri;

  /// Bij cold start via gymies://wachtwoord-reset?token=X&email=Y
  final Uri? initialPasswordResetUri;

  /// Bij cold start via gymies://gym/register?token=X
  final Uri? initialGymRegisterUri;

  /// Bij cold start via gymies://subscription/complete?tier=pro
  final String? initialSubscriptionTier;

  /// Bij cold start via gymies://mollie-connect/success
  final bool initialMollieConnectSuccess;

  /// Bij cold start via gymies://onboarding/mandaat-complete
  final bool initialMandaatComplete;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late List<AnimationController> _letterControllers;
  late final String _text;
  bool _hasNavigated = false;
  Timer? _navigateTimer;
  int _authPollCount = 0;

  /// Max keer dat we wachten op auth laden (30 × 200ms = 6s).
  /// Daarna gaan we door als niet-ingelogd — voorkomt eeuwig wit scherm.
  static const int _maxAuthPollAttempts = 30;

  @override
  void initState() {
    super.initState();
    _text = AppConfig.appName;
    _navigateTimer = Timer(TimingConstants.loadingTimeout, () {
      if (!mounted || _hasNavigated) return;
      _navigateToNext(); // _hasNavigated wordt gezet in _navigateToNext na succesauteur
    });
    _logoController = AnimationController(
      duration: TimingConstants.loadingFadeIn,
      vsync: this,
    );
    _letterControllers = List.generate(
      _text.length,
      (_) => AnimationController(
        duration: TimingConstants.loadingFadeOut,
        vsync: this,
      ),
    );
    // Start na eerste frame – voorkomt null in AnimationController bij hot reload / snelle dispose
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startAnimations();
    });
  }

  Future<void> _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    try {
      if (!_logoController.isAnimating && !_logoController.isCompleted) {
        _logoController.forward();
      }
    } catch (e) {
      // Fail-open: Logo animation optional
      if (kDebugMode) debugPrint('[LoadingScreen] Logo animation failed: $e');
    }
    for (int i = 0; i < _letterControllers.length; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      try {
        final c = _letterControllers[i];
        if (!c.isAnimating && !c.isCompleted) {
          c.forward();
        }
      } catch (e) {
        // Fail-open: Letter animation optional
        if (kDebugMode) debugPrint('[LoadingScreen] Letter animation failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _navigateTimer?.cancel();
    _logoController.dispose();
    for (final c in _letterControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _navigateToNext() async {
    final auth = context.read<AuthService>();
    // Wacht tot loadStoredAuth klaar is – maar met een maximum om infinite loop te voorkomen.
    // Na _maxAuthPollAttempts × 200ms gaan we gewoon door (gebruiker ziet login scherm).
    if (auth.loadingStored && mounted && _authPollCount < _maxAuthPollAttempts) {
      _authPollCount++;
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_hasNavigated) _navigateToNext();
      });
      return;
    }
    if (auth.loadingStored) {
      if (kDebugMode) debugPrint('[LoadingScreen] Auth laden duurde te lang ($_authPollCount polls) — ga door als niet-ingelogd');
    }
    if (_hasNavigated) return;

    // ── Force Update Check ────────────────────────────────────────────────
    // Controleert of de app versie nog ondersteund wordt door de backend.
    // Bij te oude versie: toont blokkerende "Update nu" dialog.
    if (mounted) {
      final api = context.read<ApiClient>();
      final canContinue = await ForceUpdateService.checkAndBlock(context, api);
      if (!canContinue) return; // App geblokkeerd door force update dialog
    }

    // ── Biometrische authenticatie (als ingelogd + biometric ingeschakeld) ──
    if (auth.isLoggedIn) {
      final bio = BiometricAuthService.instance;
      final bioEnabled = await bio.isEnabled;
      final bioAvailable = await bio.isAvailable;

      if (bioEnabled && bioAvailable) {
        if (kDebugMode) debugPrint('[LoadingScreen] Biometric auth ingeschakeld — start verificatie');
        final success = await bio.authenticateForAppOpen();
        if (!success) {
          // Gebruiker heeft biometric geweigerd/geannuleerd → ga naar login
          if (kDebugMode) debugPrint(S.of(context).loadingscreenBiometricAuthMisluktLoginScherm);
          if (!mounted) return;
          _hasNavigated = true;
          _navigateTimer?.cancel();
          await Navigator.of(context).pushAndRemoveUntil(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const LoginRegisterScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
            (route) => false,
          );
          return;
        }
        if (kDebugMode) debugPrint(S.of(context).loadingscreenBiometricAuthGelukt);
      }
    }

    _hasNavigated = true;
    _navigateTimer?.cancel(); // Stop timer — navigatie is gestart
    final Widget destination;
    if (auth.isLoggedIn) {
      if (auth.isAdmin) {
        destination = const ControlTowerScreen();
      } else if (auth.isTrainer) {
        destination = const TrainerShell();
      } else if (auth.isGymMember) {
        destination = const GymShell();
      } else {
        destination = const ClientShell();
      }
    } else {
      destination = const LoginRegisterScreen();
    }
    // ignore: use_build_context_synchronously
    await Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(-1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
      (route) => false,
    );

    // Cold start via gymies://payment/complete?booking_id=X: ga naar sessies
    final bookingId = widget.initialPaymentBookingId;
    if (bookingId != null &&
        bookingId.isNotEmpty &&
        auth.isLoggedIn &&
        !auth.isTrainer &&
        !auth.isAdmin &&
        mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientSessionsScreen(
            paymentReturnBookingId: bookingId,
          ),
        ),
      );
    }

    // Cold start via gymies.nl/t/{slug}: ga naar trainerprofiel
    final trainerSlug = widget.initialTrainerSlug;
    if (trainerSlug != null &&
        trainerSlug.trim().isNotEmpty &&
        mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientTrainerProfileScreen(
            trainerSlug: trainerSlug.trim(),
          ),
        ),
      );
      return;
    }

    // Cold start via gymies://buddy/join: trainerprofiel voor vriend (ook zonder login)
    final buddyUri = widget.initialBuddyUri;
    if (buddyUri != null && mounted) {
      final screen = DeepLinkService.screenFromUri(buddyUri);
      if (screen != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      }
      return;
    }

    // Cold start via gymies://wachtwoord-reset: wachtwoord resetten (geen login vereist)
    final passwordResetUri = widget.initialPasswordResetUri;
    if (passwordResetUri != null && mounted) {
      final screen = DeepLinkService.screenFromUri(passwordResetUri);
      if (screen != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      }
      return;
    }

    // Cold start via gymies://gym/register?token=X: gym registratie (geen login vereist)
    final gymRegisterUri = widget.initialGymRegisterUri;
    if (gymRegisterUri != null && mounted) {
      final screen = DeepLinkService.screenFromUri(gymRegisterUri);
      if (screen != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      }
      return;
    }

    // Cold start via gymies://subscription/complete?tier=pro: abonnement-scherm na betaling
    final subscriptionTier = widget.initialSubscriptionTier;
    if (subscriptionTier != null &&
        subscriptionTier.trim().isNotEmpty &&
        auth.isLoggedIn &&
        auth.isTrainer &&
        mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TrainerSubscriptionScreen(
            paymentReturnTier: subscriptionTier.trim(),
          ),
        ),
      );
      return;
    }

    // Cold start via gymies://mollie-connect/success: navigeer op basis van rol
    if (widget.initialMollieConnectSuccess && auth.isLoggedIn && mounted) {
      if (auth.isTrainer || auth.isGymOwner) {
        final screen = DeepLinkService.mollieConnectSuccessScreen(auth);
        if (screen != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => screen),
          );
          return;
        }
      }
    }

    // Cold start via gymies://onboarding/mandaat-complete: SEPA mandaat afgerond
    if (widget.initialMandaatComplete &&
        auth.isLoggedIn &&
        auth.isTrainer &&
        mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const TrainerOnboardingScreen(mandaatComplete: true),
        ),
      );
      return;
    }

    // Cold start via gymies://trainer/sessions, gymies://client/messages, etc.
    final dashboardUri = widget.initialDashboardUri;
    if (dashboardUri != null && auth.isLoggedIn && mounted) {
      final screen = DeepLinkService.screenFromUri(dashboardUri);
      if (screen != null) {
        final host = dashboardUri.host.toLowerCase();
        final isTrainerRoute = host == S.of(context).trainer2;
        final isClientRoute = host == 'client';
        if (isTrainerRoute && auth.isTrainer) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
        } else if (isClientRoute && !auth.isTrainer && !auth.isAdmin) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Logo - boven aan, mooi gecentreerd
            Expanded(
              flex: 3,
              child: AnimatedBuilder(
                animation: _logoController,
                builder: (context, child) {
                  return Opacity(opacity: _logoController.value, child: child);
                },
                child: Center(
                  child: Image.asset(
                    'assets/imgs/LOGOBG1.png',
                    fit: BoxFit.contain,
                    height: MediaQuery.of(context).size.height * 0.22,
                  ),
                ),
              ),
            ),
            // Tekst GYMIES - letter voor letter
            Expanded(
              flex: 2,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_text.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedBuilder(
                        animation: _letterControllers[index],
                        builder: (context, child) {
                          return SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: const Offset(1.5, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: _letterControllers[index],
                                    curve: Curves.elasticOut,
                                  ),
                                ),
                            child: FadeTransition(
                              opacity: _letterControllers[index],
                              child: Text(
                                _text[index],
                                style: GoogleFonts.sora(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
