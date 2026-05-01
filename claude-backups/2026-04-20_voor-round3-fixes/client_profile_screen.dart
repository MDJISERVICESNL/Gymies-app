import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';

const _kClientCityKey = 'gymies_client_city';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _cityController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _email = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final auth = context.read<AuthService>();
      context.read<ApiClient>().setAuthToken(auth.token);
      Map<String, dynamic> me = {};
      try {
        me = await api.getMe();
      } catch (_) {
        me = auth.user ?? {};
      }
      if (!mounted) return;
      String city = (me['city'] ?? '').toString();
      if (city.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        city = prefs.getString(_kClientCityKey) ?? '';
      }
      if (!mounted) return;
      setState(() {
        _nameController.text =
            (me['display_name'] ?? me['name'] ?? me['first_name'] ?? '')
                .toString();
        _phoneController.text = (me['phone'] ?? '').toString();
        _bioController.text = (me['bio'] ?? '').toString();
        _cityController.text = city;
        _email = (me['email'] ?? auth.user?['email'] ?? '').toString();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon profiel niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final me = await context.read<GymiesApi>().updateMe(
        displayName: _nameController.text,
        phone: _phoneController.text,
        bio: _bioController.text,
        city: _cityController.text,
      );
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final merged = {...?auth.user, ...me};
      await auth.setUser(merged);
      final city = _cityController.text.trim();
      if (city.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kClientCityKey, city);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profiel opgeslagen'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final formKey = GlobalKey<FormState>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool submitting = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Wachtwoord wijzigen'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Huidig wachtwoord',
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Vul je huidige wachtwoord in'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nieuw wachtwoord',
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Minimaal 8 tekens'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Herhaal nieuw wachtwoord',
                    ),
                    validator: (v) => v != newCtrl.text
                        ? 'Wachtwoorden komen niet overeen'
                        : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setModalState(() => submitting = true);
                        try {
                          await context.read<GymiesApi>().changeMyPassword(
                            currentPassword: currentCtrl.text,
                            newPassword: newCtrl.text,
                          );
                          if (!context.mounted) return;
                          Navigator.of(ctx).pop();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Wachtwoord succesvol gewijzigd'),
                              backgroundColor: GymiesColors.darkBlue,
                            ),
                          );
                        } on ApiException catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.message),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (context.mounted) {
                            setModalState(() => submitting = false);
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                ),
                child: const Text('Opslaan'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        title: Text(
          'Mijn profiel',
          style: GoogleFonts.fjallaOne(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Naam',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Naam is verplicht'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: _email,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneController,
                              decoration: const InputDecoration(
                                labelText: 'Telefoon',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _cityController,
                              decoration: const InputDecoration(
                                labelText: 'Mijn stad',
                                hintText: 'Bijv. Rotterdam, Amsterdam',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _bioController,
                              minLines: 3,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: 'Over mij',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _changePassword,
                        icon: const Icon(Icons.lock_outline_rounded),
                        label: const Text('Wachtwoord wijzigen'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Opslaan'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
              ),
              child: const Text('Opnieuw proberen'),
            ),
          ],
        ),
      ),
    );
  }
}
