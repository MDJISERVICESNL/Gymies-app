import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class TrainerFinanceScreen extends StatefulWidget {
  const TrainerFinanceScreen({super.key});

  @override
  State<TrainerFinanceScreen> createState() => _TrainerFinanceScreenState();
}

class _TrainerFinanceScreenState extends State<TrainerFinanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _forecast = {};
  Map<String, dynamic> _payoutSettings = {};
  Map<String, dynamic> _payoutPreview = {};
  List<Map<String, dynamic>> _payouts = [];
  List<Map<String, dynamic>> _payoutCalendar = [];
  List<Map<String, dynamic>> _invoices = [];
  bool _savingSettings = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final forecast = await api.getTrainerRevenueForecast();
      final settings = await api.getTrainerPayoutSettings();
      final preview = await api.getTrainerPayoutPreview();
      final payouts = await api.getTrainerPayouts();
      final calendar = await api.getTrainerPayoutCalendar();
      final invoices = await api.getTrainerInvoices();
      if (!mounted) return;
      setState(() {
        _forecast = forecast;
        _payoutSettings = settings;
        _payoutPreview = preview;
        _payouts = payouts;
        _payoutCalendar = calendar;
        _invoices = invoices;
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
        _error = 'Kon geavanceerde financiën niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _requestPayoutNow() async {
    try {
      await context.read<GymiesApi>().requestTrainerPayoutNow();
      if (!mounted) return;
      _showSuccess('Uitbetalingsverzoek verstuurd');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editPayoutSettings() async {
    final methodController = TextEditingController(
      text: mapStr(_payoutSettings, ['method', 'payout_method']).isNotEmpty
          ? mapStr(_payoutSettings, ['method', 'payout_method'])
          : 'bank_transfer',
    );
    final ibanController = TextEditingController(
      text: mapStr(_payoutSettings, ['iban', 'iban_number']),
    );
    final nameController = TextEditingController(
      text: mapStr(_payoutSettings, [
        'account_name',
        'accountName',
        'beneficiary_name',
      ]),
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payout instellingen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: methodController,
              decoration: const InputDecoration(labelText: 'Methode'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ibanController,
              decoration: const InputDecoration(labelText: 'IBAN'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Rekeningnaam'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _savingSettings ? null : () => Navigator.of(ctx).pop(),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: _savingSettings
                ? null
                : () async {
                    Navigator.of(ctx).pop();
                    setState(() => _savingSettings = true);
                    try {
                      await context
                          .read<GymiesApi>()
                          .updateTrainerPayoutSettings(
                            method: methodController.text.trim(),
                            iban: ibanController.text.trim(),
                            accountName: nameController.text.trim(),
                          );
                      if (!mounted) return;
                      _showSuccess('Payout instellingen opgeslagen');
                      await _load();
                    } on ApiException catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.message),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _savingSettings = false);
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
    );
  }

  Future<void> _loadQuarterZipInfo() async {
    try {
      final data = await context
          .read<GymiesApi>()
          .getTrainerInvoicesQuarterZip();
      if (!mounted) return;
      final url = data['url']?.toString();
      _showSuccess(
        url == null || url.isEmpty ? 'ZIP export gestart' : 'ZIP ready',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _currency(dynamic cents) {
    final v = _toInt(cents);
    if (v == null) return '-';
    return '€${(v / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Financiën+',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GymiesColors.primary,
          labelColor: GymiesColors.primary,
          tabs: const [
            Tab(text: 'Forecast'),
            Tab(text: 'Payouts'),
            Tab(text: 'Settings'),
            Tab(text: 'Facturen'),
          ],
        ),
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: TabBarView(
          controller: _tabController,
          children: [
            _forecastTab(),
            _payoutsTab(),
            _settingsTab(),
            _invoicesTab(),
          ],
        ),
      ),
    );
  }

  List<_ForecastBarPoint> _forecastChartPoints() {
    final monthCents = _toInt(mapPick(_forecast, [
      'month_estimate_cents',
      'monthEstimateCents',
      'expected_month_cents',
    ])) ?? 0;
    final forecastCents = _toInt(mapPick(_forecast, [
      'forecast_cents',
      'forecastCents',
      'total_forecast_cents',
    ])) ?? 0;
    final weekly = mapPick(_forecast, [
      'weekly_breakdown',
      'by_week',
      'weeks',
    ]);
    if (weekly is List && weekly.isNotEmpty) {
      return weekly.asMap().entries.map((e) {
        final v = e.value;
        final map = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
        final cents = _toInt(mapPick(map, ['cents', 'amount_cents', 'value'])) ?? 0;
        final label = mapStr(map, ['label', 'week', 'period']) != ''
            ? mapStr(map, ['label', 'week', 'period'])
            : 'W${e.key + 1}';
        return _ForecastBarPoint(label: label, value: cents / 100.0);
      }).toList();
    }
    final points = <_ForecastBarPoint>[];
    if (monthCents > 0) {
      points.add(_ForecastBarPoint(label: 'Deze maand', value: monthCents / 100.0));
    }
    if (forecastCents > 0 && forecastCents != monthCents) {
      points.add(_ForecastBarPoint(label: 'Forecast', value: forecastCents / 100.0));
    }
    if (points.isEmpty && (monthCents > 0 || forecastCents > 0)) {
      points.add(_ForecastBarPoint(
        label: 'Verwacht',
        value: (monthCents > 0 ? monthCents : forecastCents) / 100.0,
      ));
    }
    return points;
  }

  Widget _forecastTab() {
    final chartPoints = _forecastChartPoints();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (chartPoints.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Omzetverwachting',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ForecastBarChart(points: chartPoints),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _kvCard(
          'Forecast omzet',
          mapPick(_forecast, [
            'forecast_cents',
            'forecastCents',
            'total_forecast_cents',
          ]),
        ),
        _kvCard(
          'Verwacht deze maand',
          mapPick(_forecast, [
            'month_estimate_cents',
            'monthEstimateCents',
            'expected_month_cents',
          ]),
        ),
      ],
    );
  }

  Widget _payoutsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Payout preview'),
            subtitle: Text(
              'Beschikbaar: ${_currency(mapPick(_payoutPreview, ['available_cents', 'availableCents', 'amount_cents']))}',
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _requestPayoutNow,
          style: FilledButton.styleFrom(
            backgroundColor: GymiesColors.primary,
            foregroundColor: GymiesColors.darkBlue,
          ),
          icon: const Icon(Icons.payments_rounded),
          label: const Text('Vraag nu uitbetaling aan'),
        ),
        const SizedBox(height: 12),
        const Text('Uitbetalingen'),
        ..._payouts.map(
          (e) => Card(
            child: ListTile(
              title: Text(
                mapStr(e, ['status', 'state']).isNotEmpty
                    ? mapStr(e, ['status', 'state'])
                    : 'Payout',
              ),
              subtitle: Text(
                'Bedrag: ${_currency(mapPick(e, ['amount_cents', 'amountCents', 'amount']))}',
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Payout kalender'),
        ..._payoutCalendar.map(
          (e) => Card(
            child: ListTile(
              title: Text(
                mapStr(e, ['date', 'scheduled_at']).isNotEmpty
                    ? mapStr(e, ['date', 'scheduled_at'])
                    : '-',
              ),
              subtitle: Text(mapStr(e, ['label', 'description', 'status'])),
            ),
          ),
        ),
      ],
    );
  }

  /// Toont uitsluitend het gemaskeerde IBAN (backend levert iban_masked / iban_last4).
  /// Toont nooit het volledige IBAN-nummer in de UI.
  String _maskedIban(Map<String, dynamic>? settings) {
    if (settings == null) return '-';
    final masked = settings['iban_masked']?.toString().trim() ?? '';
    if (masked.isNotEmpty) return masked;
    final last4 = settings['iban_last4']?.toString().trim() ?? '';
    if (last4.isNotEmpty) return 'IBAN •••• $last4';
    // Geen gemaskeerde versie beschikbaar: toon alleen of IBAN aanwezig is.
    final raw = settings['iban']?.toString().trim() ?? settings['iban_number']?.toString().trim() ?? '';
    if (raw.isNotEmpty) return 'IBAN ••••';
    return '-';
  }

  Widget _settingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Huidige payout settings'),
            subtitle: Text(
              'Methode: ${mapStr(_payoutSettings, ['method', 'payout_method']).isNotEmpty ? mapStr(_payoutSettings, ['method', 'payout_method']) : '-'}\n'
              'IBAN: ${_maskedIban(_payoutSettings)}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editPayoutSettings,
          ),
        ),
      ],
    );
  }

  Widget _invoicesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _loadQuarterZipInfo,
          style: FilledButton.styleFrom(
            backgroundColor: GymiesColors.primary,
            foregroundColor: GymiesColors.darkBlue,
          ),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Kwartaal ZIP export'),
        ),
        const SizedBox(height: 12),
        ..._invoices.map(
          (e) => Card(
            child: ListTile(
              title: Text(
                mapStr(e, ['number', 'invoice_number']).isNotEmpty
                    ? mapStr(e, ['number', 'invoice_number'])
                    : 'Factuur',
              ),
              subtitle: Text(
                '${mapStr(e, ['date', 'issued_at']).isNotEmpty ? mapStr(e, ['date', 'issued_at']) : '-'} · ${_currency(mapPick(e, ['total_cents', 'totalCents', 'total']))}',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _kvCard(String title, dynamic cents) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(
          _currency(cents),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ForecastBarPoint {
  const _ForecastBarPoint({required this.label, required this.value});
  final String label;
  final double value;
}

class _ForecastBarChart extends StatelessWidget {
  const _ForecastBarChart({required this.points});
  final List<_ForecastBarPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final maxVal =
        points.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final safeMax = maxVal <= 0 ? 1.0 : maxVal;
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((p) {
          final normalized = (p.value / safeMax).clamp(0.08, 1.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 90 * normalized,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '€${p.value.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    p.label,
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
