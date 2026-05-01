import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
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
  List<Map<String, dynamic>> _expiringPackages = [];
  bool _expandExpiry = false;
  String _sortBy = 'naam'; // 'naam', 'prijs', 'verkocht'

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
      final api = context.read<GymiesApi>();
      final list = await api.getTrainerPackages();
      List<Map<String, dynamic>> expiring = [];
      try {
        final expiringRaw = await api.getTrainerPackageExpiringSoon();
        expiring = List<Map<String, dynamic>>.from(expiringRaw);
      } catch (e) {
        if (kDebugMode) debugPrint('[Packages] Expiring packages fout: $e');
      }
      if (!mounted) return;
      setState(() {
        _packages = List<Map<String, dynamic>>.from(list);
        _expiringPackages = expiring;
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
    Haptics.selection();
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
        builder: (context, setDialogState) => GymiesDialog(
          title: item == null ? 'Pakket toevoegen' : 'Pakket bewerken',
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
            GymiesDialogAction(
              label: 'Annuleren',
              onPressed: _saving ? null : () => Navigator.of(ctx).pop(),
            ),
            GymiesDialogAction(
              label: 'Opslaan',
              isPrimary: true,
              onPressed: _saving
                  ? null
                  : () async {
                      Haptics.light();
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    Haptics.heavy();
    if (_saving) return;
    final packageId = _resolvePackageId(item);
    if (packageId == null) {
      _showError('Pakket-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.');
      return;
    }
    final confirmed = await GymiesDialog.destructive(
      context,
      title: 'Pakket verwijderen',
      message: 'Weet je zeker dat je "${mapStr(item, ['name', 'title']).isNotEmpty ? mapStr(item, ['name', 'title']) : 'dit pakket'}" wilt verwijderen? Dit kan niet ongedaan worden.',
      confirmLabel: 'Verwijderen',
    );
    if (confirmed != true || !mounted) return;
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
    return (cents / 100).toStringAsFixed(2);
  }

  String _euroDisplay(dynamic centsRaw) {
    final str = _euroFromCents(centsRaw);
    return str.isEmpty ? '-' : '\u20AC$str';
  }

  String? _resolvePackageId(Map<String, dynamic>? map) {
    final id = mapStr(map, ['id', 'package_id', 'packageId']);
    return id.isEmpty ? null : id;
  }

  String _lessonTypeLabel(String type) {
    switch (type) {
      case 'personal':
        return 'Personal';
      case 'group':
        return 'Groepsles';
      case 'online':
        return 'Online';
      case 'duo':
        return 'Duo';
      default:
        return type;
    }
  }

  Color _lessonTypeColor(String type) {
    switch (type) {
      case 'personal':
        return Colors.green.shade600;
      case 'group':
        return Colors.blue.shade600;
      case 'online':
        return Colors.purple.shade600;
      case 'duo':
        return Colors.orange.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  Color _lessonTypeBg(String type) {
    switch (type) {
      case 'personal':
        return Colors.green.shade50;
      case 'group':
        return Colors.blue.shade50;
      case 'online':
        return Colors.purple.shade50;
      case 'duo':
        return Colors.orange.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STATS & ANALYTICS
  // ═══════════════════════════════════════════════════════════════════

  int _totalSessions() {
    int total = 0;
    for (final p in _packages) {
      total += mapInt(p, ['sessions_count', 'sessionsCount']);
    }
    return total;
  }

  String _avgPrice() {
    if (_packages.isEmpty) return '-';
    int totalCents = 0;
    for (final p in _packages) {
      final raw = mapPick(p, ['price_cents', 'priceCents', 'price']);
      if (raw is int) {
        totalCents += raw;
      } else if (raw is num) {
        totalCents += raw.toInt();
      } else {
        totalCents += int.tryParse(raw?.toString() ?? '') ?? 0;
      }
    }
    final avg = totalCents / _packages.length / 100;
    return '\u20AC${avg.toStringAsFixed(0)}';
  }

  String _topSoldPackageName() {
    if (_packages.isEmpty) return '-';
    Map<String, dynamic>? highest;
    int highestCount = -1;
    for (final p in _packages) {
      final count = mapInt(p, ['sold_count', 'soldCount']);
      if (count > highestCount) {
        highestCount = count;
        highest = p;
      }
    }
    if (highest == null || highestCount == 0) return '-';
    return mapStr(highest, ['name', 'title']).isNotEmpty
        ? mapStr(highest, ['name', 'title'])
        : 'Pakket';
  }

  int _totalSoldCount() {
    int total = 0;
    for (final p in _packages) {
      total += mapInt(p, ['sold_count', 'soldCount']);
    }
    return total;
  }

  List<Map<String, dynamic>> _sortedPackages() {
    final sorted = List<Map<String, dynamic>>.from(_packages);
    switch (_sortBy) {
      case 'prijs':
        sorted.sort((a, b) {
          final aCents = mapPick(a, ['price_cents', 'priceCents', 'price']) ?? 0;
          final bCents = mapPick(b, ['price_cents', 'priceCents', 'price']) ?? 0;
          int aInt = 0, bInt = 0;
          if (aCents is int) aInt = aCents;
          else if (aCents is num) aInt = aCents.toInt();
          else aInt = int.tryParse(aCents?.toString() ?? '') ?? 0;
          if (bCents is int) bInt = bCents;
          else if (bCents is num) bInt = bCents.toInt();
          else bInt = int.tryParse(bCents?.toString() ?? '') ?? 0;
          return aInt.compareTo(bInt);
        });
        break;
      case 'verkocht':
        sorted.sort((a, b) {
          final aCount = mapInt(a, ['sold_count', 'soldCount']);
          final bCount = mapInt(b, ['sold_count', 'soldCount']);
          return bCount.compareTo(aCount); // descending
        });
        break;
      case 'naam':
      default:
        sorted.sort((a, b) {
          final aName = mapStr(a, ['name', 'title']).toLowerCase();
          final bName = mapStr(b, ['name', 'title']).toLowerCase();
          return aName.compareTo(bName);
        });
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Pakketten'),
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
                itemCount: _sortedPackages().length + (_expiringPackages.isNotEmpty ? 3 : 2), // +1 for analytics, +1 for expiry section, +1 for sort chips
                itemBuilder: (_, i) {
                  // Item 0: Analytics summary
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
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: GymiesColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.insights_rounded, size: 15, color: GymiesColors.darkBlue),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Pakket prestaties',
                                  style: GoogleFonts.sora(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _AnalyticsCard(title: 'Meest verkocht', value: _topSoldPackageName(), icon: Icons.star_rounded),
                            const SizedBox(height: 8),
                            _AnalyticsCard(title: 'Totaal verkocht', value: '${_totalSoldCount()}', icon: Icons.shopping_bag_rounded),
                            const SizedBox(height: 8),
                            _AnalyticsCard(title: 'Gem. waarde', value: _avgPrice(), icon: Icons.euro_rounded),
                          ],
                        ),
                      ),
                    );
                  }

                  // Item 1: Expiry alerts section (if any)
                  if (i == 1 && _expiringPackages.isNotEmpty) {
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 100),
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 16),
                          child: child,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () {
                                Haptics.selection();
                                setState(() => _expandExpiry = !_expandExpiry);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.orange.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.access_time, size: 16, color: Colors.orange.shade600),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Verlopende pakketten',
                                        style: GoogleFonts.sora(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      _expandExpiry ? Icons.expand_less : Icons.expand_more,
                                      size: 18,
                                      color: Colors.orange.shade600,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_expandExpiry) ...[
                              const SizedBox(height: 8),
                              ..._expiringPackages.map((ep) {
                                final clientName = mapStr(ep, ['client_name', 'clientName']);
                                final packageName = mapStr(ep, ['package_name', 'packageName']);
                                final daysRemaining = mapInt(ep, ['days_remaining', 'daysRemaining']);
                                final isUrgent = daysRemaining <= 3;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade100),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              clientName,
                                              style: GoogleFonts.sora(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: GymiesColors.darkBlue,
                                              ),
                                            ),
                                            Text(
                                              packageName,
                                              style: GoogleFonts.sora(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isUrgent ? Colors.red.shade100 : Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '$daysRemaining dag${daysRemaining == 1 ? '' : 'en'}',
                                          style: GoogleFonts.sora(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: isUrgent ? Colors.red.shade700 : Colors.orange.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  // Item 1 or 2: Sort chips
                  final sortChipsIndex = _expiringPackages.isNotEmpty ? 2 : 1;
                  if (i == sortChipsIndex) {
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 100),
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 16),
                          child: child,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            _SortChip(
                              label: 'Naam',
                              selected: _sortBy == 'naam',
                              onTap: () {
                                Haptics.selection();
                                setState(() => _sortBy = 'naam');
                              },
                            ),
                            _SortChip(
                              label: 'Prijs',
                              selected: _sortBy == 'prijs',
                              onTap: () {
                                Haptics.selection();
                                setState(() => _sortBy = 'prijs');
                              },
                            ),
                            _SortChip(
                              label: 'Meest verkocht',
                              selected: _sortBy == 'verkocht',
                              onTap: () {
                                Haptics.selection();
                                setState(() => _sortBy = 'verkocht');
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Package cards
                  final baseIndex = _expiringPackages.isNotEmpty ? 3 : 2;
                  final idx = i - baseIndex;
                  final sortedPkgs = _sortedPackages();
                  if (idx < 0 || idx >= sortedPkgs.length) return const SizedBox.shrink();
                  final p = sortedPkgs[idx];
                  final priceCents = mapPick(p, ['price_cents', 'priceCents', 'price']);
                  final sessionCount = mapInt(p, ['sessions_count', 'sessionsCount']);
                  final lessonType = mapStr(p, ['lesson_type', 'lessonType']).isNotEmpty
                      ? mapStr(p, ['lesson_type', 'lessonType'])
                      : 'personal';
                  final validityDays = mapInt(p, ['validity_days', 'validityDays']);
                  final packageName = mapStr(p, ['name', 'title']).isNotEmpty
                      ? mapStr(p, ['name', 'title'])
                      : 'Pakket';

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
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: _saving ? null : () => _showPackageDialog(item: p),
                        onLongPress: _saving ? null : () => _delete(p),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Naam + prijs + badges
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          packageName,
                                          style: GoogleFonts.sora(
                                            fontSize: 15,
                                            color: GymiesColors.darkBlue,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '${mapInt(p, ['sold_count', 'soldCount'])} verkocht',
                                                style: GoogleFonts.sora(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '${mapInt(p, ['active_count', 'activeCount'])} actief',
                                                style: GoogleFonts.sora(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.green.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _euroDisplay(priceCents),
                                    style: GoogleFonts.sora(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: GymiesColors.darkBlue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Pills
                              if (mapInt(p, ['sold_count', 'soldCount']) == 0)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'Nog geen verkopen',
                                    style: GoogleFonts.sora(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _Pill(
                                    text: '$sessionCount ${sessionCount == 1 ? 'sessie' : 'sessies'}',
                                    bg: Colors.blue.shade50,
                                    fg: Colors.blue.shade700,
                                  ),
                                  _Pill(
                                    text: _lessonTypeLabel(lessonType),
                                    bg: _lessonTypeBg(lessonType),
                                    fg: _lessonTypeColor(lessonType),
                                  ),
                                  if (validityDays > 0)
                                    _Pill(
                                      text: '$validityDays dagen geldig',
                                      bg: Colors.grey.shade100,
                                      fg: Colors.grey.shade600,
                                    ),
                                ],
                              ),
                              // Edit hint
                              const SizedBox(height: 6),
                              Text(
                                'Tik om te bewerken \u00B7 lang indrukken om te verwijderen',
                                style: GoogleFonts.sora(
                                  fontSize: 10,
                                  color: Colors.grey.shade400,
                                ),
                              ),
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
          color: GymiesColors.primary.withValues(alpha: 0.12),
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
              style: GoogleFonts.sora(
                fontSize: 10,
                color: GymiesColors.darkBlue.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.sora(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: GymiesColors.darkBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.sora(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: GymiesColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? GymiesColors.primary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? GymiesColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? GymiesColors.darkBlue : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}
