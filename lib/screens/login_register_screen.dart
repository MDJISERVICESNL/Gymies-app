import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/gymies_theme.dart';
import '../config/app_config.dart';
import '../config/timing_constants.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/biometric_auth_service.dart';
import '../services/gymies_api.dart';
import '../utils/haptics.dart';
import 'control_tower_screen.dart';
import 'shells/client_shell.dart';
import 'shells/trainer_shell.dart';
import 'verify_email_screen.dart';
import 'widgets/gymies_dialog.dart';

/// Login/Register scherm met professionele GYMIES branding.
///
/// Layout:
///   - Hero header (gradient dark blue) met logo + tagline
///   - Witte form-area met rounded top die over de header valt
///   - Tab toggle (Inloggen / Registreren)
///   - Form content
class LoginRegisterScreen extends StatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  State<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Hero header ──
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [GymiesColors.darkBlue, Color(0xFF2A4F7F)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                child: Column(
                  children: [
                    Text(
                      AppConfig.appName,
                      style: GoogleFonts.sora(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).taglineText,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.75),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: GymiesColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── White form area met rounded top ──
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // ── Tab toggle ──
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: GymiesColors.darkBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: GymiesColors.primary,
                        unselectedLabelColor: const Color(0xFF6B7280),
                        labelStyle: GoogleFonts.sora(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelStyle: GoogleFonts.sora(fontSize: 15),
                        dividerHeight: 0,
                        tabs: [
                          Tab(text: S.of(context).login),
                          Tab(text: S.of(context).createAccount),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // ── Tab content ──
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _LoginTab(
                            auth: auth,
                            onSwitchToRegister: () =>
                                _tabController.animateTo(1),
                          ),
                          _RegisterTab(
                            auth: auth,
                            onSwitchToLogin: () =>
                                _tabController.animateTo(0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// LOGIN TAB
// ═══════════════════════════════════════════════════════════════════

class _LoginTab extends StatefulWidget {
  final AuthService auth;
  final VoidCallback? onSwitchToRegister;

  const _LoginTab({required this.auth, this.onSwitchToRegister});

  @override
  State<_LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends State<_LoginTab> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;

  /// Brute-force bescherming: teller voor opeenvolgende mislukte pogingen.
  int _failCount = 0;
  /// Tijdstip tot wanneer nieuwe pogingen geblokkeerd zijn (null = niet geblokkeerd).
  DateTime? _lockedUntil;
  /// Timer voor het aftellen van de lockout-periode (herbouwt UI elke seconde).
  Timer? _lockTimer;

  /// Berekent de verplichte wachttijd na n mislukte pogingen (exponentieel, max 5 minuten).
  Duration _lockDuration(int fails) {
    if (fails < 3) return Duration.zero;
    final seconds = (TimingConstants.lockoutBaseSeconds * (1 << (fails - 3))).clamp(TimingConstants.lockoutBaseSeconds, TimingConstants.lockoutMaxSeconds);
    return Duration(seconds: seconds);
  }

  /// Start een countdown-timer die de knop elke seconde bijwerkt totdat de lockout voorbij is.
  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_lockedUntil == null || !DateTime.now().isBefore(_lockedUntil!)) {
        _lockTimer?.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _submitting = false;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) return;

    // Throttle check: controleer of de gebruiker nog in de lockout-periode zit.
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      final remaining = _lockedUntil!.difference(DateTime.now()).inSeconds + 1;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).connectionFailed),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
      return;
    }
    if (kDebugMode) debugPrint('[AUTH_DEBUG] Login _submit – email: ${_email.text.trim()}');
    // Keyboard verbergen bij submit
    FocusManager.instance.primaryFocus?.unfocus();
    Haptics.light();
    setState(() => _submitting = true);
    try {
      final user = await widget.auth.login(
        _email.text.trim(),
        _password.text,
        rememberMe: _rememberMe,
      );
      if (kDebugMode) debugPrint('[AUTH_DEBUG] Login geslaagd – user keys: ${user.keys.toList()}');
      if (kDebugMode) debugPrint('[AUTH_DEBUG] Na _persist: auth.token=${widget.auth.token?.length ?? 0} chars, isLoggedIn=${widget.auth.isLoggedIn}');
      // Reset throttle bij succesvolle login.
      _failCount = 0;
      _lockedUntil = null;
      if (!mounted) return;

      // ── Face ID / Touch ID opt-in (éénmalig na eerste login) ──
      await _offerBiometricOptIn();

      if (!mounted) return;
      // Navigeer direct met user uit login-response; token is al gezet in AuthService
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => widget.auth.isAdminUser(user)
              ? const ControlTowerScreen()
              : (widget.auth.isTrainerUser(user)
                  ? const TrainerShell()
                  : const ClientShell()),
        ),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] Login ApiException: ${e.statusCode} – ${e.message}');
      if (kDebugMode && e.body != null) debugPrint('[AUTH_DEBUG] Response body: ${e.body}');
      // Tel alleen authenticatiefouten mee (401/422) voor throttle – geen netwerkfouten.
      if (e.statusCode == 401 || e.statusCode == 422) {
        _failCount++;
        final lockDur = _lockDuration(_failCount);
        if (lockDur > Duration.zero) {
          _lockedUntil = DateTime.now().add(lockDur);
          _startLockTimer();
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AUTH_DEBUG] Login Catch: $e');
      if (kDebugMode) debugPrint('[AUTH_DEBUG] StackTrace: $st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.of(context).connectionFailed,
            ),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Bied Face ID / Touch ID opt-in aan na eerste succesvolle login.
  Future<void> _offerBiometricOptIn() async {
    final bio = BiometricAuthService.instance;

    final alreadyAsked = await bio.hasBeenAsked;
    if (alreadyAsked) return;
    final available = await bio.isAvailable;
    if (!available) return;
    if (!mounted) return;

    final label = await bio.biometricLabel;

    if (!mounted) return;
    final accepted = await GymiesDialog.custom<bool>(
      context,
      title: '$label inschakelen?',
      subtitle: S.of(context).logSnellerInMet(label),
      icon: label == 'Face ID'
          ? Icons.face
          : label == 'Touch ID'
              ? Icons.fingerprint
              : Icons.lock_outline_rounded,
      barrierDismissible: false,
      actions: [
        GymiesDialogAction(
          label: 'Nee, bedankt',
          returnValue: false,
        ),
        GymiesDialogAction(
          label: 'Ja, activeer',
          isPrimary: true,
          returnValue: true,
        ),
      ],
    );

    await bio.markAsked();

    if (accepted == true) {
      final verified = await bio.authenticate(
        reason: 'Bevestig $label om het in te schakelen',
      );
      if (verified) {
        await bio.setEnabled(true);
      }
    }
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController(text: _email.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => _ForgotPasswordDialog(
        emailController: emailController,
        onSuccess: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── E-mail veld met icoon ──
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: GoogleFonts.sora(color: GymiesColors.darkBlue, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'E-mailadres',
                hintStyle: GoogleFonts.sora(
                  color: const Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20, color: Color(0xFF9CA3AF)),
                filled: false,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: GymiesColors.darkBlue,
                    width: 1.5,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.red.shade400,
                    width: 1.5,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.red.shade400,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return S.of(context).vulJeEmailIn;
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                  return S.of(context).vulEenGeldigEmailadresIn;
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            // ── Wachtwoord veld met icoon ──
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              style: GoogleFonts.sora(color: GymiesColors.darkBlue, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Wachtwoord',
                hintStyle: GoogleFonts.sora(
                  color: const Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF9CA3AF)),
                filled: false,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: GymiesColors.darkBlue,
                    width: 1.5,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.red.shade400,
                    width: 1.5,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.red.shade400,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF9CA3AF),
                    size: 20,
                  ),
                  onPressed: () {
                    Haptics.selection();
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return S.of(context).vulJeWachtwoordIn;
                if (v.length < 8) return 'Minimaal 8 tekens vereist';
                return null;
              },
            ),
            const SizedBox(height: 10),
            // ── Onthoud mij + wachtwoord vergeten op één rij ──
            Row(
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: (v) {
                      Haptics.light();
                      setState(() => _rememberMe = v ?? false);
                    },
                    activeColor: GymiesColors.darkBlue,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    Haptics.light();
                    setState(() => _rememberMe = !_rememberMe);
                  },
                  child: Text(
                    S.of(context).rememberMe,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Haptics.selection();
                    _showForgotPasswordDialog(context);
                  },
                  child: Text(
                    S.of(context).forgotten,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // ── Inloggen knop met throttle ──
            Builder(builder: (context) {
              final isLocked = _lockedUntil != null &&
                  DateTime.now().isBefore(_lockedUntil!);
              final remaining = isLocked
                  ? _lockedUntil!.difference(DateTime.now()).inSeconds + 1
                  : 0;
              return _GymiesButton(
                text: _submitting
                    ? S.of(context).bezig
                    : isLocked
                        ? '${S.of(context).wait} $remaining ${S.of(context).seconds}…'
                        : S.of(context).login,
                onPressed: (_submitting || isLocked) ? null : _submit,
              );
            }),
            const SizedBox(height: 24),
            const SizedBox(height: 20),
            // ── Switch naar registreren ──
            Center(
              child: GestureDetector(
                onTap: () {
                  Haptics.selection();
                  widget.onSwitchToRegister?.call();
                },
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.sora(fontSize: 13, color: const Color(0xFF6B7280)),
                    children: [
                      const TextSpan(text: S.of(context).nogGeenAccount),
                      TextSpan(
                        text: S.of(context).registerNow,
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// REGISTER TAB — 3 stappen
// ═══════════════════════════════════════════════════════════════════

enum _UserRole { klant, trainer }

enum _RegisterGender { male, female }

enum _PasswordStrength { weak, medium, strong }

class _RegisterTab extends StatefulWidget {
  final AuthService auth;
  final VoidCallback? onSwitchToLogin;

  const _RegisterTab({required this.auth, this.onSwitchToLogin});

  @override
  State<_RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<_RegisterTab> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _phone = TextEditingController();
  final _referralCode = TextEditingController();
  final _inviteCode = TextEditingController();
  final _cityController = TextEditingController();
  String? _selectedCity;
  _UserRole _role = _UserRole.klant;
  _RegisterGender? _gender;
  bool _newsletterSubscribe = false;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  bool _obscurePassword = true;
  late final VoidCallback _onPasswordChanged;

  /// Huidige stap (0 = rol/geslacht, 1 = e-mail/wachtwoord, 2 = optioneel + akkoord)
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _onPasswordChanged = () => setState(() {});
    _password.addListener(_onPasswordChanged);
  }

  static _PasswordStrength _passwordStrength(String s) {
    if (s.isEmpty) return _PasswordStrength.weak;
    final hasLetter = s.contains(RegExp(r'[a-zA-Z]'));
    final hasDigit = s.contains(RegExp(r'[0-9]'));
    if (s.length >= 8 && hasLetter && hasDigit) return _PasswordStrength.strong;
    if (s.length >= 6 && (hasLetter || hasDigit)) {
      return _PasswordStrength.medium;
    }
    return _PasswordStrength.weak;
  }

  /// Beschikbare steden (actieve launch regio's in Nederland).
  static const List<String> _availableCities = [
    'Amsterdam',
    'Rotterdam',
    'Den Haag',
    'Utrecht',
    'Eindhoven',
    'Groningen',
    'Tilburg',
    'Almere',
    'Breda',
    'Nijmegen',
    'Arnhem',
    'Haarlem',
    'Enschede',
    'Apeldoorn',
    'Amersfoort',
    'Zaanstad',
    'Den Bosch',
    'Haarlemmermeer',
    'Zwolle',
    'Zoetermeer',
    'Leiden',
    'Maastricht',
    'Dordrecht',
    'Ede',
    'Leeuwarden',
  ];

  @override
  void dispose() {
    _password.removeListener(_onPasswordChanged);
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _phone.dispose();
    _referralCode.dispose();
    _inviteCode.dispose();
    _cityController.dispose();
    super.dispose();
  }

  bool _submitting = false;

  /// Valideer de huidige stap en ga door naar de volgende.
  void _nextStep() {
    if (_step == 0) {
      // Stap 1: rol + geslacht
      if (_role == _UserRole.klant && _gender == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).chooseGender),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
        return;
      }
      Haptics.light();
      setState(() => _step = 1);
    } else if (_step == 1) {
      // Stap 2: valideer e-mail + wachtwoord
      if (!(_formKey.currentState?.validate() ?? false)) return;
      Haptics.light();
      setState(() => _step = 2);
    }
  }

  void _prevStep() {
    if (_step > 0) {
      Haptics.selection();
      setState(() => _step--);
    }
  }

  Future<void> _submit() async {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).jeMoetAkkoordGaanMetDeAlgemeneVoorwaarden),
        ),
      );
      return;
    }
    if (!_acceptedPrivacy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).jeMoetAkkoordGaanMetHetPrivacybeleid),
        ),
      );
      return;
    }
    if (_submitting) return;
    // Keyboard verbergen bij submit
    FocusManager.instance.primaryFocus?.unfocus();
    Haptics.light();
    setState(() => _submitting = true);
    try {
      final email = _email.text.trim();
      final user = await widget.auth.register(
        email: email,
        password: _password.text,
        role: _role == _UserRole.klant ? 'client' : 'trainer',
        displayName: _displayName.text.trim().isEmpty
            ? null
            : _displayName.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        gender: _role == _UserRole.klant && _gender != null
            ? (_gender == _RegisterGender.male ? 'male' : 'female')
            : null,
        newsletterSubscribe: _newsletterSubscribe,
        referralCode: _referralCode.text.trim().isEmpty
            ? null
            : _referralCode.text.trim(),
        inviteCode: _inviteCode.text.trim().isEmpty
            ? null
            : _inviteCode.text.trim(),
        city: _selectedCity,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => widget.auth.isAdminUser(user)
              ? const ControlTowerScreen()
              : (widget.auth.isTrainerUser(user)
                  ? const TrainerShell()
                  : const ClientShell()),
        ),
        (route) => false,
      );
    } on EmailVerificationRequiredException catch (e) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: e.email)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Progress indicator ──
            _StepProgressBar(currentStep: _step, totalSteps: 3),
            const SizedBox(height: 20),

            // ── Step content ──
            if (_step == 0) _buildStep0(),
            if (_step == 1) _buildStep1(),
            if (_step == 2) _buildStep2(),

            const SizedBox(height: 24),

            // ── Switch naar inloggen ──
            Center(
              child: GestureDetector(
                onTap: () {
                  Haptics.selection();
                  widget.onSwitchToLogin?.call();
                },
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.sora(fontSize: 13, color: const Color(0xFF6B7280)),
                    children: [
                      const TextSpan(text: S.of(context).alEenAccount),
                      TextSpan(
                        text: 'Inloggen',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stap 0: Wie ben je? ──
  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).whoAreYou,
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          S.of(context).chooseYourRole,
          style: GoogleFonts.sora(
            fontSize: 13,
            color: const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 16),
        // ── Rolkeuze kaarten ──
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                icon: Icons.person_rounded,
                title: S.of(context).clientSingle,
                subtitle: S.of(context).zoekEnBoekTrainers,
                selected: _role == _UserRole.klant,
                onTap: () {
                  Haptics.selection();
                  setState(() => _role = _UserRole.klant);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RoleCard(
                icon: Icons.fitness_center_rounded,
                title: S.of(context).trainer,
                subtitle: S.of(context).startJeBusiness,
                selected: _role == _UserRole.trainer,
                onTap: () {
                  Haptics.selection();
                  setState(() {
                    _role = _UserRole.trainer;
                    _gender = null;
                  });
                },
              ),
            ),
          ],
        ),
        // ── Geslacht (alleen voor klant) ──
        if (_role == _UserRole.klant) ...[
          const SizedBox(height: 20),
          Text(
            S.of(context).gender,
            style: GoogleFonts.sora(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _GenderChip(
                  label: 'Man',
                  selected: _gender == _RegisterGender.male,
                  onTap: () {
                    Haptics.selection();
                    setState(() => _gender = _RegisterGender.male);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GenderChip(
                  label: 'Vrouw',
                  selected: _gender == _RegisterGender.female,
                  onTap: () {
                    Haptics.selection();
                    setState(() => _gender = _RegisterGender.female);
                  },
                ),
              ),
            ],
          ),
        ],
        // ── Stad selectie (voor zowel trainer als klant) ──
        const SizedBox(height: 20),
        Text(
          'Jouw stad',
          style: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'In welke stad ben je actief?',
          style: GoogleFonts.sora(
            fontSize: 12,
            color: const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return _availableCities;
            }
            return _availableCities.where((city) =>
                city.toLowerCase().contains(textEditingValue.text.toLowerCase()));
          },
          onSelected: (String selection) {
            setState(() => _selectedCity = selection);
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            // Sync met _cityController als er al een stad was geselecteerd
            if (_selectedCity != null && controller.text.isEmpty) {
              controller.text = _selectedCity!;
            }
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              onFieldSubmitted: (_) => onSubmitted(),
              onChanged: (value) {
                // Als de gebruiker handmatig typt en het exact matcht, sla op
                final match = _availableCities.where(
                    (c) => c.toLowerCase() == value.toLowerCase().trim());
                if (match.isNotEmpty) {
                  _selectedCity = match.first;
                } else {
                  // Sta ook vrije invoer toe als het geen match is
                  _selectedCity = value.trim().isNotEmpty ? value.trim() : null;
                }
              },
              style: GoogleFonts.sora(color: GymiesColors.darkBlue, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Zoek je stad...',
                hintStyle: GoogleFonts.sora(
                  color: const Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(Icons.location_city_rounded, size: 20, color: Color(0xFF9CA3AF)),
                filled: false,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: GymiesColors.darkBlue, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on_outlined, size: 18, color: GymiesColors.darkBlue),
                        title: Text(
                          option,
                          style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue),
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        _GymiesButton(
          text: S.of(context).volgendeStapLogin,
          onPressed: _nextStep,
          showArrow: true,
        ),
      ],
    );
  }

  // ── Stap 1: E-mail & wachtwoord ──
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Terug knop
        GestureDetector(
          onTap: _prevStep,
          child: Row(
            children: [
              Icon(Icons.arrow_back_rounded, size: 18, color: GymiesColors.darkBlue.withOpacity(0.6)),
              const SizedBox(width: 4),
              Text(S.of(context).terug, style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue.withOpacity(0.6))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          S.of(context).accountAanmaken,
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          S.of(context).vulJeEmailEnWachtwoordIn,
          style: GoogleFonts.sora(
            fontSize: 13,
            color: const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 16),
        _GymiesFormField(
          controller: _email,
          hint: 'E-mailadres',
          prefixIcon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          validator: (v) {
            if (v == null || v.trim().isEmpty) return S.of(context).vulJeEmailIn;
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
              return S.of(context).vulEenGeldigEmailadresIn;
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _GymiesFormField(
          controller: _password,
          hint: 'Wachtwoord',
          prefixIcon: Icons.lock_outline_rounded,
          obscure: _obscurePassword,
          autofillHints: const [AutofillHints.password],
          onObscureToggle: () {
            Haptics.selection();
            setState(() => _obscurePassword = !_obscurePassword);
          },
          validator: (v) {
            if (v == null || v.isEmpty) return S.of(context).vulEenWachtwoordIn;
            if (v.length < 8) return 'Minimaal 8 tekens';
            final strength = _passwordStrength(v);
            if (strength == _PasswordStrength.weak) {
              return S.of(context).wachtwoordTeZwakGebruikLettersN;
            }
            return null;
          },
        ),
        if (_password.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          _PasswordStrengthBar(strength: _passwordStrength(_password.text)),
        ],
        const SizedBox(height: 24),
        _GymiesButton(
          text: S.of(context).volgendeStapLogin,
          onPressed: _nextStep,
          showArrow: true,
        ),
      ],
    );
  }

  // ── Stap 2: Optionele info + akkoord ──
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Terug knop
        GestureDetector(
          onTap: _prevStep,
          child: Row(
            children: [
              Icon(Icons.arrow_back_rounded, size: 18, color: GymiesColors.darkBlue.withOpacity(0.6)),
              const SizedBox(width: 4),
              Text(S.of(context).terug, style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue.withOpacity(0.6))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          S.of(context).bijnaKlaar,
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          S.of(context).dezeVeldenZijnOptioneel,
          style: GoogleFonts.sora(
            fontSize: 13,
            color: const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 16),
        _GymiesFormField(
          controller: _displayName,
          hint: 'Weergavenaam',
          prefixIcon: Icons.badge_outlined,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            if (v.trim().length > 100) {
              return 'Weergavenaam mag maximaal 100 tekens zijn';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _GymiesFormField(
          controller: _phone,
          hint: 'Telefoonnummer',
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final cleaned = v.replaceAll(RegExp(r'[^0-9+]'), '');
            if (!RegExp(r'^(\+31|0)[1-9]\d{1,9}$').hasMatch(cleaned)) {
              return 'Geldig Nederlands telefoonnummer vereist (+31 of 06)';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _GymiesFormField(
          controller: _referralCode,
          hint: 'Referralcode',
          prefixIcon: Icons.card_giftcard_rounded,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 14),
        _GymiesFormField(
          controller: _inviteCode,
          hint: 'Uitnodigingscode (optioneel)',
          prefixIcon: Icons.vpn_key_outlined,
          textCapitalization: TextCapitalization.characters,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            if (!RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(v.trim())) {
              return 'Ongeldige uitnodigingscode';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),
        // ── Checkboxes ──
        _GymiesCheckbox(
          value: _acceptedTerms,
          onChanged: (v) {
            Haptics.light();
            setState(() => _acceptedTerms = v ?? false);
          },
          label: 'Ik ga akkoord met de ',
          linkText: 'Algemene voorwaarden',
          onLinkTap: () {
            Haptics.selection();
            launchUrl(
              Uri.parse(AppConfig.termsUrl),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        _GymiesCheckbox(
          value: _acceptedPrivacy,
          onChanged: (v) {
            Haptics.light();
            setState(() => _acceptedPrivacy = v ?? false);
          },
          label: S.of(context).ikGaAkkoordMetHet,
          linkText: 'Privacybeleid',
          onLinkTap: () {
            Haptics.selection();
            launchUrl(
              Uri.parse(AppConfig.privacyUrl),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        const SizedBox(height: 6),
        _GymiesCheckbox(
          value: _newsletterSubscribe,
          onChanged: (v) {
            Haptics.light();
            setState(() => _newsletterSubscribe = v ?? false);
          },
          label: S.of(context).aanmeldenVoorNieuwsbrief,
          subtitle: S.of(context).blijfOpDeHoogteVanTips,
        ),
        const SizedBox(height: 20),
        _GymiesButton(
          text: _submitting ? S.of(context).bezig : S.of(context).createAccount,
          onPressed: _submitting
              ? null
              : () {
                  Haptics.light();
                  _submit();
                },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STAP PROGRESS BAR
// ═══════════════════════════════════════════════════════════════════

class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        final isActive = i <= currentStep;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < totalSteps - 1 ? 6 : 0),
            child: Row(
              children: [
                // Stap cirkel
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isActive ? GymiesColors.darkBlue : const Color(0xFFE5E7EB),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: i < currentStep
                        ? const Icon(Icons.check_rounded, size: 14, color: GymiesColors.primary)
                        : Text(
                            '${i + 1}',
                            style: GoogleFonts.sora(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isActive ? GymiesColors.primary : const Color(0xFF9CA3AF),
                            ),
                          ),
                  ),
                ),
                // Lijn naar volgend punt
                if (i < totalSteps - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: i < currentStep
                          ? GymiesColors.darkBlue
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ROLKEUZE KAART
// ═══════════════════════════════════════════════════════════════════

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? GymiesColors.darkBlue.withOpacity(0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? GymiesColors.darkBlue : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? GymiesColors.primary.withOpacity(0.15)
                    : const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected ? GymiesColors.darkBlue : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.sora(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? GymiesColors.darkBlue : const Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.sora(
                fontSize: 11,
                color: const Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// GESLACHT CHIP
// ═══════════════════════════════════════════════════════════════════

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? GymiesColors.darkBlue.withOpacity(0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? GymiesColors.darkBlue : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? GymiesColors.darkBlue : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// WACHTWOORD STERKTE BAR
// ═══════════════════════════════════════════════════════════════════

class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.strength});
  final _PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color, double value) = switch (strength) {
      _PasswordStrength.weak => ('Zwak', Colors.red, 1 / 3),
      _PasswordStrength.medium => ('Matig', Colors.orange, 2 / 3),
      _PasswordStrength.strong => ('Sterk', Colors.green, 1.0),
    };
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.sora(fontSize: 12, color: color)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CHECKBOX
// ═══════════════════════════════════════════════════════════════════

class _GymiesCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final String? linkText;
  final VoidCallback? onLinkTap;
  final String? subtitle;

  const _GymiesCheckbox({
    required this.value,
    required this.onChanged,
    required this.label,
    this.linkText,
    this.onLinkTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: linkText != null
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.sora(
                    color: GymiesColors.darkBlue,
                    fontSize: 13,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Haptics.selection();
                    onLinkTap?.call();
                  },
                  child: Text(
                    linkText!,
                    style: GoogleFonts.sora(
                      color: GymiesColors.darkBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(
                  '.',
                  style: GoogleFonts.sora(
                    color: GymiesColors.darkBlue,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          : Text(
              label,
              style: GoogleFonts.sora(
                color: GymiesColors.darkBlue,
                fontSize: 13,
              ),
            ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: GoogleFonts.sora(
                color: GymiesColors.darkBlue.withOpacity(0.6),
                fontSize: 11,
              ),
            )
          : null,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      activeColor: GymiesColors.darkBlue,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// FORM FIELD — neutrale kleuren + prefix icoon
// ═══════════════════════════════════════════════════════════════════

class _GymiesFormField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback? onObscureToggle;
  final TextInputType? keyboardType;
  final TextCapitalization? textCapitalization;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;
  final List<String>? autofillHints;

  const _GymiesFormField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.onObscureToggle,
    this.keyboardType,
    this.textCapitalization,
    this.validator,
    this.prefixIcon,
    this.autofillHints,
  });

  @override
  State<_GymiesFormField> createState() => _GymiesFormFieldState();
}

class _GymiesFormFieldState extends State<_GymiesFormField> {
  late FocusNode _focusNode;
  String? _displayedError;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && _displayedError != null) {
      setState(() => _displayedError = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      obscureText: widget.obscure,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization ?? TextCapitalization.none,
      autofillHints: widget.autofillHints,
      validator: (value) {
        final error = widget.validator?.call(value);
        if (error != null && mounted) {
          _displayedError = error;
        }
        return error;
      },
      style: GoogleFonts.sora(color: GymiesColors.darkBlue, fontSize: 15),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: GoogleFonts.sora(
          color: const Color(0xFF9CA3AF),
          fontSize: 14,
        ),
        prefixIcon: widget.prefixIcon != null
            ? Icon(widget.prefixIcon, size: 20, color: const Color(0xFF9CA3AF))
            : null,
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFE5E7EB),
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFE5E7EB),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: GymiesColors.darkBlue,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.red.shade400,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.red.shade400,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: widget.onObscureToggle != null
            ? IconButton(
                icon: Icon(
                  widget.obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF9CA3AF),
                  size: 20,
                ),
                onPressed: widget.onObscureToggle,
              )
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// WACHTWOORD VERGETEN DIALOG
// ═══════════════════════════════════════════════════════════════════

class _ForgotPasswordDialog extends StatefulWidget {
  final TextEditingController emailController;
  final VoidCallback onSuccess;

  const _ForgotPasswordDialog({
    required this.emailController,
    required this.onSuccess,
  });

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final email = widget.emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = S.of(context).vulJeEmailadresIn);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Haptics.light();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<GymiesApi>().requestForgotPassword(email);
      if (!mounted) return;
      widget.onSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            S.of(context).checkJeEmailVoorInstructiesOmJeWachtwoordTeResetten,
          ),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = S.of(context).konVerzoekNietVersturenProbeerOpnieuw;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GymiesDialog(
      title: S.of(context).wachtwoordVergeten,
      headerIcon: Icons.lock_reset_rounded,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.of(context).vulJeEmailadresInWeSturenJeEenLinkOmJeWachtwoordTeResetten,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: S.of(context).email,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        GymiesDialogAction(
          label: S.of(context).annuleren,
          returnValue: null,
        ),
        GymiesDialogAction(
          label: _submitting ? S.of(context).bezig : 'Verstuur',
          isPrimary: true,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// PRIMAIRE KNOP
// ═══════════════════════════════════════════════════════════════════

class _GymiesButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool showArrow;

  const _GymiesButton({
    required this.text,
    this.onPressed,
    this.showArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: GymiesColors.darkBlue,
          foregroundColor: GymiesColors.primary,
          disabledBackgroundColor: GymiesColors.darkBlue.withOpacity(0.4),
          disabledForegroundColor: GymiesColors.primary.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
