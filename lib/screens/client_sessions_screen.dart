

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/booking.dart';
import '../services/api_client.dart';
import '../services/calendar_service.dart';
import '../services/deep_link_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../services/in_app_review_service.dart';
import '../utils/safe_url_launcher.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import '../utils/currency_format.dart';
import 'client_check_in_qr_screen.dart';
import 'client_dispute_detail_screen.dart';
import 'client_group_session_detail_screen.dart';
import 'client_support_screen.dart';
import 'shells/client_shell.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/review_bottom_sheet.dart';
import 'widgets/safe_session_overlay.dart';
import 'widgets/reschedule_slot_picker.dart';
import 'widgets/trainer_state_views.dart';
class ClientSessionsScreen extends StatefulWidget {
  const ClientSessionsScreen({super.key, this.paymentReturnBookingId});

  /// Wanneer de app opent via gymies://payment/complete?booking_id=X
  /// wordt dit gezet om de lijst te verversen en success te tonen.
  final String? paymentReturnBookingId;

  @override
  State<ClientSessionsScreen> createState() => _ClientSessionsScreenState();
}

class _ClientSessionsScreenState extends State<ClientSessionsScreen> {
  bool _loading = true;
  String? _error;
  List<Booking> _bookings = [];
  List<Map<String, dynamic>> _invoices = [];
  final Set<String> _busyBookingIds = {};
  int _activeTab = 0; // 0=Komend, 1=Geweest, 2=Groep, 3=Wacht
  List<Map<String, dynamic>> _groupRegistrations = [];
  List<Map<String, dynamic>> _waitlistEntries = [];

  // Cached API reference — set once in didChangeDependencies to avoid
  // accessing context.read after async gaps (prevents _dependents.isEmpty).
  late GymiesApi _api;
  bool _didFirstLoad = false;

  @override
  void initState() {
    super.initState();
    if (widget.paymentReturnBookingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pollPaymentStatus(widget.paymentReturnBookingId!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<GymiesApi>();
    if (!_didFirstLoad) {
      _didFirstLoad = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _api;
      final list = await api.getBookings();
      List<Map<String, dynamic>> invoices = [];
      try {
        invoices = await api.getClientInvoices();
      } catch (e) {
        if (kDebugMode) debugPrint('[ClientSessions] Facturen laden mislukt: $e');
        invoices = [];
      }
      // Groepslessen en wachtlijst parallel laden (non-blocking)
      List<Map<String, dynamic>> groupRegs = [];
      List<Map<String, dynamic>> waitlist = [];
      try {
        groupRegs = await api.getMyGroupRegistrations();
      } catch (e) {
        // Fail-open: Group registrations optional
        if (kDebugMode) debugPrint('[ClientSessions] Fetch group registrations failed: $e');
      }
      try {
        waitlist = await api.getMyWaitlistEntries();
      } catch (e) {
        // Fail-open: Waitlist optional
        if (kDebugMode) debugPrint('[ClientSessions] Fetch waitlist failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _bookings = list;
        _invoices = invoices;
        _groupRegistrations = groupRegs;
        _waitlistEntries = waitlist;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[ClientSessions] Sessies laden fout: $e');
      if (!mounted) return;
      setState(() {
        _error = S.of(context).couldNotLoadSessions;
        _loading = false;
      });
    }
  }

  /// Poll betaalstatus na terugkeer van Mollie.
  /// Webhook kan vertraagd zijn — poll max 30s met exponential backoff.
  Future<void> _pollPaymentStatus(String bookingId) async {
    if (!mounted) return;
    const maxAttempts = 6;
    const delays = [
      Duration(milliseconds: 500),   // poging 1: direct
      Duration(seconds: 2),           // poging 2: na 2s
      Duration(seconds: 4),           // poging 3: na 4s
      Duration(seconds: 6),           // poging 4: na 6s
      Duration(seconds: 8),           // poging 5: na 8s
      Duration(seconds: 10),          // poging 6: na 10s (totaal ~30s)
    ];

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted) return;
      if (attempt < delays.length) {
        await Future.delayed(delays[attempt]);
      }
      if (!mounted) return;

      try {
        final api = _api;
        final status = await api.getBookingPaymentStatus(bookingId);
        if (!mounted) return;
        final paymentStatus = (status['status'] ?? status['payment_status'] ?? '')
            .toString()
            .toLowerCase();

        if (paymentStatus == 'paid' || paymentStatus == 'confirmed') {
          // Haal booking details op voor het bevestigingsscherm
          Map<String, dynamic> bookingDetails = status;
          try {
            final bookings = await api.getBookings();
            Booking? match;
            for (final b in bookings) {
              if (b.id.toString() == bookingId) {
                match = b;
                break;
              }
            }
            if (match != null) {
              bookingDetails = {
                ...status,
                S.of(context).trainername: match.trainerName,
                'scheduled_at': match.scheduledAt.toIso8601String(),
                'duration_minutes': match.durationMinutes,
                'amount_cents': match.amountCents ?? 0,
              };
            }
          } catch (e) {
            // Fail-open: Booking details fetch optional, show minimal overlay
            if (kDebugMode) debugPrint('[ClientSessions] Fetch booking details failed: $e');
          }
          if (!mounted) return;
          _showPaymentSuccessOverlay(bookingId, bookingDetails);
          InAppReviewService.instance.trackPositiveAction();
          _load();
          return;
        } else if (paymentStatus == 'failed' || paymentStatus == 'cancelled' || paymentStatus == 'expired') {
          _showError(S.of(context).paymentFailedRetry);
          _load();
          return;
        }
        // Status is nog 'pending' — ga door met pollen
      } catch (_) {
        // API niet bereikbaar — probeer opnieuw
      }
    }

    // Na alle pogingen nog steeds pending — geef neutrale melding
    if (mounted) {
      _showSuccess(S.of(context).betalingWordtVerwerktDeStatusWordt);
      _load();
    }
  }

  void _showPaymentSuccessOverlay(String bookingId, Map<String, dynamic> status) {
    if (!mounted) return;
    Haptics.success();

    final trainerName = (status[S.of(context).trainername] ?? status[S.of(context).trainer2] ?? '').toString();
    final scheduledAt = (status['scheduled_at'] ?? status['date'] ?? '').toString();
    final amountCents = int.tryParse((status['amount_cents'] ?? '0').toString()) ?? 0;
    final amountEur = formatEuro(amountCents, fallback: '');
    final durationMin = int.tryParse((status['duration_minutes'] ?? '0').toString()) ?? 0;

    // Datum en tijd formatteren
    String dateTimeStr = '';
    if (scheduledAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(scheduledAt);
        const days = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
        const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
        final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        final endTime = durationMin > 0
            ? '${dt.add(Duration(minutes: durationMin)).hour.toString().padLeft(2, '0')}:${dt.add(Duration(minutes: durationMin)).minute.toString().padLeft(2, '0')}'
            : '';
        dateTimeStr = '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} · $time${endTime.isNotEmpty ? ' – $endTime' : ''}';
      } catch (_) {
        dateTimeStr = scheduledAt;
      }
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (context, anim, _, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
      pageBuilder: (context, _, _) {
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated checkmark
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF27AE60).withOpacity(0.12),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          size: 56,
                          color: Color(0xFF27AE60),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  S.of(context).betalingGelukt,
                  style: GoogleFonts.sora(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.of(context).jeSessieIsBevestigd,
                  style: GoogleFonts.sora(
                    fontSize: 15,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (trainerName.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.person_rounded, size: 18, color: GymiesColors.darkBlue.withOpacity(0.6)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                trainerName,
                                style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (dateTimeStr.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 18, color: GymiesColors.darkBlue.withOpacity(0.6)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dateTimeStr,
                                style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w500, color: GymiesColors.darkBlue),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (amountEur.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.payment_rounded, size: 18, color: GymiesColors.darkBlue.withOpacity(0.6)),
                            const SizedBox(width: 8),
                            Text(
                              amountEur,
                              style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      S.of(context).bekijkMijnSessies,
                      style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    Haptics.error(); // Tactiele foutmelding: tap-tap-tap
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    Haptics.success(); // Tactiele bevestiging: ta-tap
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  bool _isSentInvoice(Map<String, dynamic> invoice) {
    final sentAt = mapStr(invoice, ['sent_at', 'sentAt', 'delivered_at']);
    final isSentRaw = invoice['is_sent'] ?? invoice['sent'];
    final isSent =
        isSentRaw == true ||
        isSentRaw == 1 ||
        isSentRaw?.toString().toLowerCase() == 'true';
    final link = _invoiceLink(invoice);
    return isSent || sentAt.isNotEmpty || link.isNotEmpty;
  }

  String _invoiceLink(Map<String, dynamic> invoice) {
    return mapStr(invoice, [
      'download_url',
      'pdf_url',
      'pdf_public_url',
      'pdf_download_url',
      'invoice_pdf_url',
      'invoice_url',
      'url',
    ]);
  }

  Map<String, dynamic>? _sentInvoiceForBooking(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return null;
    for (final invoice in _invoices) {
      final invoiceBookingId = mapStr(invoice, [
        'booking_id',
        'bookingId',
      ]).trim();
      if (invoiceBookingId == id && _isSentInvoice(invoice)) {
        return invoice;
      }
    }
    return null;
  }

  Future<void> _openInvoiceForBooking(Booking booking) async {
    final invoice = _sentInvoiceForBooking(booking.id);
    if (invoice == null) {
      _showError(S.of(context).factuurNogNietBeschikbaar);
      return;
    }
    final link = _invoiceLink(invoice);
    if (link.isEmpty) {
      _showError(S.of(context).factuurlinkOntbreekt);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showError(S.of(context).factuurlinkIsOngeldig);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(S.of(context).downloadDePdfDirectNaOpenen),
        backgroundColor: GymiesColors.darkBlue,
      ),
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showError(S.of(context).konFactuurNietOpenen);
    }
  }

  Future<void> _runBookingAction(
    Booking booking,
    Future<void> Function() action,
  ) async {
    if (booking.id.isEmpty) {
      _showError(S.of(context).boekingidOntbreektVernieuwDeLijstEn);
      return;
    }
    if (_busyBookingIds.contains(booking.id)) return;
    setState(() => _busyBookingIds.add(booking.id));
    try {
      await action();
      if (mounted) await _load();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('[ClientSessions] Booking actie fout: $e');
      _showError(S.of(context).actieMisluktProbeerOpnieuw);
    } finally {
      if (mounted) {
        setState(() => _busyBookingIds.remove(booking.id));
      }
    }
  }

  Future<void> _showCancellationPreview(Booking booking) async {
    if (booking.id.isEmpty) {
      _showError(S.of(context).boekingidOntbreekt);
      return;
    }
    try {
      final data = await context
          .read<GymiesApi>()
          .getBookingCancellationPreview(booking.id);
      if (!mounted) return;
      final fee = data['fee_cents'] ?? data['cancellation_fee_cents'] ?? '-';
      final refundable =
          data['refundable_cents'] ?? data['refund_cents'] ?? '-';
      await GymiesDialog.info(
        context,
        title: S.of(context).annuleringsoverzicht,
        message: 'Kosten: $fee cents\nTerugbetaling: $refundable cents',
        icon: Icons.report_gmailerrorred_outlined,
        buttonLabel: 'Sluiten',
      );
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _raiseDispute(Booking booking) async {
    final reasonCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool submitting = false;

    // ignore: unused_local_variable
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.gavel_rounded, color: Colors.deepOrange.shade700, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            S.of(context).geschilIndienen,
                            style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          icon: Icon(Icons.close_rounded, size: 22, color: Colors.grey.shade400),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              S.of(context).beschrijfHetProbleemZoDuidelijkMogelijkWeNemenHetZoSnelMogelijkInBehandeling,
                              style: GoogleFonts.sora(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: reasonCtrl,
                      decoration: InputDecoration(
                        labelText: S.of(context).reden,
                        hintText: S.of(context).bijvNoshowKwaliteitsprobleem,
                        prefixIcon: const Icon(Icons.report_problem_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? S.of(context).fillInReason : null,
                      maxLength: 255,
                      style: GoogleFonts.sora(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: detailsCtrl,
                      decoration: InputDecoration(
                        labelText: S.of(context).toelichtingoptioneel,
                        hintText: S.of(context).beschrijfDeSituatieInDetail,
                        prefixIcon: const Icon(Icons.description_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      maxLength: 2000,
                      style: GoogleFonts.sora(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: submitting
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ?? false)) return;
                                setDlg(() => submitting = true);
                                try {
                                  final api = _api;
                                  final res = await api.raiseDispute(
                                    bookingId: booking.id,
                                    reason: reasonCtrl.text.trim(),
                                    details: detailsCtrl.text.trim().isNotEmpty ? detailsCtrl.text.trim() : null,
                                  );
                                  if (!ctx.mounted) return;
                                  Navigator.of(ctx).pop(true);
                                  Haptics.success();
                                  // Navigeer naar detail
                                  final disputeId = res['data']?['id']?.toString() ?? res['id']?.toString();
                                  if (disputeId != null && disputeId.isNotEmpty && context.mounted) {
                                    // ignore: use_build_context_synchronously
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ClientDisputeDetailScreen(disputeId: disputeId),
                                      ),
                                    );
                                  }
                                } on ApiException catch (e) {
                                  setDlg(() => submitting = false);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
                                  );
                                } catch (_) {
                                  setDlg(() => submitting = false);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: const Text(S.of(context).konGeschilNietIndienen), backgroundColor: Colors.red.shade600),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepOrange.shade600,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.deepOrange.shade200,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          submitting ? S.of(context).bezig2 : S.of(context).geschilIndienen,
                          style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    reasonCtrl.dispose();
    detailsCtrl.dispose();
  }

  Future<void> _cancelBooking(Booking booking) async {
    // Haal annuleringsbeleid op voordat we de dialoog tonen
    Map<String, dynamic>? preview;
    try {
      preview = await _api.getBookingCancellationPreview(booking.id);
    } catch (_) {
      // Fallback: toon simpele bevestiging als preview niet beschikbaar is
    }

    if (!mounted) return;

    final policyMsg = (preview?['cancellation_policy_message'] ?? '').toString();
    final penaltyApplies = preview?['penalty_applies'] == true;
    final refundPercent = (preview?['refund_percent'] ?? 0);

    final ok = await GymiesDialog.custom<bool>(
      context,
      title: S.of(context).cancelSession,
      icon: Icons.cancel_outlined,
      iconColor: Colors.red.shade600,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (policyMsg.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: penaltyApplies
                    ? Colors.orange.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: penaltyApplies
                      ? Colors.orange.shade200
                      : Colors.green.shade200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    penaltyApplies
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: penaltyApplies
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      policyMsg,
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        color: penaltyApplies
                            ? Colors.orange.shade900
                            : Colors.green.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (refundPercent is num && refundPercent > 0)
            Text(
              'Terugbetaling: $refundPercent%',
              style: GoogleFonts.sora(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          if (refundPercent is num && refundPercent > 0)
            const SizedBox(height: 8),
          const Text(S.of(context).weetJeZekerDatJeDezeSessieWiltAnnuleren),
        ],
      ),
      actions: [
        GymiesDialogAction(
          label: 'Nee, behouden',
          returnValue: false,
        ),
        GymiesDialogAction(
          label: S.of(context).jaAnnuleren,
          isPrimary: true,
          isDestructive: true,
          returnValue: true,
        ),
      ],
    );
    if (ok != true) return;
    await _runBookingAction(booking, () async {
      await _api.cancelBooking(
        bookingId: booking.id,
        reason: 'client_cancelled',
      );
      _showSuccess(S.of(context).sessionCancelled);
    });
  }

  Future<void> _rescheduleBooking(Booking booking) async {
    if (booking.trainerUserId == null) return;
    final api = _api;
    final trainerId = booking.trainerUserId!;

    // Toon bottom sheet met beschikbare slots
    final selectedDateTime = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RescheduleSlotPicker(
        api: api,
        trainerId: trainerId,
        trainerName: booking.trainerName,
        currentScheduledAt: booking.scheduledAt,
      ),
    );

    if (selectedDateTime == null || !mounted) return;

    await _runBookingAction(booking, () async {
      await api.requestBookingReschedule(
        bookingId: booking.id,
        requestedAt: selectedDateTime,
      );
      _showSuccess(S.of(context).rescheduleRequestSent);
    });
  }

  Future<void> _startPayment(Booking booking) async {
    final api = _api;
    final promoController = TextEditingController();
    String paymentMethod = 'mollie';
    String suggestedCode = '';
    String suggestedCredit = '';
    try {
      final referral = await api.getMyReferralProgram();
      suggestedCode =
          (referral['code'] ??
                  referral['referral_code'] ??
                  referral['referralCode'] ??
                  '')
              .toString();
      suggestedCredit = (referral['credit'] ?? referral['reward'] ?? '')
          .toString();
    } catch (_) {
      suggestedCode = '';
    }
    if (!mounted) return;
    final usePromo = await GymiesDialog.custom<bool>(
      context,
      title: S.of(context).betalingStarten,
      icon: Icons.payments_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (suggestedCode.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).referralVoordeelBeschikbaar,
                    style: GoogleFonts.sora(fontWeight: FontWeight.w700),
                  ),
                  Text('Code: $suggestedCode'),
                  if (suggestedCredit.isNotEmpty)
                    Text(S.of(context).tegoedSuggested(suggestedCredit.toString())),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () {
                        promoController.text = suggestedCode;
                      },
                      child: const Text(S.of(context).gebruikCode),
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: promoController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: S.of(context).promocodeoptioneel,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: paymentMethod,
            decoration: const InputDecoration(labelText: S.of(context).betaalmethode),
            items: const [
              DropdownMenuItem(
                value: 'mollie',
                child: Text(S.of(context).onlinemollie),
              ),
              DropdownMenuItem(
                value: 'cash',
                child: Text(S.of(context).cashBijTrainer),
              ),
            ],
            onChanged: (v) {
              paymentMethod = v ?? 'mollie';
            },
          ),
        ],
      ),
      actions: [
        GymiesDialogAction(
          label: S.of(context).annuleren,
          returnValue: false,
        ),
        GymiesDialogAction(
          label: S.of(context).startBetaling,
          isPrimary: true,
          returnValue: true,
        ),
      ],
    );
    if (usePromo != true) return;
    await _runBookingAction(booking, () async {
      final data = await api.startBookingPayment(
        bookingId: booking.id,
        promoCode: promoController.text.trim(),
        paymentMethod: paymentMethod,
      );
      if (paymentMethod == 'cash') {
        _showSuccess(
          S.of(context).cashBetalingGemarkeerdBevestigBetalingBij,
        );
      } else {
        final url = (data['payment_url'] ?? data['url'] ?? '').toString();
        if (url.isEmpty) {
          _showSuccess('Betaling gestart');
        } else {
          _showSuccess(
            S.of(context).jeWordtNuDoorgestuurdNaarDe,
          );
          if (mounted) {
            final opened = await SafeUrlLauncher.launchPaymentUrl(context, url);
            if (!opened && mounted) {
              _showError(S.of(context).konBetaalpaginaNietOpenen);
            }
          }
        }
      }
    });
  }

  Future<void> _checkPaymentStatus(Booking booking) async {
    if (booking.id.isEmpty) {
      _showError(S.of(context).boekingidOntbreekt);
      return;
    }
    try {
      final status = await _api.getBookingPaymentStatus(
        booking.id,
      );
      if (!mounted) return;
      final label = (status['status'] ?? status['payment_status'] ?? 'onbekend')
          .toString();
      _showSuccess('Betaalstatus: $label');
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _addToCalendar(Booking booking) async {
    try {
      final ok = await CalendarService.instance.addBookingToCalendar(booking);
      if (!mounted) return;
      if (ok) {
        _showSuccess(S.of(context).sessieToegevoegdAanJeAgenda);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ClientSessions] Calendar sync fout: $e');
      if (mounted) {
        _showError(S.of(context).konSessieNietToevoegenAanAgenda);
      }
    }
  }

  Future<void> _shareBuddyInvite(Booking booking) async {
    final url = DeepLinkService.buddyInviteUrl(
      bookingId: booking.id,
      trainerId: booking.trainerUserId,
      trainerName: booking.trainerName,
    );
    final text =
        'Train met mij mee! Ik heb een sessie bij ${booking.trainerName} op '
        '${booking.scheduledAt.day}/${booking.scheduledAt.month}/${booking.scheduledAt.year} om '
        '${booking.scheduledAt.hour.toString().padLeft(2, '0')}:${booking.scheduledAt.minute.toString().padLeft(2, '0')}. '
        'Open de link om meer te weten: $url';
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, title: S.of(context).trainMetMijMee),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ClientSessions] Buddy invite delen fout: $e');
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        _showSuccess(S.of(context).linkGekopieerdNaarKlembord);
      }
    }
  }

  Future<void> _showReviewDialog(Booking booking) async {
    final trainerName = booking.trainerName.trim().isNotEmpty
        ? booking.trainerName.trim()
        : S.of(context).trainer;
    final result = await showReviewBottomSheet(
      context,
      trainerName: trainerName,
    );
    if (result == null || !mounted) return;
    if (_busyBookingIds.contains(booking.id)) return;
    setState(() => _busyBookingIds.add(booking.id));
    try {
      await _api.submitReview(
            bookingId: booking.id,
            rating: result.rating,
            message: result.message,
            isAnonymous: result.isAnonymous,
            photoPath: result.photoPath,
          );
      if (!mounted) return;
      _showSuccess(S.of(context).bedanktVoorJeBeoordeling);
      // Positieve actie: gebruiker geeft review → perfect moment voor in-app review
      InAppReviewService.instance.trackPositiveAction();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('[ClientSessions] Review versturen fout: $e');
      if (!mounted) return;
      _showError(S.of(context).beoordelingVersturenMisluktProbeerLaterOpnieuw);
    } finally {
      if (mounted) setState(() => _busyBookingIds.remove(booking.id));
    }
  }

  Future<void> _showBookingActions(Booking booking) async {
    final isBusy = _busyBookingIds.contains(booking.id);
    final isPayable =
        booking.amountCents != null &&
        booking.amountCents! > 0 &&
        booking.paidAt == null &&
        booking.status != 'cancelled';
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: GymiesColors.darkBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.tune_rounded, color: GymiesColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        S.of(context).meerActies,
                        style: GoogleFonts.sora(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(Icons.close_rounded, size: 22, color: Colors.grey.shade400),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      _ActionButton(
                        icon: Icons.info_outline,
                        iconColor: Colors.blue.shade600,
                        title: S.of(context).betaalstatusControleren,
                        onTap: isBusy
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                _checkPaymentStatus(booking);
                              },
                      ),
                      if (isPayable)
                        _ActionButton(
                          icon: Icons.payments_outlined,
                          iconColor: Colors.green.shade600,
                          title: S.of(context).betalingStarten,
                          onTap: isBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _startPayment(booking);
                                },
                        ),
                      if (booking.isUpcoming && booking.status != 'cancelled')
                        _ActionButton(
                          icon: Icons.calendar_month_outlined,
                          iconColor: Colors.teal.shade600,
                          title: S.of(context).rescheduleSession,
                          onTap: isBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _rescheduleBooking(booking);
                                },
                        ),
                      if (booking.isUpcoming && booking.status != 'cancelled')
                        _ActionButton(
                          icon: Icons.report_gmailerrorred_outlined,
                          iconColor: Colors.orange.shade800,
                          title: S.of(context).annuleringsoverzicht,
                          onTap: isBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _showCancellationPreview(booking);
                                },
                        ),
                      if (booking.isUpcoming && booking.status != 'cancelled')
                        _ActionButton(
                          icon: Icons.cancel_outlined,
                          iconColor: Colors.red.shade700,
                          title: S.of(context).cancelSession,
                          onTap: isBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _cancelBooking(booking);
                                },
                        ),
                      _ActionButton(
                        icon: Icons.gavel_rounded,
                        iconColor: Colors.deepOrange.shade700,
                        title: S.of(context).geschilIndienen,
                        onTap: isBusy
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                _raiseDispute(booking);
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestInvoiceForBooking(Booking booking) async {
    final trainerName = booking.trainerName.isEmpty
        ? S.of(context).trainer2
        : booking.trainerName;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientSupportScreen(
          initialType: 'invoice',
          initialSubject: S.of(context).factuurverzoekVoorSessie,
          initialMessage:
              'Hoi, ik wil graag een factuur ontvangen voor mijn sessie bij $trainerName op ${booking.scheduledAt.day.toString().padLeft(2, '0')}-${booking.scheduledAt.month.toString().padLeft(2, '0')}-${booking.scheduledAt.year}.',
          initialBookingId: booking.id,
          openComposerOnStart: true,
        ),
      ),
    );
  }

  Widget _buildSegmentTab(String label, int index, {int? count}) {
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_activeTab != index) {
            Haptics.selection();
            setState(() => _activeTab = index);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? GymiesColors.primary.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(
                    color: GymiesColors.primary.withOpacity(0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? GymiesColors.primary
                        : Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isActive
                        ? GymiesColors.primary.withOpacity(0.25)
                        : Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? GymiesColors.primary
                          : Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupContent() {
    if (_groupRegistrations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          const SizedBox(height: 64),
          Center(
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: GymiesColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.event_available_outlined, size: 34, color: GymiesColors.darkBlue),
            ),
          ),
          const SizedBox(height: 20),
          Text(S.of(context).geenInschrijvingen, style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(S.of(context).jeHebtJeNogNietIngeschrevenVoorEenGroepsles, style: GoogleFonts.sora(fontSize: 14, color: Colors.grey.shade600, height: 1.4), textAlign: TextAlign.center),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _groupRegistrations.length,
      itemBuilder: (_, i) {
        final r = _groupRegistrations[i];
        final id = (r['group_session_id'] ?? r['groupSessionId'] ?? '').toString();
        final rawTitle = (r['group_session_title'] ?? r['title'] ?? r['name'] ?? '').toString();
        final displayTitle = rawTitle.isEmpty ? S.of(context).groepsles : rawTitle;
        final startsAt = DateTime.tryParse((r['starts_at'] ?? r['startsAt'] ?? r['start_at'] ?? '').toString());
        final status = (r['status'] ?? r['payment_status'] ?? '').toString().toLowerCase();
        final isConfirmed = status == 'paid' || status == 'confirmed';
        final isPast = startsAt != null && startsAt.isBefore(DateTime.now());

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: id.isEmpty ? null : () async {
              Haptics.selection();
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ClientGroupSessionDetailScreen(groupSessionId: id)),
              );
              if (mounted) _load();
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    if (startsAt != null) ...[
                      Container(
                        width: 50,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isPast ? Colors.grey.shade100 : GymiesColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(_groupMonthAbbr(startsAt.month), style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: isPast ? Colors.grey.shade500 : GymiesColors.darkBlue)),
                            Text('${startsAt.day}', style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w700, color: isPast ? Colors.grey.shade600 : GymiesColors.darkBlue, height: 1.1)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayTitle, style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (startsAt != null) ...[
                            const SizedBox(height: 2),
                            Text('${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isConfirmed ? Colors.green.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isConfirmed ? 'Bevestigd' : 'In afwachting',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isConfirmed ? Colors.green.shade700 : Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _groupMonthAbbr(int month) {
    const months = ['JAN', 'FEB', 'MRT', 'APR', 'MEI', 'JUN', 'JUL', 'AUG', 'SEP', 'OKT', 'NOV', 'DEC'];
    return months[(month - 1).clamp(0, 11)];
  }

  Widget _buildWaitlistContent() {
    if (_waitlistEntries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          const SizedBox(height: 64),
          Center(
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: GymiesColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.hourglass_empty_rounded, size: 34, color: GymiesColors.darkBlue),
            ),
          ),
          const SizedBox(height: 20),
          Text(S.of(context).geenWachtlijsten, style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(S.of(context).alsEenTrainerVolgeboektIsKunJeJeOpDeWachtlijstPlaatsen, style: GoogleFonts.sora(fontSize: 14, color: Colors.grey.shade600, height: 1.4), textAlign: TextAlign.center),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _waitlistEntries.length,
      itemBuilder: (_, i) {
        final item = _waitlistEntries[i];
        final trainerName = (item[S.of(context).trainername] ?? item[S.of(context).trainername2] ?? S.of(context).trainer).toString();
        final requestedDate = (item['requested_date'] ?? item['requestedDate'] ?? item['preferred_date'] ?? '').toString();
        final status = (item['status'] ?? 'waiting').toString().toLowerCase();
        final position = item['position'] ?? item['queue_position'];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: GymiesColors.darkBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: Text(trainerName.isNotEmpty ? trainerName[0].toUpperCase() : '?', style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: GymiesColors.darkBlue, fontSize: 16))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(trainerName, style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                        if (requestedDate.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Voorkeursdatum: $requestedDate', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                        if (position != null) ...[
                          const SizedBox(height: 2),
                          Text('Positie: #$position', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: status == 'notified' ? Colors.green.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status == 'notified' ? 'Plek vrij!' : 'Wachtend',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: status == 'notified' ? Colors.green.shade700 : Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isSession(Booking b) {
      final status = b.status.toLowerCase();
      return b.isPast ||
          status == 'completed' ||
          status == 'no_show' ||
          status == 'noshow' ||
          status == 'done' ||
          status == 'finished';
    }

    final bookings = _bookings.where((b) => !isSession(b)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final sessions = _bookings.where(isSession).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            backgroundColor: GymiesColors.darkBlue,
            foregroundColor: Colors.white,
            pinned: true,
            toolbarHeight: 56,
            automaticallyImplyLeading: false,
            title: Text(
              S.of(context).training,
              style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    _buildSegmentTab('Komend', 0, count: bookings.length),
                    const SizedBox(width: 3),
                    _buildSegmentTab('Geweest', 1, count: sessions.length),
                    const SizedBox(width: 3),
                    _buildSegmentTab('Groep', 2, count: _groupRegistrations.length),
                    const SizedBox(width: 3),
                    _buildSegmentTab('Wacht', 3, count: _waitlistEntries.length),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: Stack(
          children: [
            GymiesListBody(
              loading: _loading,
              error: _error,
              onRefresh: _load,
              child: _activeTab == 2
                  ? _buildGroupContent()
                  : _activeTab == 3
                      ? _buildWaitlistContent()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: (_activeTab == 1 ? sessions : bookings).isEmpty
                              ? 1
                              : (_activeTab == 1 ? sessions : bookings).length,
                          itemBuilder: (context, i) {
                            final list = _activeTab == 1 ? sessions : bookings;
                            if (list.isEmpty) {
                              return _EmptyView(
                                title: _activeTab == 1
                                    ? S.of(context).nogGeenAfgerondeSessies
                                    : S.of(context).nogGeenKomendeSessies,
                                subtitle: _activeTab == 1
                                    ? S.of(context).jeVoltooideTrainingenEnBeoordelingenZullen
                                    : S.of(context).boekNuEenTrainingEnBegin,
                              );
                            }
                            final b = list[i];
                            return _SessionCard(
                              booking: b,
                              isBusy: _busyBookingIds.contains(b.id),
                              isPast: _activeTab == 1,
                              hasInvoice: _sentInvoiceForBooking(b.id) != null,
                              onActions: () => _showBookingActions(b),
                              onCheckInQr: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ClientCheckInQrScreen(booking: b),
                                ),
                              ),
                              onAddToCalendar: () => _addToCalendar(b),
                              onShare: () => _shareBuddyInvite(b),
                              onPay: () => _startPayment(b),
                              onReview: () => _showReviewDialog(b),
                              onOpenInvoice: () => _openInvoiceForBooking(b),
                              onRequestInvoice: () => _requestInvoiceForBooking(b),
                            );
                          },
                        ),
            ),
            // ── Safe Session Overlay ──────────────────────────
            if (_bookings.any((b) => b.safeSessionActive))
              SafeSessionOverlay(
                booking: _bookings.firstWhere((b) => b.safeSessionActive),
              ),
          ],
        ),
      ),
    );
  }
}

/// Vertaal ruwe backend status naar Nederlandse labels.
String _statusLabel(String raw) {
  switch (raw.toLowerCase()) {
    case 'reserved':
      return S.of(context).wachtOpBetaling;
    case 'pending':
    case 'pending_payment':
      return 'In afwachting';
    case 'confirmed':
      return 'Bevestigd';
    case 'cancelled':
    case 'canceled':
      return S.of(context).geannuleerd;
    case 'expired':
      return 'Verlopen';
    case 'completed':
    case 'done':
    case 'finished':
      return 'Afgerond';
    case 'checked_in':
      return 'Ingecheckt';
    case 'no_show':
    case 'noshow':
      return 'Niet verschenen';
    case 'failed':
      return S.of(context).betalingMislukt;
    case 'refunded':
      return 'Terugbetaald';
    default:
      return raw;
  }
}

/// Kleur bij status.
Color _statusColor(String raw) {
  switch (raw.toLowerCase()) {
    case 'reserved':
    case 'pending':
    case 'pending_payment':
      return Colors.orange;
    case 'confirmed':
    case 'checked_in':
      return Colors.green;
    case 'completed':
    case 'done':
    case 'finished':
      return Colors.blueGrey;
    case 'cancelled':
    case 'canceled':
    case 'expired':
      return Colors.red;
    case 'no_show':
    case 'noshow':
      return Colors.deepOrange;
    case 'failed':
      return Colors.red.shade800;
    case 'refunded':
      return Colors.purple;
    default:
      return Colors.grey;
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.booking,
    required this.isBusy,
    required this.isPast,
    required this.hasInvoice,
    required this.onActions,
    required this.onCheckInQr,
    required this.onAddToCalendar,
    required this.onShare,
    required this.onPay,
    required this.onReview,
    required this.onOpenInvoice,
    required this.onRequestInvoice,
  });

  final Booking booking;
  final bool isBusy;
  final bool isPast;
  final bool hasInvoice;
  final VoidCallback onActions;
  final VoidCallback onCheckInQr;
  final VoidCallback onAddToCalendar;
  final VoidCallback onShare;
  final VoidCallback onPay;
  final VoidCallback onReview;
  final VoidCallback onOpenInvoice;
  final VoidCallback onRequestInvoice;

  static const _monthNames = [
    'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
    'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
  ];

  static const _dayNames = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

  bool get _needsPayment =>
      (booking.status.toLowerCase() == 'reserved' ||
          booking.status.toLowerCase() == 'pending_payment') &&
      booking.paidAt == null &&
      booking.amountCents != null &&
      booking.amountCents! > 0;

  bool get _isUpcomingActive =>
      booking.isUpcoming && booking.status.toLowerCase() != 'cancelled';

  bool get _isWithinCheckInWindow {
    final scheduled = booking.scheduledAt;
    final diff = scheduled.difference(DateTime.now());
    return diff.inMinutes <= 15 && !diff.isNegative;
  }

  String _countdownText(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return 'Nu';
    if (diff.inMinutes < 60) return 'Over ${diff.inMinutes} min';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return m > 0 ? 'Over ${h}u ${m}m' : 'Over $h uur';
    }
    if (diff.inDays == 1) return 'Morgen';
    return 'Over ${diff.inDays} dagen';
  }

  /// Linkerborder kleur op basis van status
  Color get _accentColor {
    if (_needsPayment) return Colors.orange;
    if (isPast) return Colors.grey.shade300;
    final status = booking.status.toLowerCase();
    if (status == 'confirmed' || status == 'checked_in') return const Color(0xFF27AE60);
    if (status == 'cancelled' || status == 'canceled') return Colors.red;
    return GymiesColors.darkBlue;
  }

  /// Trainer initialen voor avatar
  String get _initials {
    final name = booking.trainerName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final month = _monthNames[b.scheduledAt.month - 1];
    final dayName = _dayNames[b.scheduledAt.weekday - 1];
    final timeStr =
        '${b.scheduledAt.hour.toString().padLeft(2, '0')}:${b.scheduledAt.minute.toString().padLeft(2, '0')}';
    final endTime = b.scheduledAt.add(Duration(minutes: b.durationMinutes));
    final endStr =
        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    final amount = b.amountCents == null
        ? null
        : formatEuro(b.amountCents);
    final sessionType = b.sessionType?.isNotEmpty == true ? b.sessionType! : null;

    // Inline datum: "Za 3 mei"
    final dateInline = '${dayName[0].toUpperCase()}${dayName.substring(1)} ${b.scheduledAt.day} $month';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: _needsPayment
              ? Border.all(color: Colors.orange.withOpacity(0.35), width: 1)
              : Border.all(color: Colors.grey.shade100, width: 0.5),
        ),
        child: Opacity(
          opacity: isPast ? 0.7 : 1.0,
          child: IntrinsicHeight(
            child: Row(
              children: [
                // ── Linkerborder accent ──
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: _accentColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                  ),
                ),
                // ── Card body ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Top row: avatar + info + dots ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Trainer avatar
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: isPast
                                    ? GymiesColors.darkBlue.withOpacity(0.3)
                                    : GymiesColors.darkBlue,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _initials,
                                  style: GoogleFonts.sora(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: GymiesColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Trainer name
                                  Text(
                                    b.trainerName.isEmpty ? S.of(context).trainer : b.trainerName,
                                    style: GoogleFonts.sora(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isPast
                                          ? Colors.grey.shade500
                                          : GymiesColors.darkBlue,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  // Metadata: datum · tijd · type
                                  Text.rich(
                                    TextSpan(
                                      style: GoogleFonts.sora(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                      children: [
                                        TextSpan(text: dateInline),
                                        const TextSpan(text: ' · '),
                                        TextSpan(text: '$timeStr – $endStr'),
                                        if (sessionType != null) ...[
                                          const TextSpan(text: ' · '),
                                          TextSpan(text: sessionType),
                                        ],
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Actions menu button (alleen voor niet-past)
                            if (!isPast)
                              GestureDetector(
                                onTap: isBusy ? null : onActions,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: GymiesColors.darkBlue.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: isBusy
                                      ? const Padding(
                                          padding: EdgeInsets.all(7),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: GymiesColors.primary,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.more_horiz_rounded,
                                          size: 16,
                                          color: GymiesColors.darkBlue,
                                        ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // ── Status + prijs rij ──
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(b.status)
                                    .withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _needsPayment
                                    ? S.of(context).wachtOpBetaling
                                    : _statusLabel(b.status),
                                style: GoogleFonts.sora(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _statusColor(b.status),
                                ),
                              ),
                            ),
                            if (!isPast && _isUpcomingActive) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: GymiesColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _countdownText(b.scheduledAt),
                                  style: GoogleFonts.sora(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (amount != null)
                              Text(
                                amount,
                                style: GoogleFonts.sora(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                          ],
                        ),

                        // ── Quick actions voor komende sessies ──
                        if (_isUpcomingActive && !_needsPayment) ...[
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Colors.grey.shade100),
                              ),
                            ),
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                if (_isWithinCheckInWindow) ...[
                                  _QuickActionChip(
                                    label: 'Check-in QR',
                                    icon: Icons.qr_code_2_rounded,
                                    isPrimary: true,
                                    onTap: onCheckInQr,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                _QuickActionChip(
                                  label: S.of(context).agenda,
                                  icon: Icons.event_available_rounded,
                                  onTap: onAddToCalendar,
                                ),
                                const SizedBox(width: 6),
                                _QuickActionChip(
                                  label: 'Delen',
                                  icon: Icons.share_rounded,
                                  onTap: onShare,
                                ),
                              ],
                            ),
                          ),
                        ],

                        // ── Betaal CTA ──
                        if (_needsPayment && !isPast) ...[
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Colors.grey.shade100),
                              ),
                            ),
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Text(
                                  amount ?? '',
                                  style: GoogleFonts.sora(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: isBusy ? null : onPay,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                      decoration: BoxDecoration(
                                        color: GymiesColors.darkBlue,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        S.of(context).betaalNu,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.sora(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: GymiesColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // ── Past session actions: Review + Factuur ──
                        if (isPast) ...[
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Colors.grey.shade100),
                              ),
                            ),
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                if (const {'completed', 'done', 'finished'}
                                    .contains(b.status.toLowerCase()))
                                  _QuickActionChip(
                                    label: 'Beoordeel',
                                    icon: Icons.star_outline_rounded,
                                    isPrimary: true,
                                    onTap: onReview,
                                  ),
                                if (const {'completed', 'done', 'finished'}
                                        .contains(b.status.toLowerCase()) &&
                                    (hasInvoice || true))
                                  const SizedBox(width: 6),
                                if (hasInvoice)
                                  _QuickActionChip(
                                    label: S.of(context).factuur2,
                                    icon: Icons.receipt_long_rounded,
                                    onTap: onOpenInvoice,
                                  )
                                else
                                  _QuickActionChip(
                                    label: S.of(context).factuur2,
                                    icon: Icons.receipt_long_rounded,
                                    onTap: onRequestInvoice,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isPrimary
                ? GymiesColors.primary.withOpacity(0.12)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isPrimary
                    ? GymiesColors.darkBlue
                    : Colors.grey.shade500,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isPrimary
                      ? GymiesColors.darkBlue
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(
                Icons.fitness_center_rounded,
                size: 36,
                color: GymiesColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 20,
              color: GymiesColors.darkBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              // Navigate to discover trainers tab using ClientShellExtension
              context.clientShell?.jumpToTab(1); // Navigate to Ontdekken tab
            },
            child: Text(
              S.of(context).zoekEenTrainer,
              style: GoogleFonts.sora(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.iconColor,
    required this.title,
    // ignore: unused_element_parameter
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: GoogleFonts.sora(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
