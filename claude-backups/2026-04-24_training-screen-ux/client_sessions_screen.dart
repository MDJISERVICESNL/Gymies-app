import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/timing_constants.dart';
import '../models/booking.dart';
import '../services/api_client.dart';
import '../services/calendar_service.dart';
import '../services/deep_link_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../services/in_app_review_service.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'client_check_in_qr_screen.dart';
import 'client_support_screen.dart';
import 'shells/client_shell.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/safe_session_overlay.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.paymentReturnBookingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Haal actuele betaalstatus op (webhook kan al binnen zijn)
        try {
          final api = context.read<GymiesApi>();
          final status = await api.getBookingPaymentStatus(
            widget.paymentReturnBookingId!,
          );
          if (!mounted) return;
          final paymentStatus = (status['status'] ?? status['payment_status'] ?? '')
              .toString()
              .toLowerCase();
          if (paymentStatus == 'paid' || paymentStatus == 'confirmed') {
            _showSuccess('Betaling gelukt! Je sessie is bevestigd.');
            InAppReviewService.instance.trackPositiveAction();
          } else if (paymentStatus == 'failed' || paymentStatus == 'cancelled' || paymentStatus == 'expired') {
            _showError('Betaling niet gelukt. Je kunt het opnieuw proberen via de acties bij je boeking.');
          } else {
            // Pending — webhook is nog niet binnen, geef neutrale melding
            _showSuccess('Betaling wordt verwerkt. De status wordt zo bijgewerkt.');
          }
        } catch (_) {
          // API niet bereikbaar — geef neutrale melding
          _showSuccess('Je bent terug van de betaalpagina. Trek om te vernieuwen.');
        }
        // Herlaad de lijst om actuele status te tonen
        _load();
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final list = await api.getBookings();
      List<Map<String, dynamic>> invoices = [];
      try {
        invoices = await api.getClientInvoices();
      } catch (e) {
        debugPrint('[ClientSessions] Facturen laden mislukt: $e');
        invoices = [];
      }
      if (!mounted) return;
      setState(() {
        _bookings = list;
        _invoices = invoices;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[ClientSessions] Sessies laden fout: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Kon sessies niet laden.';
        _loading = false;
      });
    }
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
      _showError('Factuur nog niet beschikbaar.');
      return;
    }
    final link = _invoiceLink(invoice);
    if (link.isEmpty) {
      _showError('Factuurlink ontbreekt.');
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showError('Factuurlink is ongeldig.');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download de PDF direct na openen.'),
        backgroundColor: GymiesColors.darkBlue,
      ),
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showError('Kon factuur niet openen.');
    }
  }

  Future<void> _runBookingAction(
    Booking booking,
    Future<void> Function() action,
  ) async {
    if (booking.id.isEmpty) {
      _showError('Boeking-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.');
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
      debugPrint('[ClientSessions] Booking actie fout: $e');
      _showError('Actie mislukt. Probeer opnieuw.');
    } finally {
      if (mounted) {
        setState(() => _busyBookingIds.remove(booking.id));
      }
    }
  }

  Future<void> _showCancellationPreview(Booking booking) async {
    if (booking.id.isEmpty) {
      _showError('Boeking-ID ontbreekt.');
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
        title: 'Annuleringsoverzicht',
        message: 'Kosten: $fee cents\nTerugbetaling: $refundable cents',
        icon: Icons.report_gmailerrorred_outlined,
        buttonLabel: 'Sluiten',
      );
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _cancelBooking(Booking booking) async {
    // Haal annuleringsbeleid op voordat we de dialoog tonen
    Map<String, dynamic>? preview;
    try {
      preview = await context.read<GymiesApi>().getBookingCancellationPreview(booking.id);
    } catch (_) {
      // Fallback: toon simpele bevestiging als preview niet beschikbaar is
    }

    if (!mounted) return;

    final policyMsg = (preview?['cancellation_policy_message'] ?? '').toString();
    final penaltyApplies = preview?['penalty_applies'] == true;
    final refundPercent = (preview?['refund_percent'] ?? 0);

    final ok = await GymiesDialog.custom<bool>(
      context,
      title: 'Sessie annuleren',
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
                      style: TextStyle(
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
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          if (refundPercent is num && refundPercent > 0)
            const SizedBox(height: 8),
          const Text('Weet je zeker dat je deze sessie wilt annuleren?'),
        ],
      ),
      actions: [
        GymiesDialogAction(
          label: 'Nee, behouden',
          returnValue: false,
        ),
        GymiesDialogAction(
          label: 'Ja, annuleren',
          isPrimary: true,
          isDestructive: true,
          returnValue: true,
        ),
      ],
    );
    if (ok != true) return;
    await _runBookingAction(booking, () async {
      await context.read<GymiesApi>().cancelBooking(
        bookingId: booking.id,
        reason: 'client_cancelled',
      );
      _showSuccess('Sessie geannuleerd');
    });
  }

  Future<void> _rescheduleBooking(Booking booking) async {
    final date = await showDatePicker(
      context: context,
      initialDate: booking.scheduledAt.isAfter(DateTime.now())
          ? booking.scheduledAt
          : DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(TimingConstants.datePickerMaxRange),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(booking.scheduledAt),
    );
    if (time == null) return;
    final requestedAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await _runBookingAction(booking, () async {
      await context.read<GymiesApi>().requestBookingReschedule(
        bookingId: booking.id,
        requestedAt: requestedAt,
      );
      _showSuccess('Verplaatsingsverzoek verstuurd');
    });
  }

  Future<void> _startPayment(Booking booking) async {
    final api = context.read<GymiesApi>();
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
      title: 'Betaling starten',
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
                  const Text(
                    'Referral voordeel beschikbaar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('Code: $suggestedCode'),
                  if (suggestedCredit.isNotEmpty)
                    Text('Tegoed: $suggestedCredit'),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () {
                        promoController.text = suggestedCode;
                      },
                      child: const Text('Gebruik code'),
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: promoController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Promocode (optioneel)',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: paymentMethod,
            decoration: const InputDecoration(labelText: 'Betaalmethode'),
            items: const [
              DropdownMenuItem(
                value: 'mollie',
                child: Text('Online (Mollie)'),
              ),
              DropdownMenuItem(
                value: 'cash',
                child: Text('Cash bij trainer'),
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
          label: 'Annuleren',
          returnValue: false,
        ),
        GymiesDialogAction(
          label: 'Start betaling',
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
          'Cash betaling gemarkeerd. Bevestig betaling bij trainer.',
        );
      } else {
        final url = (data['payment_url'] ?? data['url'] ?? '').toString();
        if (url.isEmpty) {
          _showSuccess('Betaling gestart');
        } else {
          _showSuccess(
            'Je wordt nu doorgestuurd naar de betaalpagina. Na betaling keer je terug naar de app.',
          );
          final uri = Uri.tryParse(url);
          if (uri != null) {
            final opened = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (!opened && mounted) {
              _showError('Kon betaalpagina niet openen.');
            }
          }
        }
      }
    });
  }

  Future<void> _checkPaymentStatus(Booking booking) async {
    if (booking.id.isEmpty) {
      _showError('Boeking-ID ontbreekt.');
      return;
    }
    try {
      final status = await context.read<GymiesApi>().getBookingPaymentStatus(
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
        _showSuccess('Sessie toegevoegd aan je agenda');
      }
    } catch (e) {
      debugPrint('[ClientSessions] Calendar sync fout: $e');
      if (mounted) {
        _showError('Kon sessie niet toevoegen aan agenda');
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
      await Share.share(text, subject: 'Train met mij mee!');
    } catch (e) {
      debugPrint('[ClientSessions] Buddy invite delen fout: $e');
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        _showSuccess('Link gekopieerd naar klembord');
      }
    }
  }

  Future<void> _showReviewDialog(Booking booking) async {
    int rating = 5;
    bool isAnonymous = false;
    final controller = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => GymiesDialog(
          title: 'Beoordeling geven',
          headerIcon: Icons.star_outline_rounded,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hoe was je sessie bij ${booking.trainerName}?',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return IconButton(
                      icon: Icon(
                        star <= rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 36,
                      ),
                      onPressed: () => setState(() => rating = star),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Compliment of opmerking (optioneel)',
                    hintText: 'Bijv. Top sessie, heel motiverend!',
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: isAnonymous,
                  onChanged: (v) => setState(() => isAnonymous = v ?? false),
                  title: const Text('Anoniem plaatsen'),
                  subtitle: const Text('Je naam wordt niet getoond bij de review'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            GymiesDialogAction(
              label: 'Annuleren',
              returnValue: null,
            ),
            GymiesDialogAction(
              label: 'Versturen',
              isPrimary: true,
              returnValue: {'submit': true, 'isAnonymous': isAnonymous},
            ),
          ],
        ),
      ),
    );
    if (result == null || result['submit'] != true || !mounted) return;
    final reviewIsAnonymous = result['isAnonymous'] == true;
    if (_busyBookingIds.contains(booking.id)) return;
    setState(() => _busyBookingIds.add(booking.id));
    try {
      await context.read<GymiesApi>().submitReview(
            bookingId: booking.id,
            rating: rating,
            message: controller.text.trim().isEmpty ? null : controller.text.trim(),
            isAnonymous: reviewIsAnonymous,
          );
      if (!mounted) return;
      _showSuccess('Bedankt voor je beoordeling!');
      // Positieve actie: gebruiker geeft review → perfect moment voor in-app review
      InAppReviewService.instance.trackPositiveAction();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      debugPrint('[ClientSessions] Review versturen fout: $e');
      if (!mounted) return;
      _showError('Beoordeling versturen mislukt. Probeer later opnieuw.');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tune_rounded, color: GymiesColors.darkBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Acties',
                      style: GoogleFonts.sora(fontSize: 18, color: GymiesColors.darkBlue),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionButton(
                        icon: Icons.info_outline,
                        iconColor: Colors.blue.shade600,
                        title: 'Betaalstatus controleren',
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
                          title: 'Betaling starten',
                          onTap: isBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _startPayment(booking);
                                },
                        ),
                      if (booking.isUpcoming && booking.status != 'cancelled')
                        _ActionButton(
                          icon: Icons.group_add_rounded,
                          iconColor: Colors.orange.shade600,
                          title: 'Train met een vriend',
                          subtitle: 'Deel uitnodigingslink',
                          onTap: isBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _shareBuddyInvite(booking);
                                },
                        ),
                      if (booking.isUpcoming && booking.status != 'cancelled')
                        _ActionButton(
                          icon: Icons.qr_code_2_rounded,
                          iconColor: Colors.purple.shade600,
                          title: 'Toon check-in QR',
                          onTap: isBusy
                              ? null
                              : () async {
                                  Navigator.of(ctx).pop();
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ClientCheckInQrScreen(booking: booking),
                                    ),
                                  );
                                },
                        ),
                      if (booking.isUpcoming && booking.status != 'cancelled')
                        _ActionButton(
                          icon: Icons.event_available_rounded,
                          iconColor: Colors.green.shade700,
                          title: 'Toevoegen aan agenda',
                          subtitle: 'Apple of Google Calendar',
                          onTap: isBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _addToCalendar(booking);
                                },
                        ),
                      if (booking.isUpcoming && booking.status != 'cancelled')
                        _ActionButton(
                          icon: Icons.calendar_month_outlined,
                          iconColor: Colors.teal.shade600,
                          title: 'Sessie verplaatsen',
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
                          title: 'Annuleringsoverzicht',
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
                          title: 'Sessie annuleren',
                          onTap: isBusy
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  _cancelBooking(booking);
                                },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestInvoiceForBooking(Booking booking) async {
    final trainerName = booking.trainerName.isEmpty
        ? 'trainer'
        : booking.trainerName;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientSupportScreen(
          initialType: 'invoice',
          initialSubject: 'Factuurverzoek voor sessie',
          initialMessage:
              'Hoi, ik wil graag een factuur ontvangen voor mijn sessie bij $trainerName op ${booking.scheduledAt.day.toString().padLeft(2, '0')}-${booking.scheduledAt.month.toString().padLeft(2, '0')}-${booking.scheduledAt.year}.',
          initialBookingId: booking.id,
          openComposerOnStart: true,
        ),
      ),
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
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Mijn afspraken',
        actions: [
          IconButton(
            tooltip: 'Support',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ClientSupportScreen()),
              );
            },
            icon: const Icon(Icons.support_agent_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          GymiesListBody(
            loading: _loading,
            error: _error,
            onRefresh: _load,
            child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Komend',
                        style: GoogleFonts.sora(
                          fontSize: 18,
                          color: GymiesColors.darkBlue,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _SessionList(
                    bookings: bookings,
                    busyBookingIds: _busyBookingIds,
                    onOpenActions: _showBookingActions,
                    showActions: true,
                    emptyTitle: 'Nog geen komende sessies',
                    emptySubtitle:
                        'Boek nu een training en begin je fitnessreis. Je trainer zal contact opnemen om alles in te plannen.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Geweest',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SessionList(
                    bookings: sessions,
                    busyBookingIds: _busyBookingIds,
                    onOpenActions: _showBookingActions,
                    invoiceForBooking: _sentInvoiceForBooking,
                    onOpenInvoice: _openInvoiceForBooking,
                    onRequestInvoice: _requestInvoiceForBooking,
                    onLeaveReview: _showReviewDialog,
                    showActions: false,
                    emptyTitle: 'Nog geen afgeronde sessies',
                    emptySubtitle:
                        'Je voltooide trainingen en beoordelingen zullen hier verschijnen na je eerste sessie.',
                  ),
                ],
              ),
          ),
          // ── Safe Session Overlay ──────────────────────────
          // Toon overlay als er een actieve safe session is
          if (_bookings.any((b) => b.safeSessionActive))
            SafeSessionOverlay(
              booking: _bookings.firstWhere((b) => b.safeSessionActive),
            ),
        ],
      ),
    );
  }
}

/// Vertaal ruwe backend status naar Nederlandse labels.
String _statusLabel(String raw) {
  switch (raw.toLowerCase()) {
    case 'reserved':
      return 'Wacht op betaling';
    case 'pending':
    case 'pending_payment':
      return 'In afwachting';
    case 'confirmed':
      return 'Bevestigd';
    case 'cancelled':
    case 'canceled':
      return 'Geannuleerd';
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
      return 'Betaling mislukt';
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

class _SessionList extends StatelessWidget {
  const _SessionList({
    required this.bookings,
    required this.busyBookingIds,
    required this.onOpenActions,
    this.invoiceForBooking,
    this.onOpenInvoice,
    this.onRequestInvoice,
    this.onLeaveReview,
    required this.showActions,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<Booking> bookings;
  final Set<String> busyBookingIds;
  final Future<void> Function(Booking booking) onOpenActions;
  final Map<String, dynamic>? Function(String bookingId)? invoiceForBooking;
  final Future<void> Function(Booking booking)? onOpenInvoice;
  final Future<void> Function(Booking booking)? onRequestInvoice;
  final Future<void> Function(Booking booking)? onLeaveReview;
  final bool showActions;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return _EmptyView(title: emptyTitle, subtitle: emptySubtitle);
    }
    return Column(
      children: bookings.map((b) {
        final date =
            '${b.scheduledAt.day.toString().padLeft(2, '0')}-${b.scheduledAt.month.toString().padLeft(2, '0')}-${b.scheduledAt.year}';
        final time =
            '${b.scheduledAt.hour.toString().padLeft(2, '0')}:${b.scheduledAt.minute.toString().padLeft(2, '0')}';
        final amount = b.amountCents == null
            ? 'Onbekend bedrag'
            : '€${(b.amountCents! / 100).toStringAsFixed(2)}';
        final checkInLabel = b.checkInAt == null
            ? null
            : 'Ingecheckt: ${b.checkInAt!.day.toString().padLeft(2, '0')}-${b.checkInAt!.month.toString().padLeft(2, '0')} ${b.checkInAt!.hour.toString().padLeft(2, '0')}:${b.checkInAt!.minute.toString().padLeft(2, '0')}';
        final packageUsage =
            (b.sessionsRemaining != null && b.packageSessionsTotal != null)
            ? 'Pakket: ${b.sessionsRemaining} van ${b.packageSessionsTotal} over'
            : (b.sessionsRemaining != null
                  ? 'Pakket: nog ${b.sessionsRemaining} ${b.sessionsRemaining == 1 ? 'sessie' : 'sessies'}'
                  : null);
        final noShowLabel = (b.noShowReason ?? '').isNotEmpty
            ? 'No-show gemeld: ${b.noShowReason}${b.noShowFeeCents == null ? '' : ' · Kosten: €${(b.noShowFeeCents! / 100).toStringAsFixed(2)}'}'
            : null;
        final hasInvoice = invoiceForBooking?.call(b.id) != null;
        final translatedStatus = _statusLabel(b.status);
        final needsPayment = b.status.toLowerCase() == 'reserved' &&
            b.paidAt == null &&
            b.amountCents != null &&
            b.amountCents! > 0;
        final subtitleLines = [
          '$date om $time · $amount',
          translatedStatus,
          checkInLabel,
          packageUsage,
          noShowLabel,
        ].whereType<String>().join(' · ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              dense: true,
              leading: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    needsPayment
                        ? Icons.payment_rounded
                        : showActions
                            ? Icons.event_available_rounded
                            : Icons.check_circle_outline_rounded,
                    size: 20,
                    color: needsPayment
                        ? Colors.orange.shade700
                        : _statusColor(b.status),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _statusColor(b.status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      needsPayment ? 'Betaal' : translatedStatus,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(b.status),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              title: Text(
                b.trainerName.isEmpty ? 'Trainer' : b.trainerName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                subtitleLines,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
              trailing: showActions
                  ? busyBookingIds.contains(b.id)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            onSelected: (value) {
                              if (value == 'actions') {
                                onOpenActions(b);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem<String>(
                                value: 'actions',
                                child: Row(
                                  children: [
                                    const Icon(Icons.tune, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Acties · ${_statusLabel(b.status)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                  : Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        if (onLeaveReview != null &&
                            const {'completed', 'done', 'finished'}.contains(b.status.toLowerCase()))
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => onLeaveReview!(b),
                            icon: const Icon(
                              Icons.star_outline_rounded,
                              size: 16,
                            ),
                            label: const Text('Beoordeling', style: TextStyle(fontSize: 12)),
                          ),
                        if (hasInvoice)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => onOpenInvoice?.call(b),
                            child: const Text('PDF', style: TextStyle(fontSize: 12)),
                          )
                        else if (onRequestInvoice != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => onRequestInvoice!(b),
                            child: const Text('Factuur', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
            ),
          ),
        );
      }).toList(),
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
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Icon(
                Icons.calendar_today_rounded,
                size: 40,
                color: Colors.grey.shade400,
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
              'Zoek een trainer',
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
                  color: iconColor.withValues(alpha: 0.12),
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
