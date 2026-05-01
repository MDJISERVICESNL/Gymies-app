import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/gymies_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'shells/client_shell.dart';
import 'shells/trainer_shell.dart';

/// Scherm voor e-mailverificatie na registratie.
class VerifyEmailScreen extends StatefulWidget {
  final String email;

  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final auth = context.read<AuthService>();
      final user = await auth.verifyEmail(
        widget.email,
        _codeController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => auth.isTrainerUser(user)
              ? const TrainerShell()
              : const ClientShell(),
        ),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('Exception')
              ? 'Er ging iets mis. Probeer opnieuw.'
              : e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    setState(() => _error = null);
    try {
      final auth = context.read<AuthService>();
      await auth.resendVerificationCode(widget.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nieuwe code verstuurd. Controleer je e-mail.'),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GymiesColors.primary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text(
                'E-mail verifiëren',
                style: GoogleFonts.sora(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: GymiesColors.darkBlue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We hebben een code gestuurd naar ${widget.email}. Vul de code hieronder in.',
                style: GoogleFonts.sora(
                  fontSize: 16,
                  color: GymiesColors.darkBlue.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _codeController,
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 24,
                  color: GymiesColors.darkBlue,
                ),
                decoration: InputDecoration(
                  hintText: 'Code',
                  hintStyle: GoogleFonts.sora(
                    color: GymiesColors.darkBlue.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onFieldSubmitted: (_) => _verify(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GymiesColors.darkBlue,
                    foregroundColor: GymiesColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Verifiëren',
                          style: GoogleFonts.sora(fontSize: 18),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loading ? null : _resendCode,
                child: Text(
                  'Code opnieuw sturen',
                  style: GoogleFonts.sora(
                    color: GymiesColors.darkBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
