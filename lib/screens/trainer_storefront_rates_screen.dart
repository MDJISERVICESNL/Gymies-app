import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/storefront_cms_provider.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Trainer Storefront Rates Screen — "Tarieven & Betaling"
/// Allows trainers to set hourly rates (in euros) and payment method.
class TrainerStorefrontRatesScreen extends StatefulWidget {
  const TrainerStorefrontRatesScreen({super.key});

  @override
  State<TrainerStorefrontRatesScreen> createState() =>
      _TrainerStorefrontRatesScreenState();
}

class _TrainerStorefrontRatesScreenState
    extends State<TrainerStorefrontRatesScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late TextEditingController _hourlyRateController;
  String _paymentMethod = 'transfer_and_cash';

  @override
  void initState() {
    super.initState();
    _hourlyRateController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _hourlyRateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cmsProvider = context.read<StorefrontCmsProvider>();
      await cmsProvider.ensureLoaded();
      if (!mounted) return;
      final cms = cmsProvider.data ?? <String, dynamic>{};

      // Load hourly rate (cents → euros)
      final rateCents = cms['hourly_rate_cents'] ?? cms['hourlyRateCents'];
      if (rateCents is int && rateCents > 0) {
        _hourlyRateController.text = (rateCents / 100).toStringAsFixed(0);
      }

      // Load payment method
      _paymentMethod = mapStr(cms, ['payment_method', 'paymentMethod']);
      if (_paymentMethod.isEmpty) {
        _paymentMethod = 'transfer_and_cash';
      }

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
        _error = S.of(context).konTarievenNietLaden;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    Haptics.light();
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final rateText = _hourlyRateController.text.trim();
    if (rateText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).vulEenTarieveIn), backgroundColor: Colors.orange),
      );
      return;
    }

    final parsed = double.tryParse(rateText);
      if (parsed == null || parsed <= 0 || parsed > 50000) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tarief moet tussen €1 en €500 liggen'), backgroundColor: Colors.orange),
        );
        return;
      }

    final api = context.read<GymiesApi>();
    setState(() => _saving = true);
    try {
      final rateCents = (parsed * 100).round();
      await api.updateTrainerStorefrontCms({
        'hourly_rate_cents': rateCents,
        'payment_method': _paymentMethod,
      });
      if (!mounted) return;
      context.read<StorefrontCmsProvider>().invalidate();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(S.of(context).tarievenOpgeslagen,
                  style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: GymiesColors.darkBlue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: S.of(context).tarievenEnBetaling),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Hourly Rate Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).uurtarief,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).stelJeUurtariefInVoorIndividueleSessies,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _hourlyRateController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: GymiesColors.primary,
                          width: 2,
                        ),
                      ),
                      prefixText: '€ ',
                      prefixStyle: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.darkBlue,
                      ),
                      hintText: '0',
                      hintStyle: GoogleFonts.sora(
                        fontSize: 16,
                        color: Colors.grey.shade400,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Payment Method Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).betaalmethode,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).kiesHoeKlantenJeKunnenBetalen,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _paymentMethodCard(
                    value: 'transfer_and_cash',
                    label: S.of(context).overboekingenCash,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: 12),
                  _paymentMethodCard(
                    value: 'transfer_only',
                    label: S.of(context).alleenOverboekingen,
                    icon: Icons.account_balance_outlined,
                  ),
                  const SizedBox(height: 12),
                  _paymentMethodCard(
                    value: 'cash_only',
                    label: S.of(context).alleenCash,
                    icon: Icons.payments_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Save Button
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
                disabledBackgroundColor: Colors.grey.shade300,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: GymiesColors.darkBlue,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.save_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          S.of(context).opslaan,
                          style: GoogleFonts.sora(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _paymentMethodCard({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _paymentMethod == value;
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        setState(() => _paymentMethod = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: isSelected ? GymiesColors.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? GymiesColors.primary : Colors.grey.shade400,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? GymiesColors.primary : GymiesColors.darkBlue,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                size: 24,
                color: GymiesColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}
