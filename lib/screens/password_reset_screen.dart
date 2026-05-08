import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'login_register_screen.dart';

/// Scherm voor wachtwoord reset na klik op link in e-mail.
/// Deep link: gymies://wachtwoord-reset?token=X&email=Y
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    required this.token,
    this.email,
  });

  final String token;
  final String? email;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _loading) return;
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();
    if (password != confirm) {
      setState(() => _error = S.of(context).wachtwoordenKomenNietOvereen);
      return;
    }
    if (password.length < 8) {
      setState(() => _error = S.of(context).minimaal8Tekens);
      return;
    }
    FocusScope.of(context).unfocus();
    Haptics.light();
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<GymiesApi>();
    try {
      await api.resetPassword(
            token: widget.token,
            newPassword: password,
            email: widget.email,
          );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = S.of(context).erGingIetsMisProbeerOpnieuw;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        title: Text(
          S.of(context).resetPasswordTitle,
          style: GoogleFonts.sora(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _success
              ? _SuccessView(
                  onLogin: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const LoginRegisterScreen(),
                      ),
                      (r) => false,
                    );
                  },
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        S.of(context).setNewPassword,
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        S.of(context).chooseStrongPassword,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: S.of(context).newPassword,
                          hintText: S.of(context).minimum8Characters,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: GymiesColors.darkBlue,
                            ),
                            onPressed: () {
                              Haptics.selection();
                              setState(
                                  () => _obscurePassword = !_obscurePassword);
                            },
                          ),
                          filled: true,
                          fillColor: GymiesColors.primary.withOpacity(0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return S.of(context).vulEenWachtwoordIn;
                          }
                          if (v.trim().length < 8) {
                            return S.of(context).minimaal8Tekens;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          labelText: S.of(context).repeatPassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: GymiesColors.darkBlue,
                            ),
                            onPressed: () {
                              Haptics.selection();
                              setState(
                                  () => _obscureConfirm = !_obscureConfirm);
                            },
                          ),
                          filled: true,
                          fillColor: GymiesColors.primary.withOpacity(0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return S.of(context).herhaalJeWachtwoord;
                          }
                          if (v.trim() != _passwordController.text.trim()) {
                            return S.of(context).passwordsDoNotMatch;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: GymiesColors.darkBlue,
                                ),
                              )
                            : Text(
                                S.of(context).savePassword,
                                style: GoogleFonts.sora(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
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
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Icon(
          Icons.check_circle_rounded,
          size: 80,
          color: Colors.green.shade600,
        ),
        const SizedBox(height: 24),
        Text(
          S.of(context).passwordChanged,
          style: GoogleFonts.sora(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: GymiesColors.darkBlue,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          S.of(context).canNowLoginNewPassword,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () {
            Haptics.light();
            onLogin();
          },
          style: FilledButton.styleFrom(
            backgroundColor: GymiesColors.primary,
            foregroundColor: GymiesColors.darkBlue,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            S.of(context).goToLogin,
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
