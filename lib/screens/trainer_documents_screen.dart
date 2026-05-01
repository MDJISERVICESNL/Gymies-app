import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';

class TrainerDocumentsScreen extends StatefulWidget {
  const TrainerDocumentsScreen({super.key});

  @override
  State<TrainerDocumentsScreen> createState() => _TrainerDocumentsScreenState();
}

class _TrainerDocumentsScreenState extends State<TrainerDocumentsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyCtrl = TextEditingController();
  final _kvkCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'NL');
  final _vogCtrl = TextEditingController();
  final _diplomasCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _kvkCtrl.dispose();
    _vatCtrl.dispose();
    _addressCtrl.dispose();
    _postcodeCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _vogCtrl.dispose();
    _diplomasCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    Haptics.selection();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<GymiesApi>().getTrainerDocuments();
      if (!mounted) return;
      setState(() {
        _companyCtrl.text = mapStr(data, ['company_name', 'companyName']);
        _kvkCtrl.text = mapStr(data, ['kvk_number', 'kvk']);
        _vatCtrl.text = mapStr(data, ['vat_number', 'vat']);
        _addressCtrl.text = mapStr(data, [
          'trainer_address_line1',
          'address_line1',
          'address',
        ]);
        _postcodeCtrl.text = mapStr(data, ['trainer_postcode', 'postcode']);
        _cityCtrl.text = mapStr(data, ['trainer_city', 'city']);
        _countryCtrl.text = mapStr(data, [
          'trainer_country',
          'country',
          'country_code',
        ]);
        if (_countryCtrl.text.trim().isEmpty) _countryCtrl.text = 'NL';
        _vogCtrl.text = mapStr(data, ['vog_url', 'vog_document_url']);
        final diplomas = data['diploma_urls'];
        if (diplomas is List) {
          _diplomasCtrl.text = diplomas.map((e) => e.toString()).join('\n');
        } else {
          _diplomasCtrl.text = mapStr(data, ['diploma_url', 'diplomas']);
        }
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
        _error = 'Kon documenten niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    Haptics.light();
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final diplomaLines = _diplomasCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final api = context.read<GymiesApi>();
    try {
      await api.updateTrainerDocuments({
        'company_name': _companyCtrl.text.trim(),
        'kvk_number': _kvkCtrl.text.trim(),
        'vat_number': _vatCtrl.text.trim(),
        'trainer_address_line1': _addressCtrl.text.trim(),
        'trainer_postcode': _postcodeCtrl.text.trim(),
        'trainer_city': _cityCtrl.text.trim(),
        'trainer_country': _countryCtrl.text.trim(),
        'vog_url': _vogCtrl.text.trim(),
        'diploma_urls': diplomaLines,
      });
      final refreshed = await api.getTrainerDocuments();
      bool hasAny(List<String> keys) {
        for (final key in keys) {
          final value = refreshed[key];
          if (value != null && value.toString().trim().isNotEmpty) return true;
        }
        return false;
      }

      final verified =
          hasAny(const ['company_name', 'companyName']) &&
          hasAny(const ['kvk_number', 'kvk']) &&
          hasAny(const ['trainer_address_line1', 'address_line1', 'address']) &&
          hasAny(const ['trainer_postcode', 'postcode']) &&
          hasAny(const ['trainer_city', 'city']) &&
          hasAny(const ['trainer_country', 'country', 'country_code']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verified
                ? 'Documenten opgeslagen'
                : 'Opslaan gelukt, maar controleer verplichte velden opnieuw.',
          ),
          backgroundColor: verified ? GymiesColors.darkBlue : Colors.orange,
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

  Widget _sectionHeader(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: GymiesColors.darkBlue),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: GymiesColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Documenten'),
      body: _error != null
          ? Center(child: Text(_error!))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _sectionHeader(Icons.business_outlined, 'Bedrijfsgegevens'),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                          children: [
                            TextFormField(
                              controller: _companyCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Bedrijfsnaam (voor factuur)',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Bedrijfsnaam is verplicht'
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _kvkCtrl,
                              decoration: const InputDecoration(
                                labelText: 'KVK-nummer',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'KVK is verplicht'
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _vatCtrl,
                              decoration: const InputDecoration(
                                labelText: 'BTW-nummer',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _addressCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Adresregel 1',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Adres is verplicht'
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _postcodeCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Postcode',
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                        ? 'Postcode is verplicht'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _cityCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Stad',
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                        ? 'Stad is verplicht'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _countryCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Land',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Land is verplicht'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    _sectionHeader(Icons.description_outlined, 'Compliance'),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _vogCtrl,
                              decoration: const InputDecoration(
                                labelText: 'VOG link (optioneel)',
                                hintText: 'https://...',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _diplomasCtrl,
                              minLines: 2,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: 'Diploma links (optioneel)',
                                hintText: '1 link per regel',
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                        ),
                        child: Text(_saving ? 'Bezig...' : 'Opslaan'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
