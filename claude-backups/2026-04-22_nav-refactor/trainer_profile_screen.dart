
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/trainer_badges.dart';
import 'client_trainer_profile_screen.dart';
import 'login_register_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_media_section.dart';
import 'widgets/trainer_state_views.dart';

class TrainerProfileScreen extends StatefulWidget {
  const TrainerProfileScreen({super.key});

  @override
  State<TrainerProfileScreen> createState() => _TrainerProfileScreenState();
}

class _TrainerProfileScreenState extends State<TrainerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _regionController = TextEditingController();
  final _bioController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _profileSlugController = TextEditingController();

  Map<String, dynamic>? _profile;
  Set<String> _visibleBadgeIds = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _dirty = false;
  bool _syncingFromLoad = false;

  @override
  void initState() {
    super.initState();
    for (final c in [
      _displayNameController,
      _specialtyController,
      _regionController,
      _bioController,
      _hourlyRateController,
      _profileSlugController,
    ]) {
      c.addListener(_onFormChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _displayNameController,
      _specialtyController,
      _regionController,
      _bioController,
      _hourlyRateController,
      _profileSlugController,
    ]) {
      c.removeListener(_onFormChanged);
    }
    _displayNameController.dispose();
    _specialtyController.dispose();
    _regionController.dispose();
    _bioController.dispose();
    _hourlyRateController.dispose();
    _profileSlugController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (_syncingFromLoad) return;
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final p = await api.getTrainerProfile();
      if (mounted) {
        _syncingFromLoad = true;
        _displayNameController.text = (p['display_name'] ?? p['name'] ?? '')
            .toString();
        _specialtyController.text = (p['specialty'] ?? '').toString();
        _regionController.text = (p['region'] ?? '').toString();
        _bioController.text = (p['bio'] ?? p['description'] ?? '').toString();
        _profileSlugController.text =
            (p['profile_slug'] ?? p['profileSlug'] ?? '').toString();
        final cents = int.tryParse((p['hourly_rate_cents'] ?? '').toString());
        if (cents != null && cents > 0) {
          _hourlyRateController.text = (cents / 100).toStringAsFixed(0);
        } else {
          _hourlyRateController.text = '';
        }
        final raw = p['visible_badges'] ?? p['visible_badge_ids'] ?? p['badge_ids'];
        if (raw is List) {
          _visibleBadgeIds = raw
              .map((e) => e?.toString().trim())
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet();
        } else {
          _visibleBadgeIds = TrainerBadges.availableOptions()
              .map((o) => o.id)
              .toSet();
        }
        _syncingFromLoad = false;
        setState(() {
          _profile = p;
          _dirty = false;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Kon profiel niet laden.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _saving) return;
    setState(() => _saving = true);
    try {
      final euro = int.tryParse(_hourlyRateController.text.trim());
      final updated = await context.read<GymiesApi>().updateTrainerProfile(
        displayName: _displayNameController.text.trim(),
        specialty: _specialtyController.text.trim(),
        region: _regionController.text.trim(),
        bio: _bioController.text.trim(),
        hourlyRateCents: euro == null ? null : euro * 100,
        visibleBadgeIds: _visibleBadgeIds.toList(),
        profileSlug: _profileSlugController.text.trim().isEmpty
            ? null
            : _profileSlugController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _dirty = false;
      });
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

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Uitloggen'),
        content: const Text('Weet je zeker dat je wilt uitloggen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Uitloggen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthService>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
      (r) => false,
    );
  }

  Future<void> _openProfileAsClient() async {
    final slug = _profileSlugController.text.trim();
    final userId = context.read<AuthService>().user?['id']?.toString();
    if (slug.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientTrainerProfileScreen(
            trainerSlug: slug,
            showFullProfileOnly: true,
          ),
        ),
      );
    } else if (userId != null && userId.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientTrainerProfileScreen(
            trainerId: userId,
            showFullProfileOnly: true,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sla eerst een profiel-slug op om als klant te bekijken.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_dirty || _saving) return;
        showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Wijzigingen niet opgeslagen'),
            content: const Text(
              'Weet je zeker dat je zonder opslaan wilt sluiten?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Terug'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sluiten'),
              ),
            ],
          ),
        ).then((discard) {
          if (discard == true && context.mounted) {
            Navigator.of(context).pop();
          }
        });
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: const GymiesAppBar(title: 'Mijn profiel'),
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
                        _ProfileInfoCard(profile: _profile ?? {}),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openProfileAsClient,
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('Bekijk als klant'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GymiesColors.darkBlue,
                            side: const BorderSide(color: GymiesColors.darkBlue),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Profiel bewerken',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _FormField(
                          controller: _displayNameController,
                          label: 'Weergavenaam',
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Weergavenaam is verplicht';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          controller: _specialtyController,
                          label: 'Specialiteit',
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          controller: _regionController,
                          label: 'Regio',
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          controller: _profileSlugController,
                          label: 'Persoonlijke link (slug)',
                          hint: 'jouwnaam → gymies.nl/t/jouwnaam',
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final slug = v.trim();
                            if (!RegExp(r'^[a-zA-Z0-9\-]+$').hasMatch(slug)) {
                              return 'Alleen letters, cijfers en streepjes';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          controller: _hourlyRateController,
                          label: 'Tarief per uur (EUR)',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final raw = (v ?? '').trim();
                            if (raw.isEmpty) return null;
                            if (int.tryParse(raw) == null) {
                              return 'Gebruik alleen cijfers';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          controller: _bioController,
                          label: 'Bio',
                          maxLines: 4,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Badges op profiel',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kies welke badges je op je publieke profiel toont. Prijs blijft altijd zichtbaar.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _BadgePreferencesSection(
                          visibleIds: _visibleBadgeIds,
                          onChanged: (ids) {
                            setState(() {
                              _visibleBadgeIds = ids;
                              if (!_dirty) _dirty = true;
                            });
                          },
                        ),
                        const SizedBox(height: 24),
                        TrainerMediaSection(),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: GymiesColors.primary,
                            foregroundColor: GymiesColors.darkBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Opslaan'),
                        ),
                        if (_dirty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Niet-opgeslagen wijzigingen',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.logout_rounded,
                                color: Colors.red),
                            label: const Text(
                              'Uitloggen',
                              style: TextStyle(color: Colors.red),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
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

class _BadgePreferencesSection extends StatelessWidget {
  const _BadgePreferencesSection({
    required this.visibleIds,
    required this.onChanged,
  });

  final Set<String> visibleIds;
  final void Function(Set<String>) onChanged;

  @override
  Widget build(BuildContext context) {
    final options = TrainerBadges.availableOptions();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final selected = visibleIds.contains(opt.id);
        return FilterChip(
          label: Text(opt.label),
          selected: selected,
          onSelected: (v) {
            final next = Set<String>.from(visibleIds);
            if (v) {
              next.add(opt.id);
            } else {
              next.remove(opt.id);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final name =
        profile['display_name'] ?? profile['name'] ?? profile['email'] ?? '–';
    final email = profile['email'] ?? '–';
    final specialty = profile['specialty'] ?? '–';
    final region = profile['region'] ?? '–';

    return Material(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: GymiesColors.primary.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.toString(),
              style: GoogleFonts.fjallaOne(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            _InfoRow(label: 'E-mail', value: email.toString()),
            _InfoRow(label: 'Specialiteit', value: specialty.toString()),
            _InfoRow(label: 'Regio', value: region.toString()),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
