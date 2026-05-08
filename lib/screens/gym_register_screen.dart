import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'shells/gym_shell.dart';

/// Gym registratiescherm — bereikbaar via deep link gymies://gym/register?token=xxx
///
/// Flow:
/// 1. Token valideren via API → pre-filled data laden
/// 2. Gebruiker kiest wachtwoord + bevestigt gegevens
/// 3. registerWithToken() → automatisch inloggen → naar GymShell
class GymRegisterScreen extends StatefulWidget {
  const GymRegisterScreen({super.key, required this.token});

  /// 64-hex invite token uit de deep link
  final String token;

  @override
  State<GymRegisterScreen> createState() => _GymRegisterScreenState();
}

class _GymRegisterScreenState extends State<GymRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  // Pre-filled data van de token validatie
  String _gymName = '';
  String _contactName = '';
  String _email = '';
  String _phone = '';
  String _city = '';
  String? _website;
  int? _estimatedTrainers;

  @override
  void initState() {
    super.initState();
    _validateToken();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _validateToken() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.validateGymInviteToken(widget.token);
      final data = res['data'] as Map<String, dynamic>? ?? res;

      if (mounted) {
        setState(() {
          _gymName = data['gym_name']?.toString() ?? '';
          _contactName = data['contact_name']?.toString() ?? '';
          _email = data['email']?.toString() ?? '';
          _phone = data['phone']?.toString() ?? '';
          _city = data['city']?.toString() ?? '';
          _website = data['website_url']?.toString();
          _estimatedTrainers = int.tryParse(data['estimated_trainers']?.toString() ?? '');
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (e.statusCode == 404 || e.statusCode == 410) {
            _error = 'Deze uitnodigingslink is ongeldig of verlopen. Neem contact op met het GYMIES team.';
          } else if (e.statusCode == 409) {
            _error = 'Deze uitnodigingslink is al gebruikt.';
          } else {
            _error = 'Er is een fout opgetreden. Probeer het later opnieuw.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Kan geen verbinding maken met de server.';
        });
      }
    }
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_submitting) return;

    setState(() => _submitting = true);
    Haptics.light();

    try {
      final api = context.read<GymiesApi>();
      final auth = context.read<AuthService>();

      final res = await api.registerGymWithToken({
        'token': widget.token,
        'password': _passwordController.text,
        'password_confirmation': _passwordController.text,
      });

      // Haal token en user uit response (zelfde patroon als login)
      final tokenRaw = res['token'] ?? res['access_token'] ?? res['data']?['token'] ?? res['data']?['access_token'];
      final token = tokenRaw is String ? tokenRaw.trim() : tokenRaw?.toString().trim();
      final userRaw = res['user'] ?? res['data']?['user'];
      final user = userRaw is Map<String, dynamic> ? userRaw : null;

      if (token == null || token.isEmpty) {
        throw ApiException(500, 'Geen sessietoken ontvangen.');
      }

      // Auto-login
      await auth.loginWithSessionToken(token, user);

      if (!mounted) return;
      Haptics.success();

      // Navigeer naar GymShell (verwijder alle vorige routes)
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GymShell()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          if (e.statusCode == 410) {
            _error = 'Deze uitnodigingslink is verlopen.';
          } else if (e.statusCode == 409) {
            _error = 'Er bestaat al een account met dit e-mailadres. Probeer in te loggen.';
          } else if (e.statusCode == 422) {
            _error = e.message.isNotEmpty ? e.message : 'Controleer je gegevens.';
          } else {
            _error = 'Registratie mislukt. Probeer het later opnieuw.';
          }
        });
        Haptics.error();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Er is een fout opgetreden. Probeer het later opnieuw.';
        });
        Haptics.error();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? _buildLoading()
          : (_error != null ? _buildError() : _buildForm()),
    );
  }

  Widget _buildLoading() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GymiesTheme.darkBlue, Color(0xFF0D1F33)],
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: GymiesTheme.primaryGold),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GymiesTheme.darkBlue, Color(0xFF0D1F33)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 24),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    'Terug naar login',
                    style: GoogleFonts.sora(
                      color: GymiesTheme.primaryGold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GymiesTheme.darkBlue, Color(0xFF0D1F33)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),

              // ── Header ──
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: GymiesTheme.primaryGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.fitness_center_rounded, color: GymiesTheme.primaryGold, size: 36),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Welkom bij ${AppConfig.appName}!',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Rond je registratie af voor $_gymName',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 32),

              // ── Pre-filled gegevens card ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Je gegevens',
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: GymiesTheme.primaryGold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _infoRow(Icons.business_rounded, 'Gym', _gymName),
                    if (_contactName.isNotEmpty) _infoRow(Icons.person_rounded, 'Contactpersoon', _contactName),
                    _infoRow(Icons.email_rounded, 'E-mail', _email),
                    if (_phone.isNotEmpty) _infoRow(Icons.phone_rounded, 'Telefoon', _phone),
                    if (_city.isNotEmpty) _infoRow(Icons.location_on_rounded, 'Stad', _city),
                    if (_website != null && _website!.isNotEmpty)
                      _infoRow(Icons.language_rounded, 'Website', _website!),
                    if (_estimatedTrainers != null)
                      _infoRow(Icons.groups_rounded, 'Geschat aantal trainers', '$_estimatedTrainers'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Wachtwoord form ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kies een wachtwoord',
                        style: GoogleFonts.sora(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: GymiesTheme.primaryGold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: GoogleFonts.sora(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Wachtwoord',
                          labelStyle: GoogleFonts.sora(color: Colors.white.withOpacity(0.5)),
                          prefixIcon: Icon(Icons.lock_rounded, color: Colors.white.withOpacity(0.5)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: GymiesTheme.primaryGold),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Wachtwoord is verplicht';
                          if (v.length < 8) return 'Minimaal 8 tekens';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        style: GoogleFonts.sora(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Bevestig wachtwoord',
                          labelStyle: GoogleFonts.sora(color: Colors.white.withOpacity(0.5)),
                          prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.white.withOpacity(0.5)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: GymiesTheme.primaryGold),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Bevestig je wachtwoord';
                          if (v != _passwordController.text) return 'Wachtwoorden komen niet overeen';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── Error message ──
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.sora(color: Colors.red.shade200, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // ── Register knop ──
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GymiesTheme.primaryGold,
                    foregroundColor: GymiesTheme.darkBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: GymiesTheme.darkBlue,
                          ),
                        )
                      : Text(
                          'Account aanmaken',
                          style: GoogleFonts.sora(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Terug naar login link ──
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    'Ik heb al een account',
                    style: GoogleFonts.sora(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withOpacity(0.5)),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: GoogleFonts.sora(
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.sora(
                fontSize: 13,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
