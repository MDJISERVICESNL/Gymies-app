

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'login_register_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/trainer_state_views.dart';

class TrainerProfileScreen extends StatefulWidget {
  const TrainerProfileScreen({super.key});

  @override
  State<TrainerProfileScreen> createState() => _TrainerProfileScreenState();
}

class _TrainerProfileScreenState extends State<TrainerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _error;
  bool _dirty = false;
  bool _syncingFromLoad = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_onFormChanged);
    _load();
  }

  @override
  void dispose() {
    _displayNameController.removeListener(_onFormChanged);
    _displayNameController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (_syncingFromLoad) return;
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = context.read<GymiesApi>();
    final auth = context.read<AuthService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (kDebugMode) debugPrint(S.of(context).trainerprofileProfielLaden);
      final p = await api.getTrainerProfile();
      if (kDebugMode) debugPrint('[TrainerProfile] OK – ${p.length} velden geladen');

      if (mounted) {
        _syncingFromLoad = true;
        _displayNameController.text =
            (p['display_name'] ?? p['name'] ?? '').toString();
        _avatarUrl = (p['avatar_url'] ?? p['avatarUrl'] ?? '').toString();
        if (_avatarUrl != null && _avatarUrl!.trim().isEmpty) _avatarUrl = null;
        _syncingFromLoad = false;
        setState(() {
          _profile = p;
          _dirty = false;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[TrainerProfile] ApiException: ${e.statusCode} – ${e.message}');
      if (mounted) {
        // Fallback: gebruik AuthService user data als minimaal profiel
        final fallback = _buildFallbackProfile();
        if (fallback != null && (e.statusCode == 404 || e.statusCode == 500)) {
          if (kDebugMode) debugPrint(S.of(context).trainerprofileFallbackProfielGebruiktVanuitAuthservice);
          _syncingFromLoad = true;
          _displayNameController.text =
              (fallback['display_name'] ?? fallback['name'] ?? '').toString();
          _avatarUrl = (fallback['avatar_url'] ?? '').toString();
          if (_avatarUrl != null && _avatarUrl!.trim().isEmpty) _avatarUrl = null;
          _syncingFromLoad = false;
          setState(() {
            _profile = fallback;
            _dirty = false;
            _loading = false;
            _error = null;
          });
        } else {
          setState(() {
            _error = e.message;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[TrainerProfile] Error: $e');
      if (mounted) {
        final fallback = _buildFallbackProfile();
        if (fallback != null) {
          if (kDebugMode) debugPrint(S.of(context).trainerprofileFallbackProfielGebruiktNaFout);
          _syncingFromLoad = true;
          _displayNameController.text =
              (fallback['display_name'] ?? fallback['name'] ?? '').toString();
          _avatarUrl = (fallback['avatar_url'] ?? '').toString();
          if (_avatarUrl != null && _avatarUrl!.trim().isEmpty) _avatarUrl = null;
          _syncingFromLoad = false;
          setState(() {
            _profile = fallback;
            _dirty = false;
            _loading = false;
            _error = null;
          });
        } else {
          setState(() {
            _error = S.of(context).konProfielNietLadenProbeerOpnieuw;
            _loading = false;
          });
        }
      }
    }
  }

  /// Bouw minimaal profiel vanuit AuthService user data als fallback bij API-fout.
  Map<String, dynamic>? _buildFallbackProfile() {
    try {
      final user = context.read<AuthService>().user;
      if (user == null) return null;
      return <String, dynamic>{
        'user_id': user['id']?.toString() ?? '',
        'display_name': user['display_name'] ?? user['name'] ?? '',
        'email': user['email'] ?? '',
        'avatar_url': user['avatar_url'] ?? user['avatarUrl'] ?? '',
        'role': user['role'] ?? S.of(context).trainer2,
        'bio': '',
        'specialty': '',
        'region': '',
        'hourly_rate_cents': 0,
        '_is_fallback': true,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _saving) return;
    Haptics.light();
    final api = context.read<GymiesApi>();
    setState(() => _saving = true);
    try {
      final updated = await api.updateTrainerProfile(
        displayName: _displayNameController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _dirty = false;
      });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    Haptics.selection();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                S.of(context).profielfotoKiezen,
                style: GoogleFonts.sora(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: GymiesColors.darkBlue),
                ),
                title: Text(S.of(context).camera,
                    style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                subtitle: Text(S.of(context).maakEenNieuweFoto,
                    style: GoogleFonts.sora(
                        fontSize: 12, color: Colors.grey.shade600)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: GymiesColors.darkBlue),
                ),
                title: Text(S.of(context).galerij,
                    style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                subtitle: Text(S.of(context).kiesUitJeFotorol,
                    style: GoogleFonts.sora(
                        fontSize: 12, color: Colors.grey.shade600)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingAvatar = true);

    try {
      final api = context.read<GymiesApi>();

      // Upload via media endpoint met usage 'avatar'
      final mediaRes = await api.postTrainerMedia(
        filePath: picked.path,
        type: 'photo',
        usage: 'avatar',
      );

      // Haal de URL op uit het response
      final newUrl = (mediaRes['url'] ?? mediaRes['full_url'] ?? mediaRes['file_url'] ?? '').toString();

      if (newUrl.isNotEmpty) {
        // Update avatar_url op het profiel
        await api.updateTrainerProfile(
          displayName: _displayNameController.text.trim(),
          avatarUrl: newUrl,
        );
        if (!mounted) return;
        setState(() => _avatarUrl = newUrl);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).profielfotoBijgewerkt),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).konFotoNietUploaden(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await GymiesDialog.destructive(
      context,
      title: S.of(context).uitloggen,
      message: S.of(context).logoutConfirmMessage,
      confirmLabel: S.of(context).uitloggen,
    );
    if (confirmed != true || !mounted) return;
    Haptics.heavy();
    await context.read<AuthService>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = (_profile?['email'] ?? '').toString();
    final initial = _displayNameController.text.trim().isNotEmpty
        ? _displayNameController.text.trim()[0].toUpperCase()
        : '?';

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_dirty || _saving) return;
        GymiesDialog.destructive(
          context,
          title: S.of(context).wijzigingenNietOpgeslagen,
          message: S.of(context).weetJeZekerDatJeZonder,
          confirmLabel: 'Sluiten',
        ).then((discard) {
          if (discard == true && context.mounted) {
            Navigator.of(context).pop();
          }
        });
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: const GymiesAppBar(title: S.of(context).myProfileTitle),
        body: GymiesListBody(
          loading: _loading,
          error: _error,
          onRefresh: _load,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Avatar sectie ──
                  Center(
                    child: GestureDetector(
                      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                      child: Stack(
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: GymiesColors.primary.withOpacity(0.15),
                              border: Border.all(
                                color: GymiesColors.primary.withOpacity(0.3),
                                width: 3,
                              ),
                            ),
                            child: ClipOval(
                              child: _uploadingAvatar
                                  ? Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: GymiesColors.darkBlue,
                                        ),
                                      ),
                                    )
                                  : _avatarUrl != null && _avatarUrl!.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: _avatarUrl!,
                                          width: 110,
                                          height: 110,
                                          fit: BoxFit.cover,
                                          cacheWidth: 220,
                                          cacheHeight: 220,
                                          placeholder: (_, _) => Center(
                                            child: Text(
                                              initial,
                                              style: GoogleFonts.sora(
                                                fontSize: 38,
                                                fontWeight: FontWeight.w700,
                                                color: GymiesColors.darkBlue,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (_, _, _) => Center(
                                            child: Text(
                                              initial,
                                              style: GoogleFonts.sora(
                                                fontSize: 38,
                                                fontWeight: FontWeight.w700,
                                                color: GymiesColors.darkBlue,
                                              ),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            initial,
                                            style: GoogleFonts.sora(
                                              fontSize: 38,
                                              fontWeight: FontWeight.w700,
                                              color: GymiesColors.darkBlue,
                                            ),
                                          ),
                                        ),
                            ),
                          ),
                          // Camera badge
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: GymiesColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 16,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      S.of(context).tikOmFotoTeWijzigen,
                      style: GoogleFonts.sora(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Profielgegevens ──
                  Text(
                    S.of(context).profielgegevens,
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Weergavenaam
                  TextFormField(
                    controller: _displayNameController,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return S.of(context).weergavenaamIsVerplicht;
                      }
                      return null;
                    },
                    style: GoogleFonts.sora(fontSize: 15),
                    decoration: InputDecoration(
                      labelText: S.of(context).weergavenaam,
                      labelStyle: GoogleFonts.sora(
                          fontSize: 14, fontWeight: FontWeight.w500),
                      prefixIcon: const Icon(Icons.person_outline_rounded,
                          size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // E-mail (alleen-lezen)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.email_outlined,
                            size: 20, color: Colors.grey.shade500),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.of(context).email,
                                style: GoogleFonts.sora(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email.isNotEmpty ? email : '–',
                                style: GoogleFonts.sora(
                                  fontSize: 15,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.lock_outline_rounded,
                            size: 16, color: Colors.grey.shade400),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Opslaan ──
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(S.of(context).opslaan,
                            style: GoogleFonts.sora(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  if (_dirty) ...[
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).nietopgeslagenWijzigingen,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.sora(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),

                  // ── Info hint ──
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: Colors.blue.shade600),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            S.of(context).specialiteitenTariefBioEnMediaKunJeAanpassenInDeEtalageeditor,
                            style: GoogleFonts.sora(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 12),

                  // ── Uitloggen ──
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout_rounded, color: Colors.red),
                      label: Text(
                        S.of(context).uitloggen,
                        style: GoogleFonts.sora(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _logout,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
