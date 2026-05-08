import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/gymies_theme.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../utils/haptics.dart';
import 'mollie_connect_webview_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';

/// ─── Nieuwe Trainer Onboarding (Fase C) ──────────────────────
///
/// Stappen:
///   0. Uitnodigingscode (als feature flag actief)
///   1. Bedrijfsgegevens (KvK, adres, etc.)
///   2. Documenten uploaden (KvK-uittreksel, ID, certificaat)
///   3. Plan + billing cycle kiezen (met promo banner)
///   4. Indienen voor review
///   5. Wachten op goedkeuring (status scherm)
///   6. Mandaat betaling (€0,01 SEPA)
///   7. Actief! (success scherm)
///
/// Gymies Connect is de standaard betaalroute.
class TrainerOnboardingScreen extends StatefulWidget {
  const TrainerOnboardingScreen({
    super.key,
    this.mollieConnectSuccess = false,
    this.initialStep,
    this.mandaatComplete = false,
  });

  final bool mollieConnectSuccess;
  final int? initialStep;
  final bool mandaatComplete;

  @override
  State<TrainerOnboardingScreen> createState() =>
      _TrainerOnboardingScreenState();
}

class _TrainerOnboardingScreenState extends State<TrainerOnboardingScreen> {
  int _currentStep = 0;
  bool _loading = true;
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _pricing = {};
  List<Map<String, dynamic>> _plans = [];

  // Form state
  String _invitationCode = '';
  bool _invitationCodeValid = false;
  bool _invitationCodeRequired = true;
  String _selectedPlanSlug = 'starter';
  String _billingCycle = 'monthly';
  bool _launchPromoActive = false;
  String? _onboardingStatus;

  // Document upload state
  final Map<String, bool> _uploadedDocs = {
    'kvk_extract': false,
    'id_document': false,
    'certification': false,
  };
  bool _uploading = false;

  // Business details
  final _companyNameCtrl = TextEditingController();
  final _kvkNumberCtrl = TextEditingController();
  final _vatNumberCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _kvkNumberCtrl.dispose();
    _vatNumberCtrl.dispose();
    _addressCtrl.dispose();
    _postcodeCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = context.read<GymiesApi>();
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.getOnboardingStatus(),
        api.getPlans(),
        api.getPricingPreview(plan: _selectedPlanSlug, cycle: _billingCycle),
      ]);

      final status = results[0] as Map<String, dynamic>;
      final plans = results[1] as List<Map<String, dynamic>>;
      final pricing = results[2] as Map<String, dynamic>;

      if (!mounted) return;

      _onboardingStatus = status['onboarding_status'] as String? ??
          status['current_step'] as String? ??
          'incomplete';
      _launchPromoActive = pricing['launch_promo_active'] == true;
      _invitationCodeRequired = status['invitation_code_required'] == true;

      // Pre-fill business details
      _companyNameCtrl.text = status['company_name'] as String? ?? '';
      _kvkNumberCtrl.text = status['kvk_number'] as String? ?? '';
      _vatNumberCtrl.text = status['vat_number'] as String? ?? '';
      _addressCtrl.text = status['trainer_address_line1'] as String? ?? '';
      _postcodeCtrl.text = status['trainer_postcode'] as String? ?? '';
      _cityCtrl.text = status['trainer_city'] as String? ?? '';

      // Pre-fill docs
      final docs = status['documents'] as Map<String, dynamic>? ?? {};
      for (final key in _uploadedDocs.keys) {
        _uploadedDocs[key] = _docUploaded(docs, key);
      }

      // Determine current step based on status
      final step = _determineStep(status);

      setState(() {
        _status = status;
        _plans = plans;
        _pricing = pricing;
        _currentStep = widget.initialStep ?? step;
        if (widget.mandaatComplete) _currentStep = 7;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).foutMsg(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  int _determineStep(Map<String, dynamic> status) {
    final onboardingStatus = status['onboarding_status'] as String? ?? 'incomplete';
    return switch (onboardingStatus) {
      'pending_review' => 5,
      'approved' => 6,
      'active' => 7,
      'rejected' => 4, // Terug naar indienen
      _ => 0, // incomplete: begin bij stap 0
    };
  }

  bool _docUploaded(Map<String, dynamic> docs, String key) {
    final doc = docs[key];
    if (doc == null) return false;
    if (doc is Map) return doc['uploaded'] == true || doc['verified_at'] != null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: GymiesAppBar(title: s.onboarding),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (_currentStep) {
      0 => _buildInvitationCodeStep(),
      1 => _buildBusinessDetailsStep(),
      2 => _buildDocumentsStep(),
      3 => _buildPlanSelectionStep(),
      4 => _buildSubmitStep(),
      5 => _buildWaitingForReviewStep(),
      6 => _buildMandaatStep(),
      7 => _buildActiveStep(),
      _ => _buildInvitationCodeStep(),
    };
  }

  // ─── Stap 0: Uitnodigingscode ────────────────────────────────
  Widget _buildInvitationCodeStep() {
    final s = S.of(context);
    return _stepScaffold(
      stepIndex: 0,
      title: 'Uitnodigingscode',
      subtitle: _invitationCodeRequired
          ? 'Gymies is momenteel op uitnodiging. Voer je code in om verder te gaan.'
          : 'Heb je een uitnodigingscode? Voer deze in voor extra voordelen.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              labelText: 'Uitnodigingscode',
              hintText: 'GYM-XXXXXXXX',
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: _invitationCodeValid
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) => _invitationCode = v.trim(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _validateCode,
            icon: const Icon(Icons.verified_outlined),
            label: Text(s.controleer),
          ),
          if (!_invitationCodeRequired) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _goToStep(1),
              child: Text(s.overslaan),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _validateCode() async {
    if (_invitationCode.isEmpty) return;
    try {
      final api = context.read<GymiesApi>();
      final result = await api.validateInvitationCode(_invitationCode);
      if (!mounted) return;
      if (result['valid'] == true) {
        setState(() => _invitationCodeValid = true);
        Haptics.success();
        _goToStep(1);
      } else {
        Haptics.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] as String? ?? 'Ongeldige code'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).foutMsg(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Stap 1: Bedrijfsgegevens ────────────────────────────────
  Widget _buildBusinessDetailsStep() {
    final s = S.of(context);
    return _stepScaffold(
      stepIndex: 1,
      title: s.bedrijfsgegevens,
      subtitle: 'Vul je bedrijfsgegevens in. Deze worden gecontroleerd door ons team.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _textField(_companyNameCtrl, s.bedrijfsnaam, Icons.business),
          const SizedBox(height: 12),
          _textField(_kvkNumberCtrl, s.kvkNummer, Icons.numbers, keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _textField(_vatNumberCtrl, 'BTW-nummer (optioneel)', Icons.receipt_long),
          const SizedBox(height: 12),
          _textField(_addressCtrl, s.adres, Icons.location_on),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _textField(_postcodeCtrl, s.postcode, Icons.local_post_office)),
              const SizedBox(width: 12),
              Expanded(child: _textField(_cityCtrl, s.stad, Icons.location_city)),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saveBusinessDetails,
            child: Text(s.volgende),
          ),
        ],
      ),
    );
  }

  Future<void> _saveBusinessDetails() async {
    if (_companyNameCtrl.text.isEmpty || _kvkNumberCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).vulAlleVeldenIn), backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      final api = context.read<GymiesApi>();
      await api.post('trainer/me', {
        'company_name': _companyNameCtrl.text,
        'kvk_number': _kvkNumberCtrl.text,
        'vat_number': _vatNumberCtrl.text,
        'trainer_address_line1': _addressCtrl.text,
        'trainer_postcode': _postcodeCtrl.text,
        'trainer_city': _cityCtrl.text,
      });
      if (mounted) _goToStep(2);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).foutMsg(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Stap 2: Documenten ──────────────────────────────────────
  Widget _buildDocumentsStep() {
    final s = S.of(context);
    return _stepScaffold(
      stepIndex: 2,
      title: s.documenten,
      subtitle: 'Upload je documenten ter verificatie.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _documentTile(s.kvkUittreksel, 'kvk_extract', Icons.description),
          const SizedBox(height: 8),
          _documentTile(s.idDocument, 'id_document', Icons.badge),
          const SizedBox(height: 8),
          _documentTile(s.certificering, 'certification', Icons.school),
          const SizedBox(height: 8),
          _documentTile('VOG (optioneel)', 'vog', Icons.verified_user),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _allRequiredDocsUploaded() ? () => _goToStep(3) : null,
            child: Text(s.volgende),
          ),
        ],
      ),
    );
  }

  bool _allRequiredDocsUploaded() {
    return _uploadedDocs['kvk_extract'] == true &&
        _uploadedDocs['id_document'] == true &&
        _uploadedDocs['certification'] == true;
  }

  Widget _documentTile(String label, String category, IconData icon) {
    final uploaded = _uploadedDocs[category] == true;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: uploaded ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      leading: Icon(icon, color: uploaded ? Colors.green : GymiesColors.darkBlue),
      title: Text(label),
      subtitle: Text(uploaded
          ? S.of(context).geverifieerdCheck
          : S.of(context).nogNietGeupload),
      trailing: _uploading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              icon: Icon(uploaded ? Icons.check_circle : Icons.upload_file,
                  color: uploaded ? Colors.green : GymiesColors.accent),
              onPressed: () => _uploadDocument(category),
            ),
    );
  }

  Future<void> _uploadDocument(String category) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    setState(() => _uploading = true);
    try {
      final api = context.read<GymiesApi>();
      await api.uploadOnboardingDocument(
        filePath: file.path!,
        category: category,
        fileName: file.name,
      );
      if (mounted) {
        setState(() {
          _uploadedDocs[category] = true;
          _uploading = false;
        });
        Haptics.success();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).uploadMisluktMsg(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Stap 3: Plan + Billing Cycle ────────────────────────────
  Widget _buildPlanSelectionStep() {
    final s = S.of(context);
    return _stepScaffold(
      stepIndex: 3,
      title: 'Kies je plan',
      subtitle: 'Selecteer het plan dat bij je past.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Launch promo banner
          if (_launchPromoActive)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [GymiesColors.accent, GymiesColors.accent.withOpacity(0.7)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.celebration, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Launch Actie!',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 16)),
                        Text('Eerste maand gratis — stapelbaar met jaarkorting',
                            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Billing cycle toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _cycleTab('monthly', 'Maandelijks', false),
                _cycleTab('yearly', 'Jaarlijks (-2 mnd)', true),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Plan cards
          ..._buildPlanCards(),

          const SizedBox(height: 16),
          // Price summary
          if (_pricing.isNotEmpty) _buildPriceSummary(),

          const SizedBox(height: 24),
          FilledButton(
            onPressed: _savePlan,
            child: Text(s.volgende),
          ),
        ],
      ),
    );
  }

  Widget _cycleTab(String value, String label, bool showBadge) {
    final selected = _billingCycle == value;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          setState(() => _billingCycle = value);
          await _updatePricing();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? GymiesColors.darkBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: selected ? Colors.white : Colors.grey.shade600,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  )),
              if (showBadge && selected) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: GymiesColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('BESPAAR',
                      style: GoogleFonts.poppins(
                          fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPlanCards() {
    final planData = [
      {'slug': 'starter', 'name': 'Gymies Starter', 'icon': Icons.flash_on, 'color': Colors.blue},
      {'slug': 'pro', 'name': 'Gymies Pro', 'icon': Icons.star, 'color': Colors.purple},
      {'slug': 'pro_plus', 'name': 'Gymies Pro+', 'icon': Icons.diamond, 'color': Colors.amber},
    ];

    return planData.map((plan) {
      final slug = plan['slug'] as String;
      final selected = _selectedPlanSlug == slug;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () async {
            setState(() => _selectedPlanSlug = slug);
            await _updatePricing();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? GymiesColors.darkBlue : Colors.grey.shade300,
                width: selected ? 2 : 1,
              ),
              color: selected ? GymiesColors.darkBlue.withOpacity(0.05) : null,
            ),
            child: Row(
              children: [
                Icon(plan['icon'] as IconData, color: plan['color'] as Color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(plan['name'] as String,
                      style: GoogleFonts.poppins(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 15,
                      )),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: GymiesColors.darkBlue),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildPriceSummary() {
    final pricingData = _pricing['pricing'] as Map<String, dynamic>? ?? {};
    final monthlyPrice = pricingData['monthly_price']?.toString() ?? '0';
    final effectiveMonthly = pricingData['effective_monthly']?.toString() ?? monthlyPrice;
    final savingsMonths = pricingData['savings_months'] ?? 0;
    final trialDays = _pricing['trial_days'] ?? 30;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Prijs per maand', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
              if (_billingCycle == 'yearly' && savingsMonths > 0)
                Text('€$monthlyPrice',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey)),
            ],
          ),
          Text('€$effectiveMonthly / maand',
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          if (_billingCycle == 'yearly' && savingsMonths > 0)
            Text('$savingsMonths maanden gratis bij jaarlijks!',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade700)),
          if (_launchPromoActive)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+ eerste maand gratis (launch actie)',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          Text('$trialDays dagen gratis proberen — betaling start daarna',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Future<void> _updatePricing() async {
    try {
      final api = context.read<GymiesApi>();
      final pricing = await api.getPricingPreview(plan: _selectedPlanSlug, cycle: _billingCycle);
      if (mounted) setState(() => _pricing = pricing);
    } catch (_) {}
  }

  Future<void> _savePlan() async {
    try {
      final api = context.read<GymiesApi>();
      await api.savePlanSelection(
        planSlug: _selectedPlanSlug,
        billingCycle: _billingCycle,
      );
      if (mounted) _goToStep(4);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).foutMsg(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Stap 4: Indienen voor review ────────────────────────────
  Widget _buildSubmitStep() {
    final s = S.of(context);
    final isRejected = _onboardingStatus == 'rejected';
    final rejectionReason = _status['rejection_reason'] as String?;

    return _stepScaffold(
      stepIndex: 4,
      title: isRejected ? 'Aanvraag afgewezen' : 'Klaar om in te dienen',
      subtitle: isRejected
          ? 'Je aanvraag is afgewezen. Corrigeer de problemen en dien opnieuw in.'
          : 'Controleer je gegevens en dien je aanvraag in voor review.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isRejected && rejectionReason != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(rejectionReason,
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.red.shade700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _summaryTile('Bedrijfsnaam', _companyNameCtrl.text, Icons.business),
          _summaryTile('KvK-nummer', _kvkNumberCtrl.text, Icons.numbers),
          _summaryTile('Plan', _selectedPlanSlug.replaceAll('_', ' ').toUpperCase(), Icons.star),
          _summaryTile('Facturering', _billingCycle == 'yearly' ? 'Jaarlijks' : 'Maandelijks', Icons.calendar_today),
          _summaryTile('Documenten', '${_uploadedDocs.values.where((v) => v).length}/3 geüpload', Icons.folder),
          if (_launchPromoActive)
            _summaryTile('Promo', 'Eerste maand gratis', Icons.celebration),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitForReview,
            icon: const Icon(Icons.send),
            label: Text(isRejected ? 'Opnieuw indienen' : 'Indienen voor review'),
          ),
          if (isRejected) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _goToStep(1),
              child: const Text('Gegevens aanpassen'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        leading: Icon(icon, color: GymiesColors.darkBlue, size: 20),
        title: Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
        subtitle: Text(value, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Future<void> _submitForReview() async {
    try {
      final api = context.read<GymiesApi>();
      final result = await api.submitOnboarding();
      if (!mounted) return;

      if (result['success'] == true || result['status'] == 'pending_review') {
        Haptics.success();
        _goToStep(5);
      } else {
        final missing = result['missing'] as List? ?? [];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(missing.isNotEmpty
                ? 'Ontbrekende velden: ${missing.join(', ')}'
                : result['error'] as String? ?? 'Indienen mislukt'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).foutMsg(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Stap 5: Wachten op goedkeuring ─────────────────────────
  Widget _buildWaitingForReviewStep() {
    return _stepScaffold(
      stepIndex: 5,
      title: 'Aanvraag ingediend',
      subtitle: 'Ons team bekijkt je aanvraag. Dit duurt meestal 1-2 werkdagen.',
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: GymiesColors.accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top, size: 48, color: GymiesColors.accent),
          ),
          const SizedBox(height: 24),
          Text('Even geduld...',
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'We controleren je documenten en bedrijfsgegevens. '
            'Je ontvangt een melding zodra je aanvraag is beoordeeld.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Status vernieuwen'),
          ),
        ],
      ),
    );
  }

  // ─── Stap 6: Mandaat betaling (€0,01) ───────────────────────
  Widget _buildMandaatStep() {
    return _stepScaffold(
      stepIndex: 6,
      title: 'Betaling instellen',
      subtitle: 'Eenmalige machtiging van €0,01 voor automatische incasso.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text('Hoe werkt dit?',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Je doet een eenmalige betaling van €0,01 via iDEAL. '
                  'Hiermee geven we een SEPA-machtiging af zodat we het abonnementsbedrag '
                  'automatisch kunnen incasseren na je proefperiode.',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.blue.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Je aanvraag is goedgekeurd! Rond de machtiging af om live te gaan.',
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.green.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _startMandaat,
            icon: const Icon(Icons.payment),
            label: const Text('Betaal €0,01 — Machtiging afronden'),
          ),
        ],
      ),
    );
  }

  Future<void> _startMandaat() async {
    try {
      final api = context.read<GymiesApi>();
      final result = await api.initiateMandaat();
      if (!mounted) return;

      final checkoutUrl = result['checkout_url'] as String?;
      if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
        final uri = Uri.parse(checkoutUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geen betaallink ontvangen'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).foutMsg(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Stap 7: Actief! ────────────────────────────────────────
  Widget _buildActiveStep() {
    return _stepScaffold(
      stepIndex: 7,
      title: 'Je bent live!',
      subtitle: 'Welkom bij Gymies. Je profiel is nu zichtbaar voor klanten.',
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rocket_launch, size: 48, color: Colors.green),
          ),
          const SizedBox(height: 24),
          Text('Gefeliciteerd!',
              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Je Gymies-account is volledig actief. '
            'Ga naar je dashboard om je eerste sessies in te plannen.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.dashboard),
            label: const Text('Naar Dashboard'),
          ),
        ],
      ),
    );
  }

  // ─── Shared Helpers ──────────────────────────────────────────

  void _goToStep(int step) {
    GymiesHaptics.light();
    setState(() => _currentStep = step);
  }

  Widget _textField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _stepScaffold({
    required int stepIndex,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    // Steps 5-7 zijn status screens, geen nummers tonen
    final showStepper = stepIndex <= 4;
    final totalSteps = 5; // 0-4 zijn actieve stappen

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showStepper) ...[
            // Step indicator
            Row(
              children: List.generate(totalSteps, (i) {
                final isActive = i == stepIndex;
                final isDone = i < stepIndex;
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isDone
                          ? Colors.green
                          : isActive
                              ? GymiesColors.darkBlue
                              : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text('Stap ${stepIndex + 1} van $totalSteps',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
          ],
          Text(title,
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}
