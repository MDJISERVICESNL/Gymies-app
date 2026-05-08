import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/ui_constants.dart';
import '../theme/gymies_theme.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../utils/haptics.dart';
import '../l10n/generated/app_localizations.dart';

/// Default feature-matrix wanneer backend nog geen endpoint heeft.
/// Vraagt context om gelokaliseerde labels op te halen.
List<Map<String, dynamic>> _defaultFeatures(BuildContext context) {
  return [
    // ── Starter features ──
    {'key': 'sessions', 'label': S.of(context).sessiebeheer, 'enabled_from': 'starter'},
    {'key': 'messages', 'label': S.of(context).messages, 'enabled_from': 'starter'},
    {'key': 'agenda', 'label': S.of(context).agenda, 'enabled_from': 'starter'},
    {'key': 'invoice', 'label': S.of(context).factuurOpstellen, 'enabled_from': 'starter'},
    {'key': 'documents', 'label': 'Documenten', 'enabled_from': 'starter'},
    {'key': 'income', 'label': 'Inkomstenoverzicht', 'enabled_from': 'starter'},
    {'key': 'checkin', 'label': 'Check-in scanner', 'enabled_from': 'starter'},
    {'key': 'noshow', 'label': 'No-show registreren', 'enabled_from': 'starter'},
    {'key': 'waitlist', 'label': 'Wachtlijst', 'enabled_from': 'starter'},
    // ── Pro features ──
    {'key': 'search_priority', 'label': 'Zoekprioriteit', 'enabled_from': 'pro'},
    {'key': 'group_sessions', 'label': S.of(context).groepslessen, 'enabled_from': 'pro'},
    {'key': 'packages', 'label': 'Pakketten', 'enabled_from': 'pro'},
    {'key': 'promo_codes', 'label': 'Promo codes', 'enabled_from': 'pro'},
    {'key': 'crm', 'label': 'CRM', 'enabled_from': 'pro'},
    {'key': 'income_dashboard', 'label': 'Inkomsten dashboard', 'enabled_from': 'pro'},
    {'key': 'marketing_tools', 'label': 'Marketing tools', 'enabled_from': 'pro'},
    {'key': 'priority_support', 'label': 'Priority support', 'enabled_from': 'pro'},
    {'key': 'dossier', 'label': S.of(context).dossierPerKlant, 'enabled_from': 'pro'},
    {'key': 'goals', 'label': S.of(context).doelenPerKlant, 'enabled_from': 'pro'},
    {'key': 'health_score', 'label': 'Client health score', 'enabled_from': 'pro'},
    {'key': 'upsell', 'label': 'Upsell suggesties', 'enabled_from': 'pro'},
    {'key': 'rebook', 'label': 'Herboek suggesties', 'enabled_from': 'pro'},
    {'key': 'bulk_message', 'label': 'Bulk bericht', 'enabled_from': 'pro'},
    {'key': 'client_tags', 'label': S.of(context).klanttagslabels, 'enabled_from': 'pro'},
    // ── Pro+ features ──
    {'key': 'branded_profile', 'label': S.of(context).brandedProfiel, 'enabled_from': 'pro_plus'},
    {'key': 'custom_url', 'label': 'Eigen URL', 'enabled_from': 'pro_plus'},
    {'key': 'profile_branding', 'label': S.of(context).profielBranding, 'enabled_from': 'pro_plus'},
    {'key': 'intro_video', 'label': 'Intro video', 'enabled_from': 'pro_plus'},
    {'key': 'verified_badge', 'label': 'Verified badge', 'enabled_from': 'pro_plus'},
    {'key': 'newsletter', 'label': S.of(context).newsletterLabel, 'enabled_from': 'pro_plus'},
    {'key': 'booking_widget', 'label': S.of(context).boekingswidget, 'enabled_from': 'pro_plus'},
    {'key': 'profile_qr', 'label': S.of(context).profielQrcode, 'enabled_from': 'pro_plus'},
    {'key': 'client_analytics', 'label': S.of(context).klantanalytics, 'enabled_from': 'pro_plus'},
    // ── Studio features (gym only) ──
    {'key': 'advanced_reporting', 'label': 'Geavanceerde rapportage', 'enabled_from': 'studio'},
    {'key': 'suite_tools', 'label': 'Suite tools', 'enabled_from': 'studio'},
    // ── Limits ──
    {'key': 'profile_videos', 'label': S.of(context).videosOpProfiel, 'enabled_from': 'pro', 'limit_pro': 1, 'limit_pro_plus': -1},
    {'key': 'profile_stories', 'label': 'Story (foto/video)', 'enabled_from': 'pro', 'limit_pro': 1, 'limit_pro_plus': -1},
    {'key': 'max_clients', 'label': S.of(context).maxActieveKlanten, 'enabled_from': 'starter', 'limit_starter': -1, 'limit_pro': -1, 'limit_pro_plus': -1},
  ];
}

/// Admin scherm om abonnement-features per tier te beheren.
/// Wijzigingen worden naar de backend gestuurd; de app haalt de config op voor gating.
class AdminSubscriptionFeaturesScreen extends StatefulWidget {
  const AdminSubscriptionFeaturesScreen({super.key});

  @override
  State<AdminSubscriptionFeaturesScreen> createState() =>
      _AdminSubscriptionFeaturesScreenState();
}

class _AdminSubscriptionFeaturesScreenState
    extends State<AdminSubscriptionFeaturesScreen> {
  List<Map<String, dynamic>> _features = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _fromApi = false;

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
      final list =
          await context.read<GymiesApi>().getAdminSubscriptionFeatures();
      if (list.isNotEmpty) {
        final parsed = list
            .where((m) => (m['key'] ?? '').toString().isNotEmpty)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (!mounted) return;
        setState(() {
          _features = parsed;
          _loading = false;
          _fromApi = true;
        });
      } else {
        throw ApiException(404, S.of(context).geenFeaturesVanBackend);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode >= 500) {
        if (!mounted) return;
        setState(() {
          _features = _defaultFeatures(context);
          _loading = false;
          _fromApi = false;
          _error = S.of(context).backendEndpointNietBeschikbaarToonDefaults;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = e.message;
          _features = _defaultFeatures(context);
          _loading = false;
          _fromApi = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _features = _defaultFeatures(context);
        _loading = false;
        _fromApi = false;
        _error = S.of(context).konFeaturesNietLadenToonDefaults;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<GymiesApi>().updateAdminSubscriptionFeatures(_features);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).featuresOpgeslagen),
          backgroundColor: Colors.green,
        ),
      );
      setState(() => _fromApi = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).opslaanMisluktMsg(e.message ?? '')),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).opslaanMisluktControleerBackend),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setEnabledFrom(int index, String tier) {
    setState(() {
      if (index >= 0 && index < _features.length) {
        _features[index]['enabled_from'] = tier;
      }
    });
  }

  void _setLimit(int index, String tierKey, int value) {
    setState(() {
      if (index >= 0 && index < _features.length) {
        _features[index][tierKey] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiConstants.darkNavyBackground,
      appBar: AppBar(
        backgroundColor: UiConstants.darkNavyBackground,
        elevation: 0,
        title: Text(
          S.of(context).abonnementFeatures,
          style: GoogleFonts.sora(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: GymiesColors.primary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GymiesColors.primary),
          onPressed: () {
            Haptics.selection();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          if (!_loading && _features.isNotEmpty)
            TextButton.icon(
              onPressed: _saving ? null : () {
                Haptics.light();
                _save();
              },
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save, color: GymiesColors.primary),
              label: Text(
                _saving ? S.of(context).opslaan3 : S.of(context).opslaan,
                style: const TextStyle(color: GymiesColors.primary),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: GymiesColors.primary))
          : Column(
              children: [
                if (_error != null && !_fromApi)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.orange.shade900,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '${S.of(context).pasAanWelkeFeaturesBijStarter} ${S.of(context).deAppToontDezeInstellingenAan}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ..._features.asMap().entries.map((entry) {
                        final i = entry.key;
                        final f = entry.value;
                        final key = (f['key'] ?? '').toString();
                        final label = (f['label'] ?? key).toString();
                        final enabledFrom =
                            (f['enabled_from'] ?? 'starter').toString();
                        final hasLimit = f.containsKey('limit_pro') ||
                            f.containsKey('limit_starter') ||
                            f.containsKey('limit_pro_plus');
                        return _FeatureRow(
                          label: label,
                          enabledFrom: enabledFrom,
                          hasLimit: hasLimit,
                          feature: f,
                          onEnabledFromChanged: (t) => _setEnabledFrom(i, t),
                          onLimitChanged: (tk, v) => _setLimit(i, tk, v),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.label,
    required this.enabledFrom,
    required this.hasLimit,
    required this.feature,
    required this.onEnabledFromChanged,
    required this.onLimitChanged,
  });

  final String label;
  final String enabledFrom;
  final bool hasLimit;
  final Map<String, dynamic> feature;
  final ValueChanged<String> onEnabledFromChanged;
  final void Function(String tierKey, int value) onLimitChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: UiConstants.darkNavyCard,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...['starter', 'pro', 'pro_plus', 'studio'].map((tier) {
                  final isSelected = enabledFrom == tier;
                  const tierLabels = {
                    'starter': 'Starter',
                    'pro': 'Pro',
                    'pro_plus': 'Pro+',
                    'studio': 'Studio',
                  };
                  return ChoiceChip(
                    label: Text(tierLabels[tier] ?? tier),
                    selected: isSelected,
                    onSelected: (_) {
                      Haptics.selection();
                      onEnabledFromChanged(tier);
                    },
                    selectedColor: GymiesColors.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? GymiesColors.darkBlue : Colors.white70,
                      fontSize: 12,
                    ),
                  );
                }),
              ],
            ),
            if (hasLimit) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  if (feature.containsKey('limit_starter'))
                    _LimitField(
                      label: 'Starter',
                      value: feature['limit_starter'] is int
                          ? feature['limit_starter'] as int
                          : 25,
                      onChanged: (v) => onLimitChanged('limit_starter', v),
                    ),
                  if (feature.containsKey('limit_pro'))
                    _LimitField(
                      label: 'Pro',
                      value: feature['limit_pro'] is int
                          ? feature['limit_pro'] as int
                          : -1,
                      onChanged: (v) => onLimitChanged('limit_pro', v),
                    ),
                  if (feature.containsKey('limit_pro_plus'))
                    _LimitField(
                      label: 'Pro+',
                      value: feature['limit_pro_plus'] is int
                          ? feature['limit_pro_plus'] as int
                          : -1,
                      onChanged: (v) => onLimitChanged('limit_pro_plus', v),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LimitField extends StatefulWidget {
  const _LimitField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_LimitField> createState() => _LimitFieldState();
}

class _LimitFieldState extends State<_LimitField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value == -1 ? '∞' : '${widget.value}',
    );
  }

  @override
  void didUpdateWidget(_LimitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value == -1 ? '∞' : '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          filled: true,
          fillColor: UiConstants.darkNavyBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        style: const TextStyle(color: Colors.white),
        keyboardType: TextInputType.number,
        onSubmitted: (s) {
          final v = int.tryParse(s);
          if (v != null) widget.onChanged(v);
        },
      ),
    );
  }
}
