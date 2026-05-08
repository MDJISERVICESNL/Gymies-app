


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/haptics.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import 'widgets/gymies_dialog.dart';
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
  final _cityController = TextEditingController();
  final _ecNameController = TextEditingController();
  final _ecPhoneController = TextEditingController();
  final _ecEmailController = TextEditingController();

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
    _cityController.dispose();
    _ecNameController.dispose();
    _ecPhoneController.dispose();
    _ecEmailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<GymiesApi>();
    final auth = context.read<AuthService>();
    context.read<ApiClient>().setAuthToken(auth.token);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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
        _cityController.text = city;
        _ecNameController.text =
            (me['emergency_contact_name'] ?? '').toString();
        _ecPhoneController.text =
            (me['emergency_contact_phone'] ?? '').toString();
        _ecEmailController.text =
            (me['emergency_contact_email'] ?? '').toString();
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
        _error = S.of(context).couldNotLoadProfile;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    Haptics.light();
    setState(() => _saving = true);
    try {
      final me = await context.read<GymiesApi>().updateMe(
        displayName: _nameController.text,
        phone: _phoneController.text,
        city: _cityController.text,
        emergencyContactName: _ecNameController.text,
        emergencyContactPhone: _ecPhoneController.text,
        emergencyContactEmail: _ecEmailController.text,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved'),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    Haptics.light();
    final api = context.read<GymiesApi>();
    final formKey = GlobalKey<FormState>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool submitting = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return GymiesDialog(
            title: S.of(context).changePassword,
            headerIcon: Icons.lock_outline_rounded,
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: S.of(context).currentPassword,
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? S.of(context).enterCurrentPassword
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: S.of(context).newPassword,
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? '${S.of(context).minimumCharacters} 8'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: S.of(context).repeatNewPassword,
                    ),
                    validator: (v) => v != newCtrl.text
                        ? S.of(context).passwordsDoNotMatch
                        : null,
                  ),
                ],
              ),
            ),
            actions: [
              GymiesDialogAction(
                label: S.of(context).cancelLabel,
                returnValue: null,
              ),
              GymiesDialogAction(
                label: S.of(context).saveAction,
                isPrimary: true,
                onPressed: submitting
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setModalState(() => submitting = true);
                        try {
                          await api.changeMyPassword(
                            currentPassword: currentCtrl.text,
                            newPassword: newCtrl.text,
                          );
                          if (!context.mounted) return;
                          Navigator.of(ctx).pop();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password successfully changed'),
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
              ),
            ],
          );
        },
      ),
    ).then((_) {
      currentCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    });
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: _SkeletonBox(width: 160, height: 14),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(4, (i) => Padding(
                padding: EdgeInsets.only(bottom: i < 3 ? 14 : 0),
                child: _SkeletonBox(width: double.infinity, height: 56),
              )),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _SkeletonBox(width: 42, height: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonBox(width: 120, height: 16),
                          const SizedBox(height: 6),
                          _SkeletonBox(width: 200, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ...List.generate(3, (i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 2 ? 14 : 0),
                  child: _SkeletonBox(width: double.infinity, height: 56),
                )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SkeletonBox(width: double.infinity, height: 48),
          const SizedBox(height: 12),
          _SkeletonBox(width: double.infinity, height: 48),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          // ── Custom header ──
          Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        S.of(context).myProfileTitle,
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Body ──
          Expanded(
            child: _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : _loading
                ? _buildLoadingSkeleton()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Section label ──
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8),
                            child: Text(
                              S.of(context).personalDetails,
                              style: GoogleFonts.sora(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _nameController,
                                    decoration: InputDecoration(
                                      labelText: S.of(context).nameLabel,
                                      prefixIcon: const Icon(Icons.person_outline, size: 20),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty)
                                        ? S.of(context).nameIsRequired
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    initialValue: _email,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: S.of(context).email,
                                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade200),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade200),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _phoneController,
                                    decoration: InputDecoration(
                                      labelText: S.of(context).phoneLabel,
                                      hintText: '06 12 34 56 78',
                                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                    ),
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                                      _PhoneNumberFormatter(),
                                    ],
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) return null; // optioneel veld
                                      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                                      if (digits.length < 10) return S.of(context).enterMinimum10Digits;
                                      if (digits.length > 15) return S.of(context).phoneNumberTooLong;
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _cityController,
                                    decoration: InputDecoration(
                                      labelText: S.of(context).myCity,
                                      hintText: S.of(context).exampleCity,
                                      prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── Noodcontact sectie ──────────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.emergency_rounded,
                                          color: Colors.red.shade600,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              S.of(context).emergencyContactLabel,
                                              style: GoogleFonts.sora(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: GymiesColors.darkBlue,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              S.of(context).emergencyContactInfo,
                                              style: GoogleFonts.sora(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _ecNameController,
                                    decoration: InputDecoration(
                                      labelText: S.of(context).emergencyContactName,
                                      hintText: S.of(context).exampleName,
                                      prefixIcon: const Icon(Icons.person_outline, size: 20),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                    ),
                                    textCapitalization:
                                        TextCapitalization.words,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _ecPhoneController,
                                    decoration: InputDecoration(
                                      labelText: S.of(context).emergencyContactPhone,
                                      hintText: '+31 6 12345678',
                                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                    ),
                                    keyboardType: TextInputType.phone,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _ecEmailController,
                                    decoration: InputDecoration(
                                      labelText: S.of(context).emailEmergencyContact,
                                      hintText: S.of(context).emergencyContactPlaceholder,
                                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Haptics.light();
                                _changePassword();
                              },
                              icon: const Icon(Icons.lock_outline_rounded, size: 18),
                              label: Text(
                                S.of(context).changePassword,
                                style: GoogleFonts.sora(fontSize: 14),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: GymiesColors.primary.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: FilledButton(
                              onPressed: _saving ? null : () {
                                Haptics.light();
                                _save();
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: GymiesColors.primary,
                                foregroundColor: GymiesColors.darkBlue,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: GoogleFonts.sora(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: GymiesColors.darkBlue,
                                      ),
                                    )
                                  : Text(S.of(context).saveAction),
                            ),
                          ),
                          const SizedBox(height: 24),
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.error_outline, color: Colors.red.shade400, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                fontSize: 15,
                color: GymiesColors.darkBlue,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(S.of(context).retryAction, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox({required this.width, required this.height});
  final double width;
  final double height;

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
              end: Alignment(-1.0 + 2.0 * _ctrl.value + 1, 0),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade100,
                Colors.grey.shade200,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Formatteert telefoonnummers als "06 12 34 56 78" tijdens het typen.
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Strip alles behalve cijfers en +
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');

    // Als het begint met + (internationaal), laat het zo
    if (digits.startsWith('+')) {
      return newValue.copyWith(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }

    // NL formaat: 06 12 34 56 78
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 10; i++) {
      if (i == 2 || i == 4 || i == 6 || i == 8) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
