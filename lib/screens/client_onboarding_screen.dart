

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/generated/app_localizations.dart';
import '../config/app_config.dart';
import '../utils/haptics.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
/// SharedPreferences key: true als client onboarding is voltooid/overgeslagen.
const _kClientOnboardingDoneKey = 'gymies_client_onboarding_done';

/// Controleer of client onboarding al is afgerond.
/// Checkt server (onboarding_completed_at in /me) met local fallback.
Future<bool> isClientOnboardingDone([GymiesApi? api]) async {
  final prefs = await SharedPreferences.getInstance();
  // Probeer server-check
  if (api != null) {
    try {
      final me = await api.getMe();
      final serverDone = me['onboarding_completed_at'];
      if (serverDone != null && serverDone.toString().isNotEmpty) {
        await prefs.setBool(_kClientOnboardingDoneKey, true);
        return true;
      }
    } catch (e) {
      // Fail-open: Server check failed, fall back to local preferences
      if (kDebugMode) debugPrint('[ClientOnboarding] Server check failed: $e');
    }
  }
  return prefs.getBool(_kClientOnboardingDoneKey) ?? false;
}

/// Markeer client onboarding als afgerond.
/// Slaat op in SharedPreferences + server (fire-and-forget).
Future<void> markClientOnboardingDone([GymiesApi? api]) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kClientOnboardingDoneKey, true);
  // Sync naar server
  if (api != null) {
    try {
      await api.updateMe(
        onboardingCompletedAt: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (e) {
      // Fail-open: Server sync optional, local preference already saved
      if (kDebugMode) debugPrint('[ClientOnboarding] Server sync failed: $e');
    }
  }
}

/// Client onboarding: 3 stappen intro voor nieuwe klanten.
///
/// Stap 0 — Welkom: uitleg hoe GYMIES werkt (zoek, boek, train)
/// Stap 1 — Profiel: naam + stad invullen (optioneel)
/// Stap 2 — Klaar: CTA naar trainer-ontdekking
///
/// Kan op elk moment overgeslagen worden met "Overslaan".
class ClientOnboardingScreen extends StatefulWidget {
  const ClientOnboardingScreen({super.key, required this.onComplete});

  /// Callback wanneer onboarding voltooid of overgeslagen is.
  final VoidCallback onComplete;

  @override
  State<ClientOnboardingScreen> createState() => _ClientOnboardingScreenState();
}

class _ClientOnboardingScreenState extends State<ClientOnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _saving = false;

  // Profiel velden (stap 1)
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();

  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    // Pre-fill met bestaande user data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthService>().user;
      if (user != null) {
        final name = (user['display_name'] ?? user['first_name'] ?? '')
            .toString()
            .trim();
        final city = (user['city'] ?? '').toString().trim();
        if (name.isNotEmpty) _nameController.text = name;
        if (city.isNotEmpty) _cityController.text = city;
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _cityController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _complete() async {
    // BUG FIX: Prevent multiple clicks by checking _saving state
    if (_saving) return;
    final api = context.read<GymiesApi>();
    // Sla optioneel profiel op als er iets is ingevuld
    final name = _nameController.text.trim();
    final city = _cityController.text.trim();
    if (name.isNotEmpty || city.isNotEmpty) {
      setState(() => _saving = true);
      try {
        await api.updateMe(
          displayName: name.isNotEmpty ? name : null,
          city: city.isNotEmpty ? city : null,
        );
      } on ApiException catch (e) {
        if (kDebugMode) debugPrint('[ClientOnboarding] Profiel opslaan mislukt: ${e.message}');
      } catch (e) {
        if (kDebugMode) debugPrint('[ClientOnboarding] Profiel opslaan fout: $e');
      }
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    await markClientOnboardingDone(api);
    widget.onComplete();
  }

  Future<void> _skip() async {
    // BUG FIX: Prevent multiple clicks by checking _saving state
    if (_saving) return;
    final api = context.read<GymiesApi>();
    setState(() => _saving = true);
    try {
      await markClientOnboardingDone(api);
      widget.onComplete();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GymiesColors.darkBlue,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeController,
          child: Column(
            children: [
              // Top bar met skip knop
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Terug knop (niet op eerste pagina)
                    if (_currentPage > 0)
                      IconButton(
                        onPressed: () {
                          Haptics.selection();
                          _previousPage();
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white70,
                      )
                    else
                      const SizedBox(width: 48),
                    // Pagina indicator
                    _PageIndicator(currentPage: _currentPage, totalPages: 3),
                    // Skip knop
                    TextButton(
                      onPressed: _saving ? null : () {
                        Haptics.selection();
                        _skip();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                      ),
                      child: Text(S.of(context).skipLabel),
                    ),
                  ],
                ),
              ),
              // Pagina's
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _WelcomePage(onNext: _nextPage),
                    _ProfilePage(
                      nameController: _nameController,
                      cityController: _cityController,
                      onNext: _nextPage,
                    ),
                    _ReadyPage(
                      onComplete: _complete,
                      saving: _saving,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Pagina Indicator ──────────────────────────────────────────────────────

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentPage, required this.totalPages});

  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalPages, (i) {
        final isActive = i == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? GymiesColors.primary
                : GymiesColors.primary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ─── Stap 0: Welkom ────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          // App logo / titel
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: GymiesColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.fitness_center_rounded,
              color: GymiesColors.darkBlue,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Welkom bij ${AppConfig.appName}!',
            style: GoogleFonts.sora(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            '${S.of(context).jouwPersoonlijkeFitnessJourneyBegintHiern} In 3 simpele stappen:',
            style: GoogleFonts.sora(
              fontSize: 16,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // 3 stappen uitleg
          _StepExplainer(
            icon: Icons.search_rounded,
            title: S.of(context).zoek2,
            subtitle: S.of(context).vindDePerfecteTrainerBijJou,
          ),
          const SizedBox(height: 16),
          _StepExplainer(
            icon: Icons.event_available_rounded,
            title: 'Boek',
            subtitle: S.of(context).planEenSessieOpHetMoment,
          ),
          const SizedBox(height: 16),
          _StepExplainer(
            icon: Icons.emoji_events_rounded,
            title: 'Train',
            subtitle: S.of(context).bereikJeDoelenMetPersoonlijkeBegeleiding,
          ),
          const Spacer(flex: 3),
          // Volgende knop
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () {
                Haptics.light();
                onNext();
              },
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                S.of(context).getStarted,
                style: GoogleFonts.sora(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StepExplainer extends StatelessWidget {
  const _StepExplainer({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: GymiesColors.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: GymiesColors.primary, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.sora(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Stap 1: Profiel ───────────────────────────────────────────────────────

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.nameController,
    required this.cityController,
    required this.onNext,
  });

  final TextEditingController nameController;
  final TextEditingController cityController;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Icon(
            Icons.person_rounded,
            size: 64,
            color: GymiesColors.primary.withOpacity(0.8),
          ),
          const SizedBox(height: 20),
          Text(
            S.of(context).tellAboutYourself,
            style: GoogleFonts.sora(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            S.of(context).zoKunnenTrainersJeBeterVindennditIsOptioneelJeKuntHetLaterAanpassen,
            style: GoogleFonts.sora(
              fontSize: 14,
              color: Colors.white.withOpacity(0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // Naam veld
          _OnboardingTextField(
            controller: nameController,
            label: S.of(context).hoeMogenWeJeNoemen,
            hint: 'Bijv. Sara',
            icon: Icons.badge_outlined,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          // Stad veld
          _OnboardingTextField(
            controller: cityController,
            label: 'In welke stad train je?',
            hint: 'Bijv. Rotterdam',
            icon: Icons.location_on_outlined,
            textCapitalization: TextCapitalization.words,
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () {
                Haptics.light();
                onNext();
              },
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                S.of(context).nextAction,
                style: GoogleFonts.sora(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _OnboardingTextField extends StatelessWidget {
  const _OnboardingTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.35),
            ),
            prefixIcon: Icon(
              icon,
              color: GymiesColors.primary.withOpacity(0.7),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withOpacity(0.15),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withOpacity(0.15),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: GymiesColors.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Stap 2: Klaar! ────────────────────────────────────────────────────────

class _ReadyPage extends StatelessWidget {
  const _ReadyPage({required this.onComplete, this.saving = false});

  final VoidCallback onComplete;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              color: GymiesColors.primary,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            S.of(context).youAreReady,
            style: GoogleFonts.sora(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '${S.of(context).ontdekTrainersInJouwBuurtEnBoeknjeEersteSessie} Lets go!',
            style: GoogleFonts.sora(
              fontSize: 16,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Drie voordelen
          _BenefitChip(
            icon: Icons.verified_rounded,
            text: S.of(context).gecertificeerdeTrainers,
          ),
          const SizedBox(height: 10),
          _BenefitChip(
            icon: Icons.schedule_rounded,
            text: 'Flexibel boeken op jouw tempo',
          ),
          const SizedBox(height: 10),
          _BenefitChip(
            icon: Icons.payments_rounded,
            text: 'Veilig betalen via Mollie',
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: saving ? null : () {
                Haptics.light();
                onComplete();
              },
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
                disabledBackgroundColor:
                    GymiesColors.primary.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: GymiesColors.darkBlue,
                      ),
                    )
                  : const Icon(Icons.explore_rounded),
              label: Text(
                saving ? S.of(context).trainersCanFindYou : S.of(context).discoverTrainers,
                style: GoogleFonts.sora(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BenefitChip extends StatelessWidget {
  const _BenefitChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: GymiesColors.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: GymiesColors.primary, size: 20),
          const SizedBox(width: 12),
          Text(
            text,
            style: GoogleFonts.sora(
              color: Colors.white.withOpacity(0.85),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
