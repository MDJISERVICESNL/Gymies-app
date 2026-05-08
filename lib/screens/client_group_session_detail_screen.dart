
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../utils/haptics.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/safe_url_launcher.dart';
import '../utils/currency_format.dart';
import 'widgets/gymies_dialog.dart';
/// Detail van een groepsles + inschrijven.
class ClientGroupSessionDetailScreen extends StatefulWidget {
  const ClientGroupSessionDetailScreen({
    super.key,
    required this.groupSessionId,
  });

  final String groupSessionId;

  @override
  State<ClientGroupSessionDetailScreen> createState() =>
      _ClientGroupSessionDetailScreenState();
}

class _ClientGroupSessionDetailScreenState
    extends State<ClientGroupSessionDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _session = {};
  Map<String, dynamic>? _myRegistration;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<GymiesApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await api.getPublicGroupSession(widget.groupSessionId);
      if (!mounted) return;
      List<Map<String, dynamic>> myRegs = [];
      try {
        myRegs = await api.getMyGroupRegistrations();
      } catch (_) {
        myRegs = [];
      }
      if (!mounted) return;
      Map<String, dynamic>? myReg;
      for (final r in myRegs) {
        if (mapStr(r, ['group_session_id', 'groupSessionId']) ==
            widget.groupSessionId) {
          myReg = r;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _session = session;
        _myRegistration = myReg;
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
        _error = S.of(context).konGroepslesNietLaden;
        _loading = false;
      });
    }
  }


  /// Haal prijs per deelnemer op uit sessie-data.
  int _pricePerParticipantCents() {
    // Prioriteit: price_per_participant_cents → price_cents / max_participants → 0
    final pp = int.tryParse(
        mapStr(_session, ['price_per_participant_cents', 'pricePerParticipantCents']));
    if (pp != null && pp > 0) return pp;
    final total = int.tryParse(mapStr(_session, ['price_cents', 'priceCents'])) ?? 0;
    final max = int.tryParse(mapStr(_session, ['max_participants', 'capacity'])) ?? 1;
    if (total > 0 && max > 0) return (total / max).ceil();
    return total;
  }

  /// Crowdfund: is de sessie bevestigd (drempel bereikt)?
  bool _isSessionConfirmed() {
    final cs = mapStr(_session, ['confirmation_status']);
    return cs == 'confirmed';
  }

  /// Crowdfund: is de sessie geannuleerd?
  bool _isSessionCancelled() {
    final cs = mapStr(_session, ['confirmation_status']);
    final status = mapStr(_session, ['status']);
    return cs == 'cancelled' || status == 'cancelled';
  }

  /// Heeft mijn registratie status payment_pending (mag betalen)?
  bool _canPay() {
    if (_myRegistration == null) return false;
    return mapStr(_myRegistration, ['status']) == 'payment_pending';
  }

  Future<void> _register() async {
    if (_busy) return;

    final priceCents = _pricePerParticipantCents();
    final confirmed = _isSessionConfirmed();

    // ── Bevestigingsdialog ──
    final dialogTitle = confirmed ? S.of(context).inschrijvenBetalen : 'Plek reserveren';
    final dialogBody = confirmed
        ? 'De les gaat door! Je betaalt ${formatEuro(priceCents)} voor deze groepsles.'
        : S.of(context).jeReserveertEenPlekJeBetaalt;
    final dialogInfo = confirmed
        ? S.of(context).jeWordtDoorgestuurdNaarDeBetaalpagina2
        : S.of(context).jeOntvangtEenMeldingZodraDe;
    final buttonLabel = confirmed
        ? 'Betaal ${formatEuro(priceCents)}'
        : 'Reserveer plek';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          dialogTitle,
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: GymiesColors.darkBlue,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dialogBody, style: GoogleFonts.sora(fontSize: 14, height: 1.4)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(dialogInfo, style: GoogleFonts.sora(fontSize: 12, color: Colors.blue.shade700)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.of(context).annuleren, style: GoogleFonts.sora(color: Colors.grey.shade600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(buttonLabel, style: GoogleFonts.sora(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final api = context.read<GymiesApi>();
      final res = await api.registerForGroupSession(widget.groupSessionId);
      if (!mounted) return;

      final participantStatus = mapStr(res, ['status', 'data.status']);
      final participantId = mapStr(res, ['participant_id', 'participantId', 'id', 'data.participant_id']);

      // Crowdfund: alleen betaalflow starten als status payment_pending is
      if ((participantStatus == 'payment_pending' || confirmed) && participantId.isNotEmpty) {
        final payRes = await api.startGroupParticipantPayment(participantId);
        final url = mapStr(payRes, ['payment_url', 'checkout_url', 'url', 'redirect_url']);
        if (url.isNotEmpty && mounted) {
          await SafeUrlLauncher.launchPaymentUrl(context, url);
        }
      }

      await _load();
      if (mounted) {
        final msg = (participantStatus == 'payment_pending' || confirmed)
            ? S.of(context).inschrijvingVoltooid
            : S.of(context).plekGereserveerdJeOntvangtBerichtAls;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Betaalflow starten voor een reeds geregistreerde deelnemer (na crowdfund bevestiging).
  Future<void> _payNow() async {
    if (_busy || _myRegistration == null) return;
    final participantId = mapStr(_myRegistration, ['id', 'participant_id', 'participantId']);
    if (participantId.isEmpty) return;
    setState(() => _busy = true);
    try {
      final api = context.read<GymiesApi>();
      final payRes = await api.startGroupParticipantPayment(participantId);
      final url = mapStr(payRes, ['payment_url', 'checkout_url', 'url', 'redirect_url']);
      if (url.isNotEmpty && mounted) {
        await SafeUrlLauncher.launchPaymentUrl(context, url);
      }
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRegistration() async {
    if (_busy) return;
    final ok = await GymiesDialog.destructive(
      context,
      title: S.of(context).inschrijvingAnnuleren,
      message: S.of(context).weetJeZekerDatJeJe,
      confirmLabel: S.of(context).jaAnnuleren,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<GymiesApi>().cancelGroupSessionRegistration(
            widget.groupSessionId,
          );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(S.of(context).inschrijvingGeannuleerd),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        S.of(context).groepsles,
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.error_outline_rounded,
                              size: 36,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.sora(
                              fontSize: 15,
                              color: Colors.grey.shade800,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () {
                              Haptics.light();
                              _load();
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text(S.of(context).opnieuwProberen),
                            style: FilledButton.styleFrom(
                              backgroundColor: GymiesColors.primary,
                              foregroundColor: GymiesColors.darkBlue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _loading
                    ? _buildLoadingSkeleton()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: GymiesColors.primary,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Titel ──
                              Text(
                                mapStr(_session, ['title', 'name']).isEmpty
                                    ? S.of(context).groepsles
                                    : mapStr(_session, ['title', 'name']),
                                style: GoogleFonts.sora(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // ── Ingeschreven badge ──
                              if (_myRegistration != null)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_rounded,
                                            size: 14, color: Colors.green.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          S.of(context).ingeschreven,
                                          style: GoogleFonts.sora(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_myRegistration == null)
                                const SizedBox(height: 10),

                              // ── Info kaart ──
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    _InfoTile(
                                      icon: Icons.calendar_today_rounded,
                                      iconColor: const Color(0xFF1565C0),
                                      iconBg: const Color(0xFFE3F2FD),
                                      label: 'Datum & tijd',
                                      value: _formatDateTime(
                                        DateTime.tryParse(mapStr(_session, [
                                              'scheduled_at',
                                              'scheduledAt',
                                              'starts_at',
                                              'startsAt',
                                              'start_at',
                                            ])) ??
                                            DateTime.now(),
                                      ),
                                      showDivider: true,
                                    ),
                                    _InfoTile(
                                      icon: Icons.person_outline_rounded,
                                      iconColor: const Color(0xFF6A1B9A),
                                      iconBg: const Color(0xFFF3E5F5),
                                      label: S.of(context).trainer,
                                      value: mapStr(_session, [
                                        S.of(context).trainername,
                                        S.of(context).trainername2,
                                        'name',
                                      ]),
                                      showDivider: true,
                                    ),
                                    _InfoTile(
                                      icon: Icons.location_on_outlined,
                                      iconColor: const Color(0xFF2E7D32),
                                      iconBg: const Color(0xFFE8F5E9),
                                      label: 'Locatie',
                                      value: mapStr(
                                          _session, ['city', 'location', 'address']),
                                      showDivider: true,
                                    ),
                                    _InfoTile(
                                      icon: Icons.people_outline_rounded,
                                      iconColor: const Color(0xFFE65100),
                                      iconBg: const Color(0xFFFFF3E0),
                                      label: 'Plaatsen',
                                      value:
                                          '${mapStr(_session, ['enrolled_count', 'participants_count'])} / ${mapStr(_session, ['capacity', 'max_participants'])}',
                                      showDivider: _pricePerParticipantCents() > 0,
                                    ),
                                    if (_pricePerParticipantCents() > 0)
                                      _InfoTile(
                                        icon: Icons.euro_rounded,
                                        iconColor: const Color(0xFF2E7D32),
                                        iconBg: const Color(0xFFE8F5E9),
                                        label: 'Prijs per persoon',
                                        value: formatEuro(_pricePerParticipantCents()),
                                        showDivider: false,
                                      ),
                                  ],
                                ),
                              ),

                              // ── Crowdfund status banner ──
                              Builder(builder: (_) {
                                final cs = mapStr(_session, ['confirmation_status']);
                                final minP = int.tryParse(mapStr(_session, ['min_participants'])) ?? 1;
                                final enrolled = int.tryParse(mapStr(_session, ['enrolled_count', 'participants_count'])) ?? 0;
                                final deadlineStr = mapStr(_session, ['confirmation_deadline_at']);
                                final deadline = DateTime.tryParse(deadlineStr);
                                if (cs.isEmpty || cs == 'open' && minP <= 1) return const SizedBox.shrink();

                                Color bannerBg;
                                Color bannerFg;
                                IconData bannerIcon;
                                String bannerTitle;
                                String bannerSub;

                                if (cs == 'confirmed') {
                                  bannerBg = const Color(0xFFE8F5E9);
                                  bannerFg = const Color(0xFF2E7D32);
                                  bannerIcon = Icons.check_circle_rounded;
                                  bannerTitle = 'Deze les gaat door!';
                                  bannerSub = '$enrolled deelnemers · minimum $minP bereikt';
                                } else if (cs == 'cancelled') {
                                  bannerBg = const Color(0xFFFFEBEE);
                                  bannerFg = const Color(0xFFC62828);
                                  bannerIcon = Icons.cancel_rounded;
                                  bannerTitle = S.of(context).lesGaatNietDoor;
                                  bannerSub = 'Te weinig deelnemers ($enrolled/$minP)';
                                } else {
                                  // open — collecting
                                  bannerBg = const Color(0xFFFFF8E1);
                                  bannerFg = const Color(0xFFF57F17);
                                  bannerIcon = Icons.hourglass_top_rounded;
                                  bannerTitle = 'Nog ${ (minP - enrolled).clamp(0, minP) } deelnemer(s) nodig';
                                  bannerSub = '$enrolled / $minP ingeschreven';
                                  if (deadline != null) {
                                    final diff = deadline.difference(DateTime.now());
                                    if (diff.inDays > 0) {
                                      bannerSub += ' · nog ${diff.inDays}d ${diff.inHours % 24}u';
                                    } else if (diff.inHours > 0) {
                                      bannerSub += ' · nog ${diff.inHours}u';
                                    } else if (diff.inMinutes > 0) {
                                      bannerSub += ' · nog ${diff.inMinutes}min';
                                    }
                                  }
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: bannerBg,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(bannerIcon, size: 28, color: bannerFg),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(bannerTitle,
                                                style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: bannerFg)),
                                              const SizedBox(height: 2),
                                              Text(bannerSub,
                                                style: GoogleFonts.sora(fontSize: 12, color: bannerFg.withOpacity(0.8))),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),

                              // ── Beschrijving ──
                              if (mapStr(_session, ['description', 'bio'])
                                  .isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withOpacity(0.05),
                                        blurRadius: 12,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        S.of(context).beschrijving,
                                        style: GoogleFonts.sora(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        mapStr(
                                            _session, ['description', 'bio']),
                                        style: GoogleFonts.sora(
                                          color: Colors.grey.shade800,
                                          height: 1.5,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 28),

                              // ── CTA ──
                              if (_isSessionCancelled())
                                // Sessie geannuleerd — geen actie mogelijk
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Center(
                                    child: Text(
                                      S.of(context).dezeLesIsGeannuleerd,
                                      style: GoogleFonts.sora(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                )
                              else if (_canPay())
                                // Sessie bevestigd + mijn status is payment_pending → betaalknop
                                Column(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                            color: GymiesColors.primary.withOpacity(0.35),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: FilledButton.icon(
                                        onPressed: _busy ? null : () { Haptics.light(); _payNow(); },
                                        icon: _busy
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: GymiesColors.darkBlue))
                                            : const Icon(Icons.payment_rounded, size: 20),
                                        label: Text(
                                          'Betaal ${formatEuro(_pricePerParticipantCents())}',
                                          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: GymiesColors.primary,
                                          foregroundColor: GymiesColors.darkBlue,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: _busy ? null : () { Haptics.heavy(); _cancelRegistration(); },
                                      icon: const Icon(Icons.cancel_outlined, size: 18),
                                      label: Text(S.of(context).annuleren, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                        side: BorderSide(color: Colors.red.shade700),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                    ),
                                  ],
                                )
                              else if (_myRegistration != null)
                                // Al ingeschreven, wachtend op bevestiging → toon status + annuleerknop
                                Column(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.event_available_rounded, size: 22, color: Colors.blue.shade700),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              S.of(context).jePlekIsGereserveerdJeOntvangtEenMeldingZodraDeLesDoorgaat,
                                              style: GoogleFonts.sora(fontSize: 13, color: Colors.blue.shade700, height: 1.3),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: _busy ? null : () { Haptics.heavy(); _cancelRegistration(); },
                                      icon: _busy
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.cancel_outlined, size: 18),
                                      label: Text(S.of(context).inschrijvingAnnuleren, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                        side: BorderSide(color: Colors.red.shade700),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                // Niet ingeschreven → reserveer/inschrijf knop
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: GymiesColors.primary.withOpacity(0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: FilledButton.icon(
                                    onPressed: _busy ? null : () { Haptics.light(); _register(); },
                                    icon: _busy
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: GymiesColors.darkBlue))
                                        : const Icon(Icons.event_available_rounded, size: 20),
                                    label: Text(
                                      _isSessionConfirmed()
                                          ? 'Inschrijven · ${formatEuro(_pricePerParticipantCents())}'
                                          : 'Reserveer plek · ${formatEuro(_pricePerParticipantCents())}',
                                      style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: GymiesColors.primary,
                                      foregroundColor: GymiesColors.darkBlue,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const days = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
    const months = [
      'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
      'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
    ];
    return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} ${dt.year} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 200, height: 26),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(
                4,
                (i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 3 ? 16 : 0),
                  child: Row(
                    children: [
                      _SkeletonBox(width: 40, height: 40, radius: 10),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SkeletonBox(width: 70, height: 12),
                            const SizedBox(height: 6),
                            _SkeletonBox(width: 140, height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _SkeletonBox(width: double.infinity, height: 52, radius: 14),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SHIMMER SKELETON BOX
// ═══════════════════════════════════════════════════════════════════

class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });
  final double width;
  final double height;
  final double radius;

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
              end: Alignment(-0.4 + 2.0 * _ctrl.value, 0),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade100,
                Colors.grey.shade200,
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// INFO TILE (iOS-stijl met icon container)
// ═══════════════════════════════════════════════════════════════════

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    this.showDivider = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.sora(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      style: GoogleFonts.sora(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 70,
            color: Colors.grey.shade200,
          ),
      ],
    );
  }
}
