import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_section_header.dart';
import 'widgets/trainer_media_section.dart';
import 'widgets/trainer_state_views.dart';

/// Etalage Visual Builder – stories, gallery, SEO.
/// Pro-feature voor trainers.
class TrainerStorefrontEditorScreen extends StatefulWidget {
  const TrainerStorefrontEditorScreen({super.key});

  @override
  State<TrainerStorefrontEditorScreen> createState() =>
      _TrainerStorefrontEditorScreenState();
}

class _TrainerStorefrontEditorScreenState
    extends State<TrainerStorefrontEditorScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _metaTitleController = TextEditingController();
  final _metaDescriptionController = TextEditingController();
  final _seoSlugController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    _seoSlugController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final cms = await api.getTrainerStorefrontCms();
      if (!mounted) return;
      _metaTitleController.text =
          mapStr(cms, ['meta_title', 'metaTitle', 'seo_title']);
      _metaDescriptionController.text =
          mapStr(cms, ['meta_description', 'metaDescription', 'seo_description']);
      _seoSlugController.text =
          mapStr(cms, ['profile_slug', 'profileSlug', 'slug']);
      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon etalage niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'meta_title': _metaTitleController.text.trim(),
        'meta_description': _metaDescriptionController.text.trim(),
        'profile_slug': _seoSlugController.text.trim(),
      };
      await context.read<GymiesApi>().updateTrainerStorefrontCms(body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Etalage opgeslagen'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Etalage-editor',
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: GymiesColors.primary,
                    ),
                  )
                : const Text('Opslaan'),
          ),
        ],
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const GymiesSectionHeader('Stories & Gallery'),
                        const SizedBox(height: 8),
                        const TrainerMediaSection(),
                        const SizedBox(height: 24),
                        const GymiesSectionHeader('SEO-instellingen'),
                        const SizedBox(height: 8),
                        Text(
                          'Deze velden verbeteren je vindbaarheid in zoekmachines.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _metaTitleController,
                          decoration: const InputDecoration(
                            labelText: 'Meta titel',
                            hintText: 'bijv. Personal trainer Amsterdam',
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _metaDescriptionController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Meta beschrijving',
                            hintText:
                                'Korte beschrijving voor zoekmachines (max 160 tekens)',
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _seoSlugController,
                          decoration: const InputDecoration(
                            labelText: 'Profiel-URL (slug)',
                            hintText: 'jouwnaam → gymies.nl/t/jouwnaam',
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: GymiesColors.darkBlue,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(_saving ? 'Opslaan...' : 'Opslaan'),
                          style: FilledButton.styleFrom(
                            backgroundColor: GymiesColors.primary,
                            foregroundColor: GymiesColors.darkBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
