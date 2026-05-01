import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class TrainerPromoCodesScreen extends StatefulWidget {
  const TrainerPromoCodesScreen({super.key});

  @override
  State<TrainerPromoCodesScreen> createState() =>
      _TrainerPromoCodesScreenState();
}

class _TrainerPromoCodesScreenState extends State<TrainerPromoCodesScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _codes = [];

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
      final list = await context.read<GymiesApi>().getTrainerPromoCodes();
      if (!mounted) return;
      setState(() {
        _codes = list;
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
        _error = 'Kon promotiecodes niet laden.';
        _loading = false;
      });
    }
  }

  /// Geeft de display-waarde voor het bewerkingsformulier.
  /// Backend slaat alles op als value_cents.
  /// - percent: 1500 → "15" (15%)
  /// - fixed:   4999 → "49.99" (€49.99)
  String _displayValueFromCents(Map<String, dynamic>? item, String type) {
    final raw = mapPick(item, ['value_cents', 'valueCents', 'discount_value', 'discountValue', 'value']);
    if (raw == null) return '';
    final cents = (raw is int) ? raw : int.tryParse(raw.toString()) ?? 0;
    if (type == 'percent') {
      // Backend slaat procent op als geheel getal in value_cents (bijv. 15 = 15%)
      return cents.toString();
    }
    // Fixed: centen naar euro
    return (cents / 100).toStringAsFixed(2);
  }

  Future<void> _showDialog({Map<String, dynamic>? item}) async {
    final code = TextEditingController(
      text: mapStr(item, ['code', 'promo_code']),
    );
    String discountType =
        mapStr(item, ['discount_type', 'discountType']).isNotEmpty
        ? mapStr(item, ['discount_type', 'discountType'])
        : 'percent';
    final value = TextEditingController(
      text: _displayValueFromCents(item, discountType),
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              title: Text(
                item == null ? 'Promocode toevoegen' : 'Promocode bewerken',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Code'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: discountType,
                    items: const [
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text('Percentage'),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text('Vast bedrag'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        discountType = v;
                        value.clear();
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: value,
                    keyboardType: discountType == 'percent'
                        ? TextInputType.number
                        : const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: discountType == 'percent'
                          ? 'Waarde (%)'
                          : 'Waarde (EUR)',
                      hintText: discountType == 'percent'
                          ? 'bijv. 15'
                          : 'bijv. 5.00',
                    ),
                  ),
                ],
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
                          final codeText = code.text.trim().toUpperCase();

                          // Bereken value_cents afhankelijk van type
                          int? valueCents;
                          String? validationError;

                          if (codeText.isEmpty) {
                            validationError = 'Vul een promocode in';
                          } else if (discountType == 'percent') {
                            final pct = int.tryParse(value.text.trim());
                            if (pct == null || pct <= 0) {
                              validationError = 'Vul een geldig percentage in (1-100)';
                            } else if (pct > 100) {
                              validationError = 'Percentage mag niet hoger zijn dan 100%';
                            } else {
                              valueCents = pct;
                            }
                          } else {
                            // fixed: gebruiker voert EUR in, wij converteren naar centen
                            final euro = double.tryParse(
                              value.text.trim().replaceAll(',', '.'),
                            );
                            if (euro == null || euro <= 0) {
                              validationError = 'Vul een geldig bedrag in (bijv. 5.00)';
                            } else {
                              valueCents = (euro * 100).round();
                            }
                          }

                          if (validationError != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(validationError)),
                            );
                            return;
                          }

                          setState(() => _saving = true);
                          try {
                            final api = context.read<GymiesApi>();
                            if (item == null) {
                              await api.createTrainerPromoCode(
                                code: codeText,
                                discountType: discountType,
                                valueCents: valueCents!,
                              );
                            } else {
                              final promoId = _resolvePromoId(item);
                              if (promoId == null) {
                                _showError(
                                  'Promocode-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.',
                                );
                                return;
                              }
                              await api.updateTrainerPromoCode(
                                id: promoId,
                                code: codeText,
                                discountType: discountType,
                                valueCents: valueCents!,
                              );
                            }
                            if (navigator.canPop()) navigator.pop();
                            if (!mounted) return;
                            await _load();
                            _showSuccess(
                              item == null
                                  ? 'Promocode toegevoegd'
                                  : 'Promocode bijgewerkt',
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
            );
          },
        );
      },
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (_saving) return;
    // Bevestigingsdialoog — voorkom per ongeluk verwijderen
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promocode verwijderen?'),
        content: const Text(
          'Weet je zeker dat je deze promocode wilt verwijderen? Dit kan niet ongedaan worden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final promoId = _resolvePromoId(item);
    if (promoId == null) {
      _showError(
        'Promocode-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<GymiesApi>().deleteTrainerPromoCode(promoId);
      if (!mounted) return;
      await _load();
      _showSuccess('Promocode verwijderd');
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

  String? _resolvePromoId(Map<String, dynamic>? map) {
    final id = mapStr(map, ['id', 'promo_code_id', 'promoCodeId']);
    return id.isEmpty ? null : id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Promocodes',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _showDialog,
        backgroundColor: GymiesColors.primary,
        foregroundColor: GymiesColors.darkBlue,
        icon: const Icon(Icons.add),
        label: const Text('Promocode'),
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _codes.isEmpty
                  ? ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        TrainerEmptyState(
                          icon: Icons.local_offer_outlined,
                          title: 'Nog geen promotiecodes',
                          subtitle: 'Maak promoties voor klanten.',
                          actionLabel: 'Promocode toevoegen',
                          actionIcon: Icons.add,
                          onAction: _showDialog,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _codes.length,
                      itemBuilder: (_, i) {
                        final c = _codes[i];
                        final type =
                            mapStr(c, [
                              'discount_type',
                              'discountType',
                            ]).isNotEmpty
                            ? mapStr(c, ['discount_type', 'discountType'])
                            : 'percent';
                        final rawCents = mapPick(c, [
                          'value_cents',
                          'valueCents',
                          'discount_value',
                          'discountValue',
                          'value',
                        ]);
                        final cents = (rawCents is int)
                            ? rawCents
                            : int.tryParse(rawCents?.toString() ?? '') ?? 0;
                        final displayValue = type == 'percent'
                            ? '$cents% korting'
                            : '€${(cents / 100).toStringAsFixed(2)} korting';
                        return Card(
                          child: ListTile(
                            title: Text(
                              mapStr(c, ['code', 'promo_code']).isNotEmpty
                                  ? mapStr(c, ['code', 'promo_code'])
                                  : 'CODE',
                              style: GoogleFonts.fjallaOne(
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            subtitle: Text(displayValue),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _showDialog(item: c),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  onPressed: _saving ? null : () => _delete(c),
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
