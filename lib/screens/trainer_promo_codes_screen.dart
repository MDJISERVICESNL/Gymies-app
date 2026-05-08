import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../utils/currency_format.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
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
    Haptics.selection();
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
        _error = S.of(context).konPromotiecodesNietLaden;
        _loading = false;
      });
    }
  }

  /// Geeft de display-waarde voor het bewerkingsformulier.
  String _displayValueFromCents(Map<String, dynamic>? item, String type) {
    final raw = mapPick(item, ['value_cents', 'valueCents', 'discount_value', 'discountValue', 'value']);
    if (raw == null) return '';
    final cents = (raw is int) ? raw : int.tryParse(raw.toString()) ?? 0;
    if (type == 'percent') return cents.toString();
    return (cents / 100).toStringAsFixed(2);
  }

  /// Hilfsfunktion zum Extrahieren von max_redemptions
  int? _getMaxRedemptions(Map<String, dynamic>? item) {
    if (item == null) return null;
    final raw = mapPick(item, ['max_redemptions', 'maxRedemptions']);
    if (raw == null) return null;
    return raw is int ? raw : int.tryParse(raw.toString());
  }

  /// Hilfsfunktion zum Extrahieren von valid_until
  String? _getValidUntil(Map<String, dynamic>? item) {
    if (item == null) return null;
    final raw = mapStr(item, ['valid_until', 'validUntil', 'expires_at', 'expiresAt']);
    return raw.isEmpty ? null : raw;
  }

  /// Hilfsfunktion zum Formatieren von Datum für die Anzeige
  String _formatDateDisplay(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return S.of(context).geenEinddatum;
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _discountType(Map<String, dynamic> c) {
    final t = mapStr(c, ['discount_type', 'discountType']);
    return t.isNotEmpty ? t : 'percent';
  }

  int _valueCents(Map<String, dynamic> c) {
    final raw = mapPick(c, [
      'value_cents', 'valueCents', 'discount_value', 'discountValue', 'value',
    ]);
    return (raw is int) ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _discountDisplay(Map<String, dynamic> c) {
    final type = _discountType(c);
    final cents = _valueCents(c);
    if (type == 'percent') return '-$cents%';
    return '-${formatEuro(cents)}';
  }

  Future<void> _showDialog({Map<String, dynamic>? item}) async {
    Haptics.selection();
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
    final maxRedemptions = TextEditingController(
      text: _getMaxRedemptions(item)?.toString() ?? '',
    );
    String? validUntil = _getValidUntil(item);
    String selectedPackage = S.of(context).allePakketten;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return GymiesDialog(
              title: item == null ? S.of(context).promocodeToevoegen : 'Promocode bewerken',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: S.of(context).code),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: discountType,
                    items: const [
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text(S.of(context).percentage),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text(S.of(context).vastBedrag),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        discountType = v;
                        value.clear();
                      });
                    },
                    decoration: const InputDecoration(labelText: S.of(context).type),
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: maxRedemptions,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: S.of(context).maxInwisselingenleegOnbeperkt,
                      hintText: S.of(context).bijv50,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        S.of(context).geldigTot,
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: validUntil != null
                                ? DateTime.tryParse(validUntil!) ?? DateTime.now()
                                : DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              validUntil = picked.toIso8601String().split('T').first;
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(validUntil != null ? _formatDateDisplay(validUntil) : S.of(context).geenEinddatum),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPackage,
                    items: const [
                      DropdownMenuItem(
                        value: S.of(context).allePakketten,
                        child: Text(S.of(context).allePakketten),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        selectedPackage = v;
                      });
                    },
                    decoration: const InputDecoration(labelText: S.of(context).geldigVoor),
                  ),
                ],
              ),
              actions: [
                GymiesDialogAction(
                  label: S.of(context).annuleren,
                  onPressed: _saving ? null : () => Navigator.of(ctx).pop(),
                ),
                GymiesDialogAction(
                  label: S.of(context).opslaan,
                  isPrimary: true,
                  onPressed: _saving
                      ? null
                      : () async {
                          Haptics.light();
                          final navigator = Navigator.of(ctx);
                          final codeText = code.text.trim().toUpperCase();

                          int? valueCents;
                          String? validationError;

                          if (codeText.isEmpty) {
                            validationError = S.of(context).vulEenPromocodeIn;
                          } else if (discountType == 'percent') {
                            final pct = int.tryParse(value.text.trim());
                            if (pct == null || pct <= 0) {
                              validationError = S.of(context).vulEenGeldigPercentageIn1100;
                            } else if (pct > 100) {
                              validationError = S.of(context).percentageMagNietHogerZijnDan;
                            } else {
                              valueCents = pct;
                            }
                          } else {
                            final euro = double.tryParse(
                              value.text.trim().replaceAll(',', '.'),
                            );
                            if (euro == null || euro <= 0) {
                              validationError = S.of(context).vulEenGeldigBedragInBijv;
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
                            final maxRedempInt = maxRedemptions.text.trim().isEmpty
                                ? null
                                : int.tryParse(maxRedemptions.text.trim());

                            if (item == null) {
                              await api.createTrainerPromoCode(
                                code: codeText,
                                discountType: discountType,
                                valueCents: valueCents!,
                                maxRedemptions: maxRedempInt,
                                validUntil: validUntil,
                              );
                            } else {
                              final promoId = _resolvePromoId(item);
                              if (promoId == null) {
                                _showError(
                                  S.of(context).promocodeidOntbreektVernieuwDeLijstEn,
                                );
                                return;
                              }
                              await api.updateTrainerPromoCode(
                                id: promoId,
                                code: codeText,
                                discountType: discountType,
                                valueCents: valueCents!,
                                maxRedemptions: maxRedempInt,
                                validUntil: validUntil,
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
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    Haptics.heavy();
    if (_saving) return;
    final confirmed = await GymiesDialog.destructive(
      context,
      title: S.of(context).promocodeVerwijderenVraag,
      message: S.of(context).weetJeZekerDatJeDeze,
      confirmLabel: S.of(context).verwijderen,
    );
    if (confirmed != true || !mounted) return;
    final promoId = _resolvePromoId(item);
    if (promoId == null) {
      _showError(
        S.of(context).promocodeidOntbreektVernieuwDeLijstEn,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<GymiesApi>().deleteTrainerPromoCode(promoId);
      if (!mounted) return;
      await _load();
      _showSuccess(S.of(context).promocodeVerwijderd);
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

  Color _getCardBorderColor(Map<String, dynamic> code) {
    final maxRedem = _getMaxRedemptions(code);
    if (maxRedem == null || maxRedem <= 0) return Colors.grey.shade200;

    final usedCount = mapPick(code, ['redemption_count', 'redemptionCount', 'used_count', 'usedCount']);
    final used = usedCount is int ? usedCount : int.tryParse(usedCount?.toString() ?? '') ?? 0;

    if (used >= maxRedem) return Colors.red;
    if (used / maxRedem > 0.8) return Colors.orange;
    return Colors.grey.shade200;
  }

  Widget _buildUsageStatsRow(Map<String, dynamic> code) {
    final maxRedem = _getMaxRedemptions(code);
    final usedCount = mapPick(code, ['redemption_count', 'redemptionCount', 'used_count', 'usedCount']);
    final used = usedCount is int ? usedCount : int.tryParse(usedCount?.toString() ?? '') ?? 0;
    final validUntil = _getValidUntil(code);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Usage count and max redemptions
        Row(
          children: [
            Text(
              '$used keer gebruikt',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if (maxRedem != null && maxRedem > 0) ...[
              const SizedBox(width: 6),
              Text(
                'van $maxRedem max',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
        // Expiry date
        if (validUntil != null && validUntil.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Geldig tot: ${_formatDateDisplay(validUntil)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        // Progress bar if there's a limit
        if (maxRedem != null && maxRedem > 0) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: used > 0 ? (used / maxRedem).clamp(0, 1) : 0,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                used >= maxRedem
                    ? Colors.red
                    : (used / maxRedem > 0.8)
                        ? Colors.orange
                        : Colors.green,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STATS
  // ═══════════════════════════════════════════════════════════════════

  // ignore: unused_element
  int _percentCount() =>
      _codes.where((c) => _discountType(c) == 'percent').length;

  // ignore: unused_element
  int _fixedCount() =>
      _codes.where((c) => _discountType(c) != 'percent').length;

  int _activeCodesCount() {
    return _codes.where((c) {
      final validUntil = _getValidUntil(c);
      if (validUntil == null || validUntil.isEmpty) return true;
      try {
        final expiryDate = DateTime.parse(validUntil);
        return expiryDate.isAfter(DateTime.now());
      } catch (_) {
        return true;
      }
    }).length;
  }

  int _totalRedemptionCount() {
    int total = 0;
    for (final code in _codes) {
      final count = mapPick(code, ['redemption_count', 'redemptionCount', 'used_count', 'usedCount']);
      if (count != null) {
        total += count is int ? count : int.tryParse(count.toString()) ?? 0;
      }
    }
    return total;
  }

  String _mostPopularCode() {
    if (_codes.isEmpty) return '-';
    int maxCount = 0;
    String mostPopular = '-';
    for (final code in _codes) {
      final count = mapPick(code, ['redemption_count', 'redemptionCount', 'used_count', 'usedCount']);
      final codeVal = mapStr(code, ['code', 'promo_code']);
      if (codeVal.isNotEmpty) {
        final intCount = count is int ? count : int.tryParse(count?.toString() ?? '') ?? 0;
        if (intCount > maxCount) {
          maxCount = intCount;
          mostPopular = codeVal;
        }
      }
    }
    return mostPopular;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Promocodes'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _showDialog,
        backgroundColor: GymiesColors.primary,
        foregroundColor: GymiesColors.darkBlue,
        icon: const Icon(Icons.add),
        label: const Text(S.of(context).promocode),
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
                    title: S.of(context).nogGeenPromotiecodes,
                    subtitle: S.of(context).maakPromotiesVoorKlanten,
                    actionLabel: 'Promocode toevoegen',
                    actionIcon: Icons.add,
                    onAction: _showDialog,
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _codes.length + 1, // +1 voor stats strip
                itemBuilder: (_, i) {
                  // Stats strip als eerste item
                  if (i == 0) {
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 80),
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 16),
                          child: child,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            _StatBox(
                              value: '${_activeCodesCount()}',
                              label: S.of(context).actieveCodes,
                            ),
                            const SizedBox(width: 8),
                            _StatBox(
                              value: '${_totalRedemptionCount()}',
                              label: 'Totaal gebruikt',
                            ),
                            const SizedBox(width: 8),
                            _StatBox(
                              value: _mostPopularCode(),
                              label: 'Populairste',
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final idx = i - 1;
                  final c = _codes[idx];
                  final type = _discountType(c);
                  final isPercent = type == 'percent';
                  final codeText = mapStr(c, ['code', 'promo_code']).isNotEmpty
                      ? mapStr(c, ['code', 'promo_code'])
                      : 'CODE';

                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 120 + (idx * 40)),
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 16),
                        child: child,
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _getCardBorderColor(c),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: GestureDetector(
                        onTap: _saving ? null : () => _showDialog(item: c),
                        onLongPress: _saving ? null : () => _delete(c),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Code + type pill
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          codeText,
                                          style: GoogleFonts.sora(
                                            fontSize: 18,
                                            letterSpacing: 1.2,
                                            color: GymiesColors.darkBlue,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isPercent
                                                ? Colors.green.shade50
                                                : Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isPercent ? S.of(context).percentage : S.of(context).vastBedrag,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isPercent
                                                  ? Colors.green.shade700
                                                  : Colors.blue.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Discount display
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _discountDisplay(c),
                                        style: GoogleFonts.sora(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: isPercent
                                              ? Colors.green.shade600
                                              : Colors.blue.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        S.of(context).bewerku203a,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Usage stats and expiry info
                              _buildUsageStatsRow(c),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: GymiesColors.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: GymiesColors.darkBlue.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
