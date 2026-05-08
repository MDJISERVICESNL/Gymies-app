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

/// Trainer Storefront Logistics & Cancellation Screen — "Logistiek & Annulering"
/// Manages location, duo-training, intro offer, booking advance days, and cancellation policy.
class TrainerStorefrontLogisticsScreen extends StatefulWidget {
  const TrainerStorefrontLogisticsScreen({super.key});

  @override
  State<TrainerStorefrontLogisticsScreen> createState() =>
      _TrainerStorefrontLogisticsScreenState();
}

class _TrainerStorefrontLogisticsScreenState
    extends State<TrainerStorefrontLogisticsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // ── Logistiek ──
  bool _hasOwnLocation = false;
  bool _offersDuoTraining = false;
  bool _hasIntroOffer = false;
  final _introOfferController = TextEditingController();
  final _bookingDaysController = TextEditingController();

  // ── Annuleringsbeleid ──
  int? _cancellationHours;
  int? _cancellationRefundPercent;
  final _cancellationExceptionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _introOfferController.dispose();
    _bookingDaysController.dispose();
    _cancellationExceptionsController.dispose();
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

      // ── Logistiek ──
      _hasOwnLocation = cms['has_own_location'] == true;
      _offersDuoTraining = cms['offers_duo_training'] == true;
      _hasIntroOffer = cms['has_intro_offer'] == true;
      _introOfferController.text = mapStr(cms, ['intro_offer_description', 'introOfferDescription']);
      final bookDays = cms['booking_advance_days'] ?? cms['bookingAdvanceDays'];
      _bookingDaysController.text = bookDays != null ? bookDays.toString() : '';

      // ── Annuleringsbeleid ──
      final cH = cms['cancellation_hours'] ?? cms['cancellationHours'];
      _cancellationHours = cH is int ? cH : int.tryParse(cH?.toString() ?? '');
      final cR = cms['cancellation_refund_percent'] ?? cms['cancellationRefundPercent'];
      _cancellationRefundPercent = cR is int ? cR : int.tryParse(cR?.toString() ?? '');
      _cancellationExceptionsController.text = mapStr(cms, ['cancellation_exceptions', 'cancellationExceptions']);

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
        _error = S.of(context).konLogistiekNietLaden;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    Haptics.light();
    if (_saving) return;

    setState(() => _saving = true);
    try {
      final api = context.read<GymiesApi>();

      // Parse booking days
      int? bookingDays;
      final bookDaysText = _bookingDaysController.text.trim();
      if (bookDaysText.isNotEmpty) {
        bookingDays = int.tryParse(bookDaysText);
      }

      await api.updateTrainerStorefrontCms({
        'has_own_location': _hasOwnLocation,
        'offers_duo_training': _offersDuoTraining,
        'has_intro_offer': _hasIntroOffer,
        'intro_offer_description': _hasIntroOffer ? _introOfferController.text.trim() : null,
        'booking_advance_days': bookingDays,
        'cancellation_hours': _cancellationHours,
        'cancellation_refund_percent': _cancellationRefundPercent,
        'cancellation_exceptions': _cancellationExceptionsController.text.trim(),
      });
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      context.read<StorefrontCmsProvider>().invalidate();

      if (!mounted) return;

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(S.of(context).instellingenOpgeslagen,
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
      appBar: const GymiesAppBar(title: 'Logistiek & Annulering'),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: GymiesListBody(
            loading: _loading,
            error: _error,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
            // ══════════════════════════════════════════════════════════════
            // SECTION 1: LOGISTIEK
            // ══════════════════════════════════════════════════════════════
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
                    S.of(context).logistiek,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).stelJeTrainingslocatieTrainingsvormenEnAanbiedingenIn,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Toggle: Eigen trainingslocatie ──
                  _buildToggleRow(
                    label: 'Eigen trainingslocatie',
                    subtitle: S.of(context).jeHebtEenVastePlekVoor,
                    value: _hasOwnLocation,
                    onChanged: (val) {
                      Haptics.selection();
                      setState(() => _hasOwnLocation = val);
                    },
                  ),
                  Divider(height: 24, color: Colors.grey.shade200),

                  // ── Toggle: Duo-training ──
                  _buildToggleRow(
                    label: 'Duo-training',
                    subtitle: S.of(context).trainingVoor2PersonenTegelijk,
                    value: _offersDuoTraining,
                    onChanged: (val) {
                      Haptics.selection();
                      setState(() => _offersDuoTraining = val);
                    },
                  ),
                  Divider(height: 24, color: Colors.grey.shade200),

                  // ── Toggle: Introductiekorting ──
                  _buildToggleRow(
                    label: 'Introductiekorting',
                    subtitle: S.of(context).nieuweKlantenKrijgenKorting,
                    value: _hasIntroOffer,
                    onChanged: (val) {
                      Haptics.selection();
                      setState(() => _hasIntroOffer = val);
                    },
                  ),

                  // ── Intro Offer Description (only when enabled) ──
                  if (_hasIntroOffer) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _introOfferController,
                      maxLines: 2,
                      maxLength: 500,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: GymiesColors.primary,
                            width: 2,
                          ),
                        ),
                        hintText: S.of(context).beschrijfJeIntroductiekorting,
                        hintStyle: GoogleFonts.sora(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        isDense: true,
                      ),
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ── Booking Advance Days ──
                  TextField(
                    controller: _bookingDaysController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: GymiesColors.primary,
                          width: 2,
                        ),
                      ),
                      labelText: S.of(context).boekingstermijndagen,
                      labelStyle: GoogleFonts.sora(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      hintText: '0',
                      hintStyle: GoogleFonts.sora(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                      suffixText: 'dagen',
                      suffixStyle: GoogleFonts.sora(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      isDense: true,
                    ),
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ══════════════════════════════════════════════════════════════
            // SECTION 2: ANNULERINGSBELEID
            // ══════════════════════════════════════════════════════════════
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
                    S.of(context).annuleringsbeleid,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).bepaalOnderWelkeVoorwaardenKlantenKunnenAnnuleren,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Cancellation Hours Dropdown ──
                  DropdownButtonFormField<int?>(
                    initialValue: _cancellationHours,
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          S.of(context).nietIngesteld,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 0,
                        child: Text(
                          S.of(context).altijdAnnuleerbaar,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 12,
                        child: Text(
                          S.of(context).12UurVanTevoren,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 24,
                        child: Text(
                          S.of(context).24UurVanTevoren,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 48,
                        child: Text(
                          S.of(context).48Uur2Dagen,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 72,
                        child: Text(
                          S.of(context).72Uur3Dagen,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 168,
                        child: Text(
                          S.of(context).1WeekVanTevoren,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      Haptics.selection();
                      setState(() => _cancellationHours = value);
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: GymiesColors.primary,
                          width: 2,
                        ),
                      ),
                      labelText: S.of(context).annuleringstermijn,
                      labelStyle: GoogleFonts.sora(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Cancellation Refund Dropdown ──
                  DropdownButtonFormField<int?>(
                    initialValue: _cancellationRefundPercent,
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          S.of(context).nietIngesteld,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 100,
                        child: Text(
                          S.of(context).100VolledigeRestitutie,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 75,
                        child: Text(
                          S.of(context).75Restitutie,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 50,
                        child: Text(
                          S.of(context).50Restitutie,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 25,
                        child: Text(
                          S.of(context).25Restitutie,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem<int?>(
                        value: 0,
                        child: Text(
                          S.of(context).0GeenRestitutie,
                          style: GoogleFonts.sora(fontSize: 13),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      Haptics.selection();
                      setState(() => _cancellationRefundPercent = value);
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: GymiesColors.primary,
                          width: 2,
                        ),
                      ),
                      labelText: S.of(context).restitutiepercentage,
                      labelStyle: GoogleFonts.sora(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      isDense: true,
                    ),
                  ),

                  // ── Info Box Preview ──
                  if (_cancellationHours != null && _cancellationRefundPercent != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: GymiesColors.primary.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _buildCancellationPreview(),
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          color: GymiesColors.darkBlue,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ── Cancellation Exceptions ──
                  TextField(
                    controller: _cancellationExceptionsController,
                    maxLines: 3,
                    maxLength: 1000,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: GymiesColors.primary,
                          width: 2,
                        ),
                      ),
                      labelText: S.of(context).uitzonderingenoptioneel,
                      labelStyle: GoogleFonts.sora(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      hintText: S.of(context).beschrijfSpecialeGevallenOfUitzonderingen,
                      hintStyle: GoogleFonts.sora(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      isDense: true,
                    ),
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ══════════════════════════════════════════════════════════════
            // SAVE BUTTON
            // ══════════════════════════════════════════════════════════════
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
                          S.of(context).instellingenOpslaan,
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
        ),
      ),
    );
  }

  /// Build a toggle row for logistiek settings
  Widget _buildToggleRow({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.sora(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: GymiesColors.primary,
          inactiveThumbColor: Colors.grey.shade300,
          inactiveTrackColor: Colors.grey.shade200,
        ),
      ],
    );
  }

  /// Build cancellation policy preview text
  String _buildCancellationPreview() {
    if (_cancellationHours == null || _cancellationRefundPercent == null) {
      return '';
    }

    String hoursText;
    if (_cancellationHours == 0) {
      hoursText = 'altijd';
    } else if (_cancellationHours == 12) {
      hoursText = S.of(context).12UurVanTevoren;
    } else if (_cancellationHours == 24) {
      hoursText = S.of(context).24UurVanTevoren;
    } else if (_cancellationHours == 48) {
      hoursText = S.of(context).n48Uur2DagenVanTevoren;
    } else if (_cancellationHours == 72) {
      hoursText = S.of(context).n72Uur3DagenVanTevoren;
    } else if (_cancellationHours == 168) {
      hoursText = S.of(context).1WeekVanTevoren;
    } else {
      hoursText = '$_cancellationHours uur van tevoren';
    }

    return 'Klanten kunnen tot $hoursText annuleren en krijgen $_cancellationRefundPercent% terug.';
  }
}
