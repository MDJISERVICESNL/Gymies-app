import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/promotion.dart';
import '../theme/gymies_theme.dart';
import '../services/api_client.dart';
import '../services/promotion_service.dart';
import '../services/subscription_entitlements_service.dart';
import '../services/gymies_api.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/promo_code_field.dart';
import 'widgets/promotion_banner.dart';

enum TrainerSubscriptionTier { starter, pro, proPlus }

class TrainerSubscriptionScreen extends StatefulWidget {
  const TrainerSubscriptionScreen({super.key, this.paymentReturnTier});

  /// Na terugkeer van Mollie (gymies://subscription/complete?tier=pro).
  final String? paymentReturnTier;

  /// Label voor tier (Starter, Pro, Pro+) – bruikbaar vanaf o.a. trainer_dashboard_screen.
  static String tierDisplayLabel(String? tier) {
    final t = (tier ?? '').trim().toLowerCase();
    if (t.contains('studio')) return 'Studio';
    if (t.contains('pro_plus') || t.contains('proplus') || t.contains('pro+')) return 'Pro+';
    if (t.contains('elite')) return 'Studio'; // legacy
    if (t.contains('pro')) return 'Pro';
    return 'Starter';
  }

  @override
  State<TrainerSubscriptionScreen> createState() =>
      _TrainerSubscriptionScreenState();
}

class _TrainerSubscriptionScreenState extends State<TrainerSubscriptionScreen> {
  List<Map<String, dynamic>> _plans = [];
  AvailablePromotion? _validatedPromo;

  @override
  void initState() {
    super.initState();
    _loadPlans();
    if (widget.paymentReturnTier != null && widget.paymentReturnTier!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<SubscriptionEntitlementsService>().load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Betaling gelukt! Je ${TrainerSubscriptionScreen.tierDisplayLabel(widget.paymentReturnTier)}-abonnement is nu actief.',
              ),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      });
    }
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await context.read<GymiesApi>().getPlans();
      if (mounted) {
        setState(() => _plans = plans);
      }
    } catch (_) {
      // Fallback naar hardcoded prijzen in _fallbackPrice
    }
  }

  // ─────────────────────────────────────────────────
  //  FALLBACK WAARDEN (gebruikt als backend onbereikbaar is)
  // ─────────────────────────────────────────────────

  static const Map<TrainerSubscriptionTier, String> _tierLabel = {
    TrainerSubscriptionTier.starter: 'Starter',
    TrainerSubscriptionTier.pro: 'Pro',
    TrainerSubscriptionTier.proPlus: 'Pro+',
  };

  static const Map<TrainerSubscriptionTier, String> _fallbackSubtitle = {
    TrainerSubscriptionTier.starter: 'Basis voor starten als trainer',
    TrainerSubscriptionTier.pro: 'Meest gekozen door startende trainers',
    TrainerSubscriptionTier.proPlus: 'Voor de serieuze trainer',
  };

  static const Map<TrainerSubscriptionTier, String> _fallbackPrice = {
    TrainerSubscriptionTier.starter: '€27,99',
    TrainerSubscriptionTier.pro: '€64,99',
    TrainerSubscriptionTier.proPlus: '€79,99',
  };

  static const Map<TrainerSubscriptionTier, String?> _fallbackBadge = {
    TrainerSubscriptionTier.starter: null,
    TrainerSubscriptionTier.pro: 'MEEST GEKOZEN',
    TrainerSubscriptionTier.proPlus: 'VOOR DE SERIEUZE TRAINER',
  };

  // Fallback feature matrix — sync met backend SUBSCRIPTION_FEATURES
  static const List<_SubscriptionFeature> _fallbackFeatures = [
    // ── Starter ──
    _SubscriptionFeature('profile', 'Eigen profiel op Gymies', 'Je eigen trainerspagina', TrainerSubscriptionTier.starter),
    _SubscriptionFeature('bookings', 'Onbeperkte boekingen', 'Klanten kunnen direct boeken', TrainerSubscriptionTier.starter),
    _SubscriptionFeature('agenda', 'Basis agenda beheer', 'Beschikbaarheid en uitzonderingen', TrainerSubscriptionTier.starter),
    _SubscriptionFeature('reviews', 'Beoordelingen & reviews', 'Klanten laten reviews achter', TrainerSubscriptionTier.starter),
    _SubscriptionFeature('email_support', 'E-mail support', 'Hulp via e-mail', TrainerSubscriptionTier.starter),
    // ── Pro ──
    _SubscriptionFeature('search_priority', 'Prioriteit in zoekresultaten', 'Hoger in de lijst voor klanten', TrainerSubscriptionTier.pro),
    _SubscriptionFeature('group_sessions', 'Groepslessen beheer', 'Plan en beheer groepssessies', TrainerSubscriptionTier.pro),
    _SubscriptionFeature('packages', 'Strippenkaarten & pakketten', 'Trainingsabonnementen aanbieden', TrainerSubscriptionTier.pro),
    _SubscriptionFeature('promo_codes', 'Promo-codes aanmaken', 'Kortingscodes voor klanten', TrainerSubscriptionTier.pro),
    _SubscriptionFeature('crm', 'Klantenbestand (CRM)', 'Klantbeheer, tags en segmenten', TrainerSubscriptionTier.pro),
    _SubscriptionFeature('income_dashboard', 'Inkomsten dashboard & rapportages', 'Inzicht in je verdiensten', TrainerSubscriptionTier.pro),
    _SubscriptionFeature('marketing_tools', 'Marketing tools & templates', 'Promotie en klantwerving', TrainerSubscriptionTier.pro),
    _SubscriptionFeature('priority_support', 'Prioriteit support', 'Snellere reactie van ons team', TrainerSubscriptionTier.pro),
    // ── Pro+ ──
    _SubscriptionFeature('branded_profile', 'Eigen branded profielpagina', 'Volledig gepersonaliseerd profiel', TrainerSubscriptionTier.proPlus),
    _SubscriptionFeature('custom_url', 'Eigen URL (gymies.nl/jouw-naam)', 'Deel je persoonlijke link', TrainerSubscriptionTier.proPlus),
    _SubscriptionFeature('profile_branding', 'Logo & kleur op je profiel', 'Je huisstijl op Gymies', TrainerSubscriptionTier.proPlus),
    _SubscriptionFeature('intro_video', 'Intro-video op je profiel', 'Laat zien wie je bent', TrainerSubscriptionTier.proPlus),
    _SubscriptionFeature('verified_badge', 'Verified trainer badge', 'Blauw vinkje op je profiel', TrainerSubscriptionTier.proPlus),
    _SubscriptionFeature('newsletter', 'Nieuwsbrief naar klanten sturen', 'Direct contact met je klanten', TrainerSubscriptionTier.proPlus),
    _SubscriptionFeature('booking_widget', 'Boekingswidget voor je website', 'Boekingen via je eigen site', TrainerSubscriptionTier.proPlus),
    _SubscriptionFeature('profile_qr', 'QR-code voor je profiel', 'Deel je profiel offline', TrainerSubscriptionTier.proPlus),
    _SubscriptionFeature('client_analytics', 'Klant analytics', 'Actief / risico / inactief inzichten', TrainerSubscriptionTier.proPlus),
  ];

  // ─────────────────────────────────────────────────
  //  HELPER: zoek plan-data in API response
  // ─────────────────────────────────────────────────

  /// Zoek het plan-object in _plans voor een tier.
  Map<String, dynamic>? _planDataFor(TrainerSubscriptionTier tier) {
    final slug = tier == TrainerSubscriptionTier.proPlus ? 'pro_plus' : tier.name;
    for (final p in _plans) {
      final s = (p['slug'] ?? p['plan_slug'] ?? '').toString().toLowerCase();
      if (s == slug) return p;
    }
    return null;
  }

  /// Lees een string-veld uit plan-data, met meerdere key-opties.
  String _planString(Map<String, dynamic>? plan, List<String> keys) {
    if (plan == null) return '';
    for (final k in keys) {
      final v = plan[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '';
  }

  // ─────────────────────────────────────────────────
  //  DYNAMISCHE GETTERS — backend → fallback
  // ─────────────────────────────────────────────────

  /// Prijs: backend (price_label / amount_cents) → fallback.
  String _priceForTier(TrainerSubscriptionTier tier) {
    final plan = _planDataFor(tier);
    if (plan != null) {
      final label = _planString(plan, ['price_label', 'price']);
      if (label.isNotEmpty) return label.replaceAll(RegExp(r'/mnd$'), '').trim();
      final cents = plan['amount_cents'] ?? plan['amount'];
      if (cents != null) {
        final euro = (cents is int ? cents : int.tryParse(cents.toString()) ?? 0) / 100;
        return '€${euro.toStringAsFixed(2).replaceAll('.', ',')}';
      }
    }
    return _fallbackPrice[tier] ?? '';
  }

  /// Originele prijs (voor doorstreping bij actie): alleen uit backend.
  /// Retourneert null als er geen actieprijs loopt.
  String? _originalPriceForTier(TrainerSubscriptionTier tier) {
    final plan = _planDataFor(tier);
    final v = _planString(plan, ['original_price', 'price_before']);
    return v.isNotEmpty ? v : null;
  }

  /// Subtitel: backend → fallback.
  String _subtitleForTier(TrainerSubscriptionTier tier) {
    final plan = _planDataFor(tier);
    final v = _planString(plan, ['subtitle', 'description', 'plan_subtitle']);
    return v.isNotEmpty ? v : (_fallbackSubtitle[tier] ?? '');
  }

  /// Badge label (bijv. "MEEST GEKOZEN"): backend → fallback.
  String? _badgeForTier(TrainerSubscriptionTier tier) {
    final plan = _planDataFor(tier);
    final v = _planString(plan, ['badge_label', 'badge', 'plan_badge']);
    if (v.isNotEmpty) return v;
    return _fallbackBadge[tier];
  }

  /// Promo-tekst: backend → leeg (geen fallback = geen valse beloftes).
  String _promoForTier(TrainerSubscriptionTier tier) {
    final plan = _planDataFor(tier);
    return _planString(plan, ['promo_label', 'promo']);
  }

  /// Feature-lijst: backend → fallback.
  /// Backend kan per plan een array features meesturen:
  /// [{"label": "Eigen profiel", "description": "Je trainerspagina"}]
  List<_SubscriptionFeature> _featuresForTier(TrainerSubscriptionTier tier) {
    final plan = _planDataFor(tier);
    if (plan != null) {
      final raw = plan['features'] ?? plan['feature_list'];
      if (raw is List && raw.isNotEmpty) {
        final parsed = <_SubscriptionFeature>[];
        for (final f in raw) {
          if (f is Map<String, dynamic>) {
            final label = (f['label'] ?? f['title'] ?? '').toString().trim();
            final desc = (f['description'] ?? f['subtitle'] ?? '').toString().trim();
            final key = (f['key'] ?? label).toString();
            if (label.isNotEmpty) {
              parsed.add(_SubscriptionFeature(key, label, desc, tier));
            }
          }
        }
        if (parsed.isNotEmpty) return parsed;
      }
    }
    return []; // caller combineert alle tiers
  }

  /// Alle features: probeert per tier uit backend, valt terug op _fallbackFeatures.
  List<_SubscriptionFeature> get _features {
    // Check of ENIGE tier features uit de API heeft
    bool hasApiFeatures = false;
    for (final tier in TrainerSubscriptionTier.values) {
      if (_featuresForTier(tier).isNotEmpty) {
        hasApiFeatures = true;
        break;
      }
    }
    if (!hasApiFeatures) return _fallbackFeatures;

    // Bouw volledige lijst uit API features per tier
    final all = <_SubscriptionFeature>[];
    for (final tier in TrainerSubscriptionTier.values) {
      final apiFeatures = _featuresForTier(tier);
      if (apiFeatures.isNotEmpty) {
        all.addAll(apiFeatures);
      } else {
        // Deze tier heeft geen API features — gebruik fallback voor deze tier
        all.addAll(_fallbackFeatures.where((f) => f.enabledFrom == tier));
      }
    }
    return all;
  }

  static bool _featureEnabledFor(TrainerSubscriptionTier tier, _SubscriptionFeature f) {
    return tier.index >= f.enabledFrom.index;
  }

  int enabledFeatureCount(TrainerSubscriptionTier tier) {
    return _features.where((f) => _featureEnabledFor(tier, f)).length;
  }

  static TrainerSubscriptionTier _tierFromString(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    if (t.contains('pro_plus') || t.contains('proplus') || t.contains('pro+')) return TrainerSubscriptionTier.proPlus;
    if (t.contains('pro')) return TrainerSubscriptionTier.pro;
    return TrainerSubscriptionTier.starter;
  }

  static String _tierDisplayLabel(String? s) => _tierLabel[_tierFromString(s)] ?? 'Starter';

  /// Volgende factuurdatum = 1e van volgende maand
  static DateTime _nextInvoiceDate() {
    final now = DateTime.now();
    final nextMonth = now.month == 12 ? 1 : now.month + 1;
    final nextYear = now.month == 12 ? now.year + 1 : now.year;
    return DateTime(nextYear, nextMonth, 1);
  }

  static String _formatDate(DateTime d) {
    const months = [
      'januari', 'februari', 'maart', 'april', 'mei', 'juni',
      'juli', 'augustus', 'september', 'oktober', 'november', 'december',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// Format next billing date: gebruikt API (YYYY-MM-DD) als beschikbaar, anders fallback 1e v.d. maand.
  static String _nextBillingDateString(String? apiDate) {
    if (apiDate != null && apiDate.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(apiDate.trim());
      if (parsed != null) return _formatDate(parsed);
    }
    return _formatDate(_nextInvoiceDate());
  }

  void _showTierSheet(
    BuildContext context,
    TrainerSubscriptionTier tier,
    TrainerSubscriptionTier currentTier,
    GymiesApi api,
    SubscriptionEntitlementsService entitlements,
  ) {
    final sheetChanging = ValueNotifier<bool>(false);
    final price = _priceForTier(tier);
    final originalPrice = _originalPriceForTier(tier);
    final label = _tierLabel[tier] ?? '';
    final tierFeatures = _features.where((f) => _featureEnabledFor(tier, f)).toList();
    final dateStr = _nextBillingDateString(entitlements.nextBillingDate);
    final isUpgrade = tier.index > currentTier.index;
    final isDowngrade = tier.index < currentTier.index;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          color: GymiesColors.primary,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gymies $label',
                                style: GoogleFonts.fjallaOne(
                                  fontSize: 22,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              Text(
                                _subtitleForTier(tier),
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (originalPrice != null)
                              Text(
                                '$originalPrice/mnd',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.grey.shade500,
                                ),
                              ),
                            Text(
                              '$price/mnd',
                              style: GoogleFonts.fjallaOne(
                                fontSize: 20,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Wat je krijgt met $label',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 16,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...tierFeatures.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle, color: GymiesColors.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: GymiesColors.darkBlue,
                                    ),
                                  ),
                                  if (f.description.isNotEmpty)
                                    Text(
                                      f.description,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: GymiesColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isUpgrade
                                ? 'Betaling starten voor $label'
                                : isDowngrade
                                    ? 'Weet je zeker dat je wilt downgraden?'
                                    : 'Weet je zeker dat je van abonnement wilt veranderen?',
                            style: GoogleFonts.fjallaOne(
                              fontSize: 16,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isUpgrade
                                ? 'Je wordt doorgestuurd naar de betaalpagina. Na betaling is je $label-abonnement direct actief.'
                                : 'Bij je volgende factuurdatum ($dateStr) wordt je abonnement gewijzigd naar $label. Je betaalt dan $price per maand.',
                            style: TextStyle(
                              fontSize: 14,
                              color: GymiesColors.darkBlue.withValues(alpha: 0.9),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ValueListenableBuilder<bool>(
                      valueListenable: sheetChanging,
                      builder: (context, isChanging, child) => Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isChanging ? null : () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: GymiesColors.darkBlue,
                                side: BorderSide(color: GymiesColors.darkBlue),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Annuleren'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: isChanging
                                  ? null
                                  : () => isUpgrade
                                      ? _startPayment(ctx, tier, api, entitlements, sheetChanging)
                                      : _confirmChange(ctx, tier, api, entitlements, sheetChanging),
                              style: FilledButton.styleFrom(
                                backgroundColor: GymiesColors.primary,
                                foregroundColor: GymiesColors.darkBlue,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: isChanging
                                  ? SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: GymiesColors.darkBlue,
                                      ),
                                    )
                                  : Text(isUpgrade ? 'Doorgaan naar betaling' : 'Ja, wijzig abonnement'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startPayment(
    BuildContext ctx,
    TrainerSubscriptionTier tier,
    GymiesApi api,
    SubscriptionEntitlementsService entitlements,
    ValueNotifier<bool> sheetChanging,
  ) async {
    final tierStr = tier == TrainerSubscriptionTier.proPlus ? 'pro_plus' : tier.name;
    final messenger = ScaffoldMessenger.of(context);
    sheetChanging.value = true;
    try {
      final data = await api.startSubscriptionPaymentWithPromo(
        tierStr,
        promotionId: _validatedPromo?.promotionId,
        promoCode: _validatedPromo?.promotionSlug,
      );
      final url = (data['payment_url'] ?? data['url'] ?? '').toString();
      if (url.isEmpty) {
        if (ctx.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Geen betaal-URL ontvangen. Probeer opnieuw.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      if (!ctx.mounted) return;
      Navigator.pop(ctx);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Je wordt doorgestuurd naar de betaalpagina. Na betaling keer je terug naar de app.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          await entitlements.load();
        }
      }
    } catch (e) {
      if (ctx.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Betaling starten mislukt: ${e is ApiException ? e.message : e}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      sheetChanging.value = false;
    }
  }

  Future<void> _confirmChange(
    BuildContext ctx,
    TrainerSubscriptionTier tier,
    GymiesApi api,
    SubscriptionEntitlementsService entitlements,
    ValueNotifier<bool> sheetChanging,
  ) async {
    final tierStr = tier == TrainerSubscriptionTier.proPlus ? 'pro_plus' : tier.name;
    final messenger = ScaffoldMessenger.of(context);
    sheetChanging.value = true;
    try {
      await api.changeSubscription(tierStr);
      if (!ctx.mounted) return;
      await entitlements.load();
      if (!ctx.mounted) return;
      Navigator.pop(ctx);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Je abonnement wijzigt naar ${_tierLabel[tier]} bij je volgende factuurdatum.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (ctx.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Kon abonnement niet wijzigen: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      sheetChanging.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<GymiesApi>();
    final promoService = context.watch<PromotionService>();
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Abonnement'),
      body: Consumer<SubscriptionEntitlementsService>(
        builder: (context, entitlements, _) {
          final currentTier = _tierFromString(entitlements.tier);
          final tierLabel = _tierDisplayLabel(entitlements.tier);
          final enabledCount = enabledFeatureCount(currentTier);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Promotie/trial banner (als actief)
              PromotionBanner(
                promotionService: promoService,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Je profiteert al van deze actie!'),
                      backgroundColor: GymiesColors.darkBlue,
                    ),
                  );
                },
              ),
              Card(
                color: GymiesColors.darkBlue,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Actief plan: $tierLabel',
                        style: GoogleFonts.fjallaOne(
                          color: GymiesColors.primary,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$enabledCount van ${_features.length} features actief.',
                        style: TextStyle(
                          color: GymiesColors.primary.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: GymiesColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: GymiesColors.darkBlue,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Als je een abonnement wilt wijzigen, bekijk de features en verander je abonnement. Je abonnement gaat in bij de volgende factuurdatum.',
                        style: TextStyle(
                          fontSize: 14,
                          color: GymiesColors.darkBlue.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Kies een plan',
                style: GoogleFonts.fjallaOne(
                  fontSize: 18,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 8),
              ...TrainerSubscriptionTier.values.map((tier) {
                final active = tier == currentTier;
                final badge = _badgeForTier(tier);
                final promo = _promoForTier(tier);
                final originalPrice = _originalPriceForTier(tier);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: GymiesColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                        ),
                      ),
                    Card(
                      child: InkWell(
                        onTap: active
                            ? null
                            : () => _showTierSheet(
                                  context,
                                  tier,
                                  currentTier,
                                  api,
                                  entitlements,
                                ),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(
                                active ? Icons.verified_rounded : Icons.workspace_premium_outlined,
                                color: active ? Colors.green.shade700 : GymiesColors.darkBlue,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _tierLabel[tier] ?? 'Plan',
                                      style: GoogleFonts.fjallaOne(
                                        fontSize: 18,
                                        color: GymiesColors.darkBlue,
                                      ),
                                    ),
                                    Text(
                                      _subtitleForTier(tier),
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          '${_priceForTier(tier)}/mnd',
                                          style: TextStyle(
                                            color: GymiesColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (originalPrice != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '$originalPrice/mnd',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 13,
                                              decoration: TextDecoration.lineThrough,
                                              decorationColor: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (promo.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        promo,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (active)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Actief',
                                    style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                Icon(Icons.chevron_right, color: GymiesColors.darkBlue),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 20),
              // ── Promo-code invoerveld ──
              Text(
                'Heb je een kortingscode?',
                style: GoogleFonts.fjallaOne(
                  fontSize: 15,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 8),
              PromoCodeField(
                promotionService: promoService,
                tier: currentTier == TrainerSubscriptionTier.proPlus
                    ? 'pro_plus'
                    : currentTier.name,
                onPromoValidated: (promo) {
                  setState(() => _validatedPromo = promo);
                },
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _SubscriptionFeature {
  const _SubscriptionFeature(
    this.key,
    this.label,
    this.description,
    this.enabledFrom,
  );

  final String key;
  final String label;
  final String description;
  final TrainerSubscriptionTier enabledFrom;
}
