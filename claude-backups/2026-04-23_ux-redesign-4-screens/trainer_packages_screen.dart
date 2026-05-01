import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class TrainerPackagesScreen extends StatefulWidget {
  const TrainerPackagesScreen({super.key});

  @override
  State<TrainerPackagesScreen> createState() => _TrainerPackagesScreenState();
}

class _TrainerPackagesScreenState extends State<TrainerPackagesScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _packages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<GymiesApi>().getTrainerPackages();
      if (!mounted) return;
      setState(() {
        _packages = list;
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
        _error = 'Kon pakketten niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _showPackageDialog({Map<String, dynamic>? item}) async {
    final name = TextEditingController(text: mapStr(item, ['name', 'title']));
    final sessions = TextEditingController(
      text: mapInt(item, ['sessions_count', 'sessionsCount']).toString(),
    );
    final price = TextEditingController(
      text: _euroFromCents(mapPick(item, ['price_cents', 'priceCents', 'price'])),
    );
    final description = TextEditingController(
      text: mapStr(item, ['description', 'desc']),
    );
    final validityDays = TextEditingController(
      text: mapInt(item, ['validity_days', 'validityDays']) > 0
          ? mapInt(item, ['validity_days', 'validityDays']).toString()
          : '30',
    );
    String lessonType = mapStr(item, ['lesson_type', 'lessonType']).isNotEmpty
        ? mapStr(item, ['lesson_type', 'lessonType'])
        : 'personal';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: Text(item == null ? 'Pakket toevoegen' : 'Pakket bewerken'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Naam'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: lessonType,
                decoration: const InputDecoration(labelText: 'Lestype'),
                items: const [
                  DropdownMenuItem(value: 'personal', child: Text('Personal training')),
                  DropdownMenuItem(value: 'group', child: Text('Groepsles')),
                  DropdownMenuItem(value: 'online', child: Text('Online sessie')),
                  DropdownMenuItem(value: 'duo', child: Text('Duo training')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => lessonType = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sessions,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Aantal sessies'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Prijs (EUR)',
                  hintText: 'bijv. 49.99',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: validityDays,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Geldigheid (dagen)',
                  hintText: 'bijv. 30',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Beschrijving (optioneel)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(ctx).pop(),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    final navigator = Navigator.of(ctx);
                    final sessionsCount = int.tryParse(sessions.text.trim());
                    final euro = double.tryParse(
                      price.text.trim().replaceAll(',', '.'),
                    );
                    if (name.text.trim().isEmpty ||
                        sessionsCount == null ||
                        sessionsCount <= 0 ||
                        euro == null ||
                        euro <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vul naam, een geldig aantal sessies en een geldige prijs in (bijv. 49.99)',
                          ),
                        ),
                      );
                      return;
                    }
                    final priceCents = (euro * 100).round();
                    setState(() => _saving = true);
                    try {
                      final api = context.read<GymiesApi>();
                      final days = int.tryParse(validityDays.text.trim()) ?? 30;
                      if (item == null) {
                        await api.createTrainerPackage(
                          name: name.text.trim(),
                          sessionsCount: sessionsCount,
                          priceCents: priceCents,
                          lessonType: lessonType,
                          validityDays: days,
                          description: description.text.trim(),
                        );
                      } else {
                        final packageId = _resolvePackageId(item);
                        if (packageId == null) {
                          _showError(
                            'Pakket-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.',
                          );
                          return;
                        }
                        await api.updateTrainerPackage(
                          id: packageId,
                          name: name.text.trim(),
                          sessionsCount: sessionsCount,
                          priceCents: priceCents,
                          lessonType: lessonType,
                          validityDays: days,
                          description: description.text.trim(),
                        );
                      }
                      if (navigator.canPop()) navigator.pop();
                      if (!mounted) return;
                      await _load();
                      _showSuccess(
                        item == null
                            ? 'Pakket toegevoegd'
                            : 'Pakket bijgewerkt',
                      );
                    } on ApiException catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.message),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
            ),
            child: const Text('Opslaan'),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (_saving) return;
    final packageId = _resolvePackageId(item);
    if (packageId == null) {
      _showError('Pakket-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<GymiesApi>().deleteTrainerPackage(packageId);
      if (!mounted) return;
      await _load();
      _showSuccess('Pakket verwijderd');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _euroFromCents(dynamic centsRaw) {
    if (centsRaw == null) return '';
    int? cents;
    if (centsRaw is int) {
      cents = centsRaw;
    } else if (centsRaw is num) {
      cents = centsRaw.toInt();
    } else {
      cents = int.tryParse(centsRaw.toString());
    }
    if (cents == null) return '';
    // Altijd behandelen als centen; toon altijd 2 decimalen zodat
    // de gebruiker een accurate prijs ziet (bijv. 4999 → "49.99").
    return (cents / 100).toStringAsFixed(2);
  }

  String? _resolvePackageId(Map<String, dynamic>? map) {
    final id = mapStr(map, ['id', 'package_id', 'packageId']);
    return id.isEmpty ? null : id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Pakketten',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _showPackageDialog,
        backgroundColor: GymiesColors.primary,
        foregroundColor: GymiesColors.darkBlue,
        icon: const Icon(Icons.add),
        label: const Text('Pakket'),
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _packages.isEmpty
                  ? ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        TrainerEmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'Nog geen pakketten',
                          subtitle:
                              'Voeg pakketten toe voor klanten om te boeken.',
                          actionLabel: 'Pakket toevoegen',
                          actionIcon: Icons.add,
                          onAction: _showPackageDialog,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _packages.length,
                      itemBuilder: (_, i) {
                        final p = _packages[i];
                        final price = _euroFromCents(
                          mapPick(p, ['price_cents', 'priceCents', 'price']),
                        );
                        final sessionCount = mapPick(p, [
                          'sessions_count',
                          'sessionsCount',
                        ])?.toString();
                        return Card(
                          child: ListTile(
                            title: Text(
                              mapStr(p, ['name', 'title']).isNotEmpty
                                  ? mapStr(p, ['name', 'title'])
                                  : 'Pakket',
                              style: GoogleFonts.fjallaOne(
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            subtitle: Text(
                              '${sessionCount?.isNotEmpty == true ? sessionCount : '-'} sessies · ${price.isNotEmpty ? '€$price' : 'Prijs onbekend'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _showPackageDialog(item: p),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  onPressed: _saving
                                      ? null
                                      : () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Pakket verwijderen'),
                                              content: Text(
                                                'Weet je zeker dat je "${mapStr(p, ['name', 'title']).isNotEmpty ? mapStr(p, ['name', 'title']) : 'dit pakket'}" wilt verwijderen? Dit kan niet ongedaan worden.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(ctx).pop(false),
                                                  child: const Text('Annuleren'),
                                                ),
                                                FilledButton(
                                                  onPressed: () => Navigator.of(ctx).pop(true),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: Colors.red.shade600,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  child: const Text('Verwijderen'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true) _delete(p);
                                        },
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
