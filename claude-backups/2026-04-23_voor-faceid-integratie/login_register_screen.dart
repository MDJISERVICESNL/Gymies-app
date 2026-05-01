import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/gymies_theme.dart';
import '../config/app_config.dart';
import '../config/timing_constants.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import 'dashboard_screen.dart';
import 'trainer_dashboard_screen.dart';
import 'control_tower_screen.dart';
import 'verify_email_screen.dart';

/// Login/Register scherm met GYMIES thema
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
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              AppConfig.appName,
              style: GoogleFonts.fjallaOne(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: GymiesColors.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: GymiesColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: GymiesColors.darkBlue,
                unselectedLabelColor: GymiesColors.darkBlue.withValues(
                  alpha: 0.7,
                ),
                labelStyle: GoogleFonts.fjallaOne(fontSize: 18),
                tabs: const [
                  Tab(text: 'Login'),
                  Tab(text: 'Register'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _LoginTab(
                    auth: auth,
                    onSwitchToRegister: () => _tabController.animateTo(1),
                  ),
                  _RegisterTab(
                    auth: auth,
                    onSwitchToLogin: () => _tabController.animateTo(0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
            content: Text('Te veel mislukte pogingen. Probeer opnieuw over $remaining seconden.'),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
      return;
    }
    if (kDebugMode) debugPrint('[AUTH_DEBUG] Login _submit – email: ${_email.text.trim()}');
    // Keyboard verbergen bij submit
    FocusManager.instance.primaryFocus?.unfocus();
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
      // Navigeer direct met user uit login-response; token is al gezet in AuthService
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => widget.auth.isAdminUser(user)
              ? const ControlTowerScreen()
              : (widget.auth.isTrainerUser(user)
                  ? const TrainerDashboardScreen()
                  : const DashboardScreen()),
        ),
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
              'Verbinding mislukt. Controleer je internet en probeer opnieuw.',
            ),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GymiesFormField(
              controller: _email,
              hint: 'E-mail',
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Vul je e-mail in';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                  return 'Vul een geldig e-mailadres in';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _GymiesFormField(
              controller: _password,
              hint: 'Wachtwoord',
              obscure: _obscurePassword,
              onObscureToggle: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Vul je wachtwoord in' : null,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: GymiesColors.darkBlue,
              value: _rememberMe,
              onChanged: (v) => setState(() => _rememberMe = v ?? false),
              title: Text(
                'Onthoud mij',
                style: GoogleFonts.fjallaOne(
                  fontSize: 14,
                  color: GymiesColors.darkBlue,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _showForgotPasswordDialog(context),
                child: Text(
                  'Wachtwoord vergeten?',
                  style: GoogleFonts.fjallaOne(
                    fontSize: 14,
                    color: GymiesColors.darkBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Visuele throttle-indicator: toon vergrendeld label als de gebruiker geblokkeerd is.
            Builder(builder: (context) {
              final isLocked = _lockedUntil != null &&
                  DateTime.now().isBefore(_lockedUntil!);
              final remaining = isLocked
                  ? _lockedUntil!.difference(DateTime.now()).inSeconds + 1
                  : 0;
              return _GymiesButton(
                text: _submitting
                    ? 'Bezig…'
                    : isLocked
                        ? 'Wacht $remaining sec…'
                        : 'Inloggen',
                onPressed: (_submitting || isLocked) ? null : _submit,
              );
            }),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onSwitchToRegister,
              child: Text(
                'Nog geen account? Registreren',
                style: GoogleFonts.fjallaOne(
                  color: GymiesColors.darkBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  _UserRole _role = _UserRole.klant;
  _RegisterGender? _gender;
  bool _newsletterSubscribe = false;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  bool _obscurePassword = true;
  late final VoidCallback _onPasswordChanged;

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

  @override
  void dispose() {
    _password.removeListener(_onPasswordChanged);
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _phone.dispose();
    _referralCode.dispose();
    super.dispose();
  }

  bool _submitting = false;

  Future<void> _submit() async {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Je moet akkoord gaan met de Algemene voorwaarden.'),
        ),
      );
      return;
    }
    if (!_acceptedPrivacy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Je moet akkoord gaan met het Privacybeleid.'),
        ),
      );
      return;
    }
    if (_role == _UserRole.klant && _gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kies of je als man of vrouw geregistreerd staat.'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) return;
    // Keyboard verbergen bij submit
    FocusManager.instance.primaryFocus?.unfocus();
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
      );
      if (!mounted) return;
      // Navigeer direct met user uit register-response; token is al gezet in AuthService
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => widget.auth.isAdminUser(user)
              ? const ControlTowerScreen()
              : (widget.auth.isTrainerUser(user)
                  ? const TrainerDashboardScreen()
                  : const DashboardScreen()),
        ),
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
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ik ben: Klant of Trainer
            Text(
              'Ik ben:',
              style: GoogleFonts.fjallaOne(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<_UserRole>(
              segments: [
                ButtonSegment(
                  value: _UserRole.klant,
                  label: Text(
                    'Klant',
                    style: GoogleFonts.fjallaOne(fontSize: 14),
                  ),
                  icon: const Icon(Icons.person, size: 22),
                ),
                ButtonSegment(
                  value: _UserRole.trainer,
                  label: Text(
                    'Trainer',
                    style: GoogleFonts.fjallaOne(fontSize: 14),
                  ),
                  icon: const Icon(Icons.fitness_center, size: 22),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() {
                _role = s.first;
                if (_role == _UserRole.trainer) {
                  _gender = null;
                }
              }),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return GymiesColors.darkBlue;
                  }
                  return Colors.white;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return GymiesColors.primary;
                  }
                  return GymiesColors.darkBlue;
                }),
              ),
            ),
            if (_role == _UserRole.klant) ...[
              const SizedBox(height: 20),
              Text(
                'Geslacht',
                style: GoogleFonts.fjallaOne(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_RegisterGender>(
                segments: [
                  ButtonSegment(
                    value: _RegisterGender.male,
                    label: Text('Man', style: GoogleFonts.fjallaOne(fontSize: 14)),
                    icon: const Icon(Icons.man_2_outlined, size: 22),
                  ),
                  ButtonSegment(
                    value: _RegisterGender.female,
                    label:
                        Text('Vrouw', style: GoogleFonts.fjallaOne(fontSize: 14)),
                    icon: const Icon(Icons.woman_2_outlined, size: 22),
                  ),
                ],
                selected: _gender != null ? {_gender!} : <_RegisterGender>{},
                emptySelectionAllowed: true,
                onSelectionChanged: (s) {
                  setState(() => _gender = s.isEmpty ? null : s.first);
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return GymiesColors.darkBlue;
                    }
                    return Colors.white;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return GymiesColors.primary;
                    }
                    return GymiesColors.darkBlue;
                  }),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // E-mail
            _GymiesFormField(
              controller: _email,
              hint: 'E-mail',
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Vul je e-mail in';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                  return 'Vul een geldig e-mailadres in';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Wachtwoord
            _GymiesFormField(
              controller: _password,
              hint: 'Wachtwoord',
              obscure: _obscurePassword,
              onObscureToggle: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Vul een wachtwoord in';
                if (v.length < 8) return 'Minimaal 8 tekens';
                final strength = _passwordStrength(v);
                if (strength == _PasswordStrength.weak) {
                  return 'Wachtwoord te zwak. Gebruik letters én cijfers.';
                }
                return null;
              },
            ),
            if (_password.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              _PasswordStrengthBar(strength: _passwordStrength(_password.text)),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 16),
            // Weergavenaam (optioneel)
            _GymiesFormField(
              controller: _displayName,
              hint: 'Weergavenaam (optioneel)',
            ),
            const SizedBox(height: 16),
            // Telefoon (optioneel)
            _GymiesFormField(
              controller: _phone,
              hint: 'Telefoonnummer (optioneel)',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            // Referralcode (optioneel)
            _GymiesFormField(
              controller: _referralCode,
              hint: 'Referralcode (optioneel)',
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 20),
            // Checkboxes
            _GymiesCheckbox(
              value: _acceptedTerms,
              onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
              label: 'Ik ga akkoord met de ',
              linkText: 'Algemene voorwaarden',
              onLinkTap: () => launchUrl(
                Uri.parse(AppConfig.termsUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
            _GymiesCheckbox(
              value: _acceptedPrivacy,
              onChanged: (v) => setState(() => _acceptedPrivacy = v ?? false),
              label: 'Ik ga akkoord met het ',
              linkText: 'Privacybeleid',
              onLinkTap: () => launchUrl(
                Uri.parse(AppConfig.privacyUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const SizedBox(height: 8),
            _GymiesCheckbox(
              value: _newsletterSubscribe,
              onChanged: (v) =>
                  setState(() => _newsletterSubscribe = v ?? false),
              label: 'Aanmelden voor nieuwsbrief',
              subtitle: 'Blijf op de hoogte van tips en aanbiedingen',
            ),
            const SizedBox(height: 24),
            _GymiesButton(
              text: _submitting ? 'Bezig…' : 'Registreren',
              onPressed: _submitting
                  ? null
                  : () {
                      _submit();
                    },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onSwitchToLogin,
              child: Text(
                'Al een account? Inloggen',
                style: GoogleFonts.fjallaOne(
                  color: GymiesColors.darkBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
            backgroundColor: GymiesColors.darkBlue.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.fjallaOne(fontSize: 12, color: color)),
      ],
    );
  }
}

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
                  style: GoogleFonts.fjallaOne(
                    color: GymiesColors.darkBlue,
                    fontSize: 14,
                  ),
                ),
                GestureDetector(
                  onTap: onLinkTap,
                  child: Text(
                    linkText!,
                    style: GoogleFonts.fjallaOne(
                      color: GymiesColors.darkBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(
                  '.',
                  style: GoogleFonts.fjallaOne(
                    color: GymiesColors.darkBlue,
                    fontSize: 14,
                  ),
                ),
              ],
            )
          : Text(
              label,
              style: GoogleFonts.fjallaOne(
                color: GymiesColors.darkBlue,
                fontSize: 14,
              ),
            ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: GoogleFonts.fjallaOne(
                color: GymiesColors.darkBlue.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            )
          : null,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      activeColor: GymiesColors.darkBlue,
    );
  }
}

class _GymiesFormField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback? onObscureToggle;
  final TextInputType? keyboardType;
  final TextCapitalization? textCapitalization;
  final String? Function(String?)? validator;

  const _GymiesFormField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.onObscureToggle,
    this.keyboardType,
    this.textCapitalization,
    this.validator,
  });

  @override
  State<_GymiesFormField> createState() => _GymiesFormFieldState();
}

class _GymiesFormFieldState extends State<_GymiesFormField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: widget.obscure,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization ?? TextCapitalization.none,
      validator: widget.validator,
      style: GoogleFonts.fjallaOne(color: GymiesColors.darkBlue),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: GoogleFonts.fjallaOne(
          color: GymiesColors.darkBlue.withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: GymiesColors.primary.withValues(alpha: 0.12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: GymiesColors.darkBlue.withValues(alpha: 0.22),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: GymiesColors.darkBlue.withValues(alpha: 0.22),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: GymiesColors.darkBlue,
            width: 1.4,
          ),
        ),
        suffixIcon: widget.onObscureToggle != null
            ? IconButton(
                icon: Icon(
                  widget.obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: GymiesColors.darkBlue.withValues(alpha: 0.6),
                ),
                onPressed: widget.onObscureToggle,
              )
            : null,
      ),
    );
  }
}

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
      setState(() => _error = 'Vul je e-mailadres in.');
      return;
    }
    // Keyboard verbergen bij submit
    FocusManager.instance.primaryFocus?.unfocus();
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
            'Check je e-mail voor instructies om je wachtwoord te resetten.',
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
          _error = 'Kon verzoek niet versturen. Probeer opnieuw.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Wachtwoord vergeten',
        style: GoogleFonts.fjallaOne(color: GymiesColors.darkBlue),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Vul je e-mailadres in. We sturen je een link om je wachtwoord te resetten.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'E-mail',
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
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: GymiesColors.primary,
            foregroundColor: GymiesColors.darkBlue,
          ),
          child: Text(_submitting ? 'Bezig…' : 'Verstuur'),
        ),
      ],
    );
  }
}

class _GymiesButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const _GymiesButton({required this.text, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: GymiesColors.darkBlue,
          foregroundColor: GymiesColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(text, style: GoogleFonts.fjallaOne(fontSize: 18)),
      ),
    );
  }
}
