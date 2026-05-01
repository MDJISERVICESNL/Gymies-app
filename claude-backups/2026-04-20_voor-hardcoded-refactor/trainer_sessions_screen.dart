import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/gymies_theme.dart';
import '../models/booking.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../services/action_retry_queue_service.dart';
import 'trainer_agenda_screen.dart';
import 'trainer_documents_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Overzicht van alle sessies (pending, komend, voltooid) met bevestigen/afwijzen.
/// [initialTabIndex] 0=Te bevestigen, 1=Komend, 2=Voltooid – handig voor deep links.
class TrainerSessionsScreen extends StatefulWidget {
  const TrainerSessionsScreen({
    super.key,
    this.initialTabIndex,
    this.onAvatarTap,
    this.avatarLabel,
  });

  final int? initialTabIndex;
  final VoidCallback? onAvatarTap;
  final String? avatarLabel;

  @override
  State<TrainerSessionsScreen> createState() => _TrainerSessionsScreenState();
}

class _TrainerSessionsScreenState extends State<TrainerSessionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Booking> _bookings = [];
  Map<String, Map<String, dynamic>> _invoiceByBookingId = {};
  final Set<String> _actionBusyBookingIds = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final idx = widget.initialTabIndex;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: (idx != null && idx >= 0 && idx < 3) ? idx : 0,
    );
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final list = await api.getTrainerBookings();
      Map<String, Map<String, dynamic>> invoicesByBooking = {};
      try {
        final invoices = await api.getTrainerInvoices();
        for (final invoice in invoices) {
          final bookingId =
              (invoice['booking_id'] ?? invoice['bookingId'] ?? '')
                  .toString()
                  .trim();
          if (bookingId.isEmpty) continue;
          invoicesByBooking[bookingId] = invoice;
        }
      } catch (_) {
        invoicesByBooking = {};
      }
      if (mounted) {
        setState(() {
          _bookings = list;
          _invoiceByBookingId = invoicesByBooking;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Kon sessies niet laden.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirm(Booking b) async {
    if (_actionBusyBookingIds.contains(b.id)) return;
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await context.read<GymiesApi>().confirmTrainerBooking(b.id);
      if (mounted) {
        await _load();
        _showSuccess('Sessie bevestigd');
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  Future<void> _reject(Booking b) async {
    if (_actionBusyBookingIds.contains(b.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sessie afwijzen'),
        content: const Text(
          'Weet je zeker dat je deze aanvraag wilt afwijzen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Afwijzen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await context.read<GymiesApi>().rejectTrainerBooking(b.id);
      if (mounted) {
        await _load();
        _showSuccess('Sessie afgewezen');
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  Future<void> _cancel(Booking b) async {
    if (_actionBusyBookingIds.contains(b.id)) return;
    final api = context.read<GymiesApi>();
    bool notifyStandby = true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setModalState) => AlertDialog(
          title: const Text('Sessie annuleren'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Weet je zeker dat je deze sessie wilt annuleren?'),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: notifyStandby,
                contentPadding: EdgeInsets.zero,
                title: const Text('Stuur direct standby push'),
                subtitle: const Text(
                  'Geinteresseerde klanten krijgen meteen een boekkans.',
                ),
                onChanged: (v) =>
                    setModalState(() => notifyStandby = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Nee'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Ja, annuleren'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await api.cancelTrainerBooking(b.id);
      if (notifyStandby) {
        try {
          await api.notifyWaitlistForBooking(b.id);
        } catch (_) {
          // Niet blokkeren; annulering blijft leidend.
        }
      }
      if (mounted) {
        await _load();
        _showSuccess(
          notifyStandby
              ? 'Sessie geannuleerd en standby-push verstuurd'
              : 'Sessie geannuleerd',
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  Future<void> _complete(Booking b) async {
    if (_actionBusyBookingIds.contains(b.id)) return;
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await context.read<GymiesApi>().completeTrainerBooking(b.id);
      if (mounted) {
        await _load();
        _showSuccess('Sessie voltooid');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  Future<void> _startSafeSession(Booking b) async {
    if (_actionBusyBookingIds.contains(b.id)) return;
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await context.read<GymiesApi>().startSafeSession(bookingId: b.id);
      if (mounted) {
        await _load();
        _showSuccess('Safe session gestart');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  Future<void> _checkout(Booking b) async {
    if (_actionBusyBookingIds.contains(b.id)) return;
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await context.read<GymiesApi>().checkoutBooking(b.id);
      if (mounted) {
        await _load();
        _showSuccess('Sessie beëindigd');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  Future<void> _sendSos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SOS-alert'),
        content: const Text(
          'Weet je zeker dat je een noodalert wilt versturen? '
          'Admin wordt direct op de hoogte gesteld.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Verstuur SOS'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<GymiesApi>().sendSosAlert();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS-alert verstuurd. Hulp is onderweg.'),
            backgroundColor: GymiesColors.darkBlue,
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _checkIn(Booking b) async {
    if (_actionBusyBookingIds.contains(b.id)) return;
    final api = context.read<GymiesApi>();
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await api.markBookingCheckedIn(bookingId: b.id);
      await ActionRetryQueueService.log(
        actionType: 'trainer_check_in',
        status: 'sent',
        payload: {'booking_id': b.id},
        detail: 'Direct gelukt',
      );
      if (mounted) {
        await _load();
        _showSuccess('Check-in geregistreerd');
      }
    } on ApiException catch (e) {
      await ActionRetryQueueService.enqueue(
        actionType: 'trainer_check_in',
        payload: {'booking_id': b.id},
        reason: e.message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Check-in in wachtrij geplaatst. Wordt opnieuw verstuurd.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  Future<void> _markNoShow(Booking b) async {
    if (_actionBusyBookingIds.contains(b.id)) return;
    final reasonController = TextEditingController();
    final noteController = TextEditingController();
    final evidenceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No-show registreren'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reden',
                    hintText: 'Bijv. klant niet verschenen',
                  ),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Vul een reden in'
                      : null,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notitie (optioneel)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: evidenceController,
                  decoration: const InputDecoration(
                    labelText: 'Bewijs URL (optioneel)',
                    hintText: 'https://...',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.of(ctx).pop(true);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('No-show registreren'),
          ),
        ],
      ),
    );
    if (submit != true || !mounted) return;
    final reason = reasonController.text.trim();
    final note = noteController.text.trim();
    final evidenceUrl = evidenceController.text.trim();
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await context.read<GymiesApi>().markTrainerBookingNoShow(
        bookingId: b.id,
        reason: reason,
        note: note,
        evidenceUrl: evidenceUrl,
      );
      await ActionRetryQueueService.log(
        actionType: 'trainer_no_show',
        status: 'sent',
        payload: {'booking_id': b.id, 'reason': reason},
        detail: 'Direct gelukt',
      );
      if (mounted) {
        await _load();
        _showSuccess('No-show geregistreerd');
      }
    } on ApiException catch (e) {
      await ActionRetryQueueService.enqueue(
        actionType: 'trainer_no_show',
        payload: {
          'booking_id': b.id,
          'reason': reason,
          'note': note,
          'evidence_url': evidenceUrl,
        },
        reason: e.message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No-show in wachtrij geplaatst. Wordt opnieuw verstuurd.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  Future<void> _reschedule(Booking b) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: b.scheduledAt.isAfter(now) ? b.scheduledAt : now,
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(b.scheduledAt),
    );
    if (pickedTime == null || !mounted) return;
    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() => _actionBusyBookingIds.add(b.id));
    try {
      await context.read<GymiesApi>().requestBookingReschedule(
        bookingId: b.id,
        requestedAt: newDateTime,
      );
      if (mounted) {
        await _load();
        _showSuccess(
          'Verplaatsverzoek verstuurd naar de klant. De klant kan reageren in hun berichten.',
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(b.id));
    }
  }

  bool _invoiceAlreadySentFor(Booking booking) {
    final invoice = _invoiceByBookingId[booking.id];
    if (invoice == null) return false;
    final sentAt =
        (invoice['sent_at'] ??
                invoice['sentAt'] ??
                invoice['delivered_at'] ??
                '')
            .toString()
            .trim();
    final isSentRaw = invoice['is_sent'] ?? invoice['sent'];
    final isSent =
        isSentRaw == true ||
        isSentRaw == 1 ||
        isSentRaw?.toString().toLowerCase() == 'true';
    return isSent || sentAt.isNotEmpty;
  }

  Future<void> _composeAndSendInvoice(Booking booking) async {
    if (_actionBusyBookingIds.contains(booking.id)) return;
    final docsReady = await _ensureInvoiceDocumentsReady();
    if (!docsReady || !mounted) return;
    final existingInvoice = _invoiceByBookingId[booking.id];
    final existingInvoiceId =
        (existingInvoice?['id'] ??
                existingInvoice?['invoice_id'] ??
                existingInvoice?['invoiceId'] ??
                '')
            .toString()
            .trim();
    if (existingInvoiceId.isNotEmpty) {
      var existingPdfUrl = _invoicePdfLink(existingInvoice);
      if (existingPdfUrl.isEmpty) {
        try {
          final invoices = await context.read<GymiesApi>().getTrainerInvoices();
          for (final item in invoices) {
            final id =
                (item['id'] ?? item['invoice_id'] ?? item['invoiceId'] ?? '')
                    .toString()
                    .trim();
            if (id == existingInvoiceId) {
              existingPdfUrl = _invoicePdfLink(item);
              break;
            }
          }
        } catch (_) {
          // Niet blokkeren; validatie hieronder vangt ontbreken af.
        }
      }
      if (existingPdfUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF ontbreekt op server. Eerst PDF laten genereren, daarna versturen.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final confirmResend = await _openInvoiceReviewDialog(
        booking: booking,
        amountCents: _extractInvoiceAmountCents(existingInvoice),
        serviceType:
            (existingInvoice?['service_type'] ??
                    existingInvoice?['serviceType'] ??
                    'Personal training sessie')
                .toString(),
        serviceDate: _extractInvoiceDate(existingInvoice, booking.scheduledAt),
        dueDate: _extractInvoiceDate(
          existingInvoice,
          booking.scheduledAt.add(const Duration(days: 14)),
          keys: const ['due_date', 'dueDate'],
        ),
        pdfUrl: existingPdfUrl,
        existingInvoiceId: existingInvoiceId,
        resend: true,
      );
      if (confirmResend != true) return;
      if (!mounted) return;
      setState(() => _actionBusyBookingIds.add(booking.id));
      try {
        await context.read<GymiesApi>().sendTrainerInvoice(
          invoiceId: existingInvoiceId,
        );
        await _load();
        _showSuccess('Factuur verstuurd naar klant');
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _actionBusyBookingIds.remove(booking.id));
      }
      return;
    }
    final defaultCents = booking.amountCents ?? 0;
    final defaultEuro = (defaultCents / 100).toStringAsFixed(2);
    final amountCtrl = TextEditingController(text: defaultEuro);
    final serviceTypeCtrl = TextEditingController(
      text: 'Personal training sessie',
    );
    final now = DateTime.now();
    DateTime serviceDate = DateTime(
      booking.scheduledAt.year,
      booking.scheduledAt.month,
      booking.scheduledAt.day,
    );
    DateTime dueDate = serviceDate.add(const Duration(days: 14));
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Factuur opstellen'),
        content: StatefulBuilder(
          builder: (context, setModalState) {
            return Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Prijs incl. BTW (EUR)',
                      ),
                      validator: (v) {
                        final raw = (v ?? '').replaceAll(',', '.').trim();
                        final parsed = double.tryParse(raw);
                        if (parsed == null || parsed <= 0) {
                          return 'Vul een geldig bedrag in';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: serviceTypeCtrl,
                      decoration: const InputDecoration(labelText: 'Dienst'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Vul een dienstnaam in'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Service datum'),
                      subtitle: Text(
                        '${serviceDate.day.toString().padLeft(2, '0')}-${serviceDate.month.toString().padLeft(2, '0')}-${serviceDate.year}',
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2022),
                          lastDate: now.add(const Duration(days: 365 * 2)),
                          initialDate: serviceDate,
                        );
                        if (picked == null) return;
                        setModalState(() => serviceDate = picked);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Vervaldatum'),
                      subtitle: Text(
                        '${dueDate.day.toString().padLeft(2, '0')}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.year}',
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: serviceDate,
                          lastDate: now.add(const Duration(days: 365 * 2)),
                          initialDate: dueDate.isBefore(serviceDate)
                              ? serviceDate
                              : dueDate,
                        );
                        if (picked == null) return;
                        setModalState(() => dueDate = picked);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Opstellen & versturen'),
          ),
        ],
      ),
    );
    if (submit != true || !mounted) return;
    final amountRaw = amountCtrl.text.replaceAll(',', '.').trim();
    final amountCents = ((double.tryParse(amountRaw) ?? 0) * 100).round();
    if (amountCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factuurbedrag moet groter zijn dan 0'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _actionBusyBookingIds.add(booking.id));
    try {
      final api = context.read<GymiesApi>();
      final created = await api.createTrainerInvoiceForBooking(
        bookingId: booking.id,
        priceIncVatCents: amountCents,
        serviceType: serviceTypeCtrl.text.trim(),
        serviceDate: serviceDate,
        dueDate: dueDate,
      );
      final invoiceId =
          (created['id'] ?? created['invoice_id'] ?? created['invoiceId'] ?? '')
              .toString()
              .trim();
      final sentAt = (created['sent_at'] ?? created['sentAt'] ?? '')
          .toString()
          .trim();
      final isSentRaw = created['is_sent'] ?? created['sent'];
      final alreadySent =
          sentAt.isNotEmpty ||
          isSentRaw == true ||
          isSentRaw == 1 ||
          isSentRaw?.toString().toLowerCase() == 'true';

      var previewPdfUrl = _invoicePdfLink(created);
      if (previewPdfUrl.isEmpty) {
        try {
          final invoices = await api.getTrainerInvoices();
          Map<String, dynamic>? match;
          for (final item in invoices) {
            final id =
                (item['id'] ?? item['invoice_id'] ?? item['invoiceId'] ?? '')
                    .toString()
                    .trim();
            final bookingId = (item['booking_id'] ?? item['bookingId'] ?? '')
                .toString()
                .trim();
            if ((invoiceId.isNotEmpty && id == invoiceId) ||
                (bookingId.isNotEmpty && bookingId == booking.id)) {
              match = item;
              break;
            }
          }
          previewPdfUrl = _invoicePdfLink(match);
        } catch (_) {
          // Niet blokkeren als herlaad van facturen faalt.
        }
      }
      if (previewPdfUrl.isEmpty) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Factuur is aangemaakt maar PDF-link ontbreekt. Versturen is geblokkeerd tot PDF beschikbaar is.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final confirmSend = await _openInvoiceReviewDialog(
        booking: booking,
        amountCents: amountCents,
        serviceType: serviceTypeCtrl.text.trim(),
        serviceDate: serviceDate,
        dueDate: dueDate,
        pdfUrl: previewPdfUrl,
        existingInvoiceId: invoiceId.isEmpty ? null : invoiceId,
        resend: false,
      );
      if (confirmSend != true) {
        await _load();
        _showSuccess(
          'Factuur is opgesteld. Je kunt later reviewen en versturen.',
        );
        return;
      }

      if (!alreadySent && invoiceId.isNotEmpty) {
        await api.sendTrainerInvoice(invoiceId: invoiceId);
      }
      await _load();
      _showSuccess('Factuur opgesteld en verstuurd naar klant');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionBusyBookingIds.remove(booking.id));
    }
  }

  Future<bool?> _openInvoiceReviewDialog({
    required Booking booking,
    required int amountCents,
    required String serviceType,
    required DateTime serviceDate,
    required DateTime dueDate,
    String? pdfUrl,
    String? existingInvoiceId,
    required bool resend,
  }) {
    final amountEur = (amountCents / 100).toStringAsFixed(2);
    final name = (booking.clientName ?? booking.trainerName).isNotEmpty
        ? (booking.clientName ?? booking.trainerName)
        : 'Klant';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          resend ? 'Factuur review (opnieuw versturen)' : 'Factuur review',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _reviewRow('Klant', name),
              _reviewRow('Boeking', booking.id),
              if ((existingInvoiceId ?? '').isNotEmpty)
                _reviewRow('Factuur-ID', existingInvoiceId!),
              _reviewRow('Dienst', serviceType),
              _reviewRow('Service datum', _formatDate(serviceDate)),
              _reviewRow('Vervaldatum', _formatDate(dueDate)),
              _reviewRow('Bedrag incl. BTW', 'EUR $amountEur'),
              if ((pdfUrl ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _openPdfLink(pdfUrl!),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('Bekijk de PDF'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                resend
                    ? 'Deze factuur wordt opnieuw naar de klant gestuurd voor deze boeking.'
                    : 'Controleer de factuurgegevens voordat je verstuurt.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                'Na versturen moet de klant de PDF direct downloaden.',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(resend ? 'Annuleren' : 'Terug bewerken'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
            ),
            child: Text(resend ? 'Opnieuw versturen' : 'Verstuur naar klant'),
          ),
        ],
      ),
    );
  }

  DateTime _extractInvoiceDate(
    Map<String, dynamic>? invoice,
    DateTime fallback, {
    List<String> keys = const ['service_date', 'serviceDate', 'invoice_date'],
  }) {
    if (invoice == null) return fallback;
    for (final key in keys) {
      final raw = invoice[key];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  int _extractInvoiceAmountCents(Map<String, dynamic>? invoice) {
    if (invoice == null) return 0;
    final rawCandidates = [
      invoice['price_inc_vat_cents'],
      invoice['amount_cents'],
      invoice['total_cents'],
      invoice['amount'],
      invoice['total'],
    ];
    for (final raw in rawCandidates) {
      if (raw is int) {
        if (raw > 0) return raw;
      } else if (raw is num) {
        final value = raw.toInt();
        if (value > 0) return value;
      } else if (raw != null) {
        final asInt = int.tryParse(raw.toString());
        if (asInt != null && asInt > 0) return asInt;
        final asDouble = double.tryParse(raw.toString().replaceAll(',', '.'));
        if (asDouble != null && asDouble > 0) return (asDouble * 100).round();
      }
    }
    return 0;
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  String _invoicePdfLink(Map<String, dynamic>? invoice) {
    if (invoice == null) return '';
    final keys = [
      'pdf_public_url',
      'pdf_download_url',
      'invoice_pdf_url',
      'pdf_url',
      'pdf',
      'url',
    ];
    for (final key in keys) {
      final value = invoice[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  Future<void> _openPdfLink(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF link is ongeldig.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kon PDF niet openen.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<bool> _ensureInvoiceDocumentsReady() async {
    final api = context.read<GymiesApi>();
    Map<String, dynamic> docs;
    try {
      docs = await api.getTrainerDocuments();
    } on ApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
      return false;
    }

    final missing = _missingInvoiceDocFields(docs);
    if (missing.isEmpty) return true;
    if (!mounted) return false;

    final goToDocs = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Factuurgegevens ontbreken'),
        content: Text(
          'Vul eerst je factuurdocumenten in:\n- ${missing.join('\n- ')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
            ),
            child: const Text('Naar documenten'),
          ),
        ],
      ),
    );
    if (goToDocs != true || !mounted) return false;

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TrainerDocumentsScreen()));
    if (!mounted) return false;
    try {
      final refreshed = await api.getTrainerDocuments();
      final remaining = _missingInvoiceDocFields(refreshed);
      if (remaining.isEmpty) return true;
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Documenten nog niet compleet opgeslagen. Vul verplichte velden in.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    } on ApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  List<String> _missingInvoiceDocFields(Map<String, dynamic> docs) {
    bool hasAny(List<String> keys) {
      for (final key in keys) {
        final value = docs[key];
        if (value != null && value.toString().trim().isNotEmpty) return true;
      }
      return false;
    }

    final missing = <String>[];
    if (!hasAny(const ['company_name', 'companyName'])) {
      missing.add('Bedrijfsnaam');
    }
    if (!hasAny(const ['kvk_number', 'kvk'])) {
      missing.add('KVK-nummer');
    }
    if (!hasAny(const ['trainer_address_line1', 'address_line1', 'address'])) {
      missing.add('Adresregel 1');
    }
    if (!hasAny(const ['trainer_postcode', 'postcode'])) {
      missing.add('Postcode');
    }
    if (!hasAny(const ['trainer_city', 'city'])) {
      missing.add('Stad');
    }
    if (!hasAny(const ['trainer_country', 'country', 'country_code'])) {
      missing.add('Land');
    }
    return missing;
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  List<Booking> get _pending =>
      _bookings.where((b) => b.status == 'pending').toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  List<Booking> get _upcoming =>
      _bookings.where((b) => b.status == 'confirmed' && b.isUpcoming).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  List<Booking> get _completed =>
      _bookings
          .where(
            (b) =>
                b.status == 'completed' ||
                b.status == 'no_show' ||
                b.status == 'noshow' ||
                b.isPast,
          )
          .toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Mijn sessies',
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Agenda',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const TrainerAgendaScreen()),
            ),
          ),
        ],
        onAvatarTap: widget.onAvatarTap,
        avatarLabel: widget.avatarLabel,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GymiesColors.primary,
          indicatorWeight: 3,
          labelColor: GymiesColors.primary,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.85),
          labelStyle: GoogleFonts.fjallaOne(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.fjallaOne(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Te bevestigen'),
            Tab(text: 'Komend'),
            Tab(text: 'Voltooid'),
          ],
        ),
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: Stack(
                children: [
                  TabBarView(
                controller: _tabController,
                children: [
                  _SessionList(
                    bookings: _pending,
                    onConfirm: _confirm,
                    onReject: _reject,
                    onCancel: _cancel,
                    onComplete: _complete,
                    onCheckIn: _checkIn,
                    onReschedule: _reschedule,
                    onNoShow: _markNoShow,
                    onStartSafeSession: _startSafeSession,
                    onCheckout: _checkout,
                    onCreateInvoice: _composeAndSendInvoice,
                    invoiceForBookingId: _invoiceByBookingId,
                    invoiceSentForBooking: _invoiceAlreadySentFor,
                    busyBookingIds: _actionBusyBookingIds,
                    emptyIcon: Icons.mark_chat_read_rounded,
                    emptyText: 'Geen nieuwe aanvragen',
                    emptySubtitle:
                        'Wanneer een klant een sessie aanvraagt, zie je het hier direct.',
                  ),
                  _SessionList(
                    bookings: _upcoming,
                    onCancel: _cancel,
                    onComplete: _complete,
                    onCheckIn: _checkIn,
                    onReschedule: _reschedule,
                    onNoShow: _markNoShow,
                    onStartSafeSession: _startSafeSession,
                    onCheckout: _checkout,
                    onCreateInvoice: _composeAndSendInvoice,
                    invoiceForBookingId: _invoiceByBookingId,
                    invoiceSentForBooking: _invoiceAlreadySentFor,
                    busyBookingIds: _actionBusyBookingIds,
                    emptyIcon: Icons.calendar_today_rounded,
                    emptyText: 'Agenda is leeg',
                    emptySubtitle:
                        'Klanten boeken via jouw profiel. Zorg dat je beschikbaarheid klopt zodat ze je kunnen vinden.',
                    emptyActionLabel: 'Beschikbaarheid instellen',
                    emptyActionIcon: Icons.schedule_rounded,
                    onEmptyAction: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TrainerAgendaScreen(),
                      ),
                    ),
                    emptySecondaryActionLabel: 'Ververs',
                    emptySecondaryActionIcon: Icons.refresh_rounded,
                    onEmptySecondaryAction: _load,
                    isUpcomingTab: true,
                  ),
                  _SessionList(
                    bookings: _completed,
                    onCreateInvoice: _composeAndSendInvoice,
                    invoiceForBookingId: _invoiceByBookingId,
                    invoiceSentForBooking: _invoiceAlreadySentFor,
                    busyBookingIds: _actionBusyBookingIds,
                    emptyIcon: Icons.history_rounded,
                    emptyText: 'Nog geen voltooide sessies',
                    emptySubtitle:
                        'Afgeronde sessies verschijnen hier als historie.',
                  ),
                ],
              ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      onPressed: _sendSos,
                      backgroundColor: Colors.red.shade700,
                      tooltip: 'SOS-alert',
                      child: const Icon(Icons.emergency_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({
    required this.bookings,
    required this.emptyText,
    this.emptySubtitle,
    this.emptyActionLabel,
    this.emptyActionIcon = Icons.refresh_rounded,
    this.onEmptyAction,
    this.emptySecondaryActionLabel,
    this.emptySecondaryActionIcon = Icons.open_in_new_rounded,
    this.onEmptySecondaryAction,
    required this.busyBookingIds,
    this.onCancel,
    this.onComplete,
    this.onCheckIn,
    this.onReschedule,
    this.onNoShow,
    this.onStartSafeSession,
    this.onCheckout,
    this.onConfirm,
    this.onReject,
    this.onCreateInvoice,
    this.invoiceForBookingId,
    this.invoiceSentForBooking,
    this.isUpcomingTab = false,
    this.emptyIcon = Icons.event_available_rounded,
  });

  final List<Booking> bookings;
  final String emptyText;
  final String? emptySubtitle;
  final String? emptyActionLabel;
  final IconData emptyActionIcon;
  final VoidCallback? onEmptyAction;
  final String? emptySecondaryActionLabel;
  final IconData emptySecondaryActionIcon;
  final VoidCallback? onEmptySecondaryAction;
  final IconData emptyIcon;
  final Set<String> busyBookingIds;
  final void Function(Booking)? onCancel;
  final void Function(Booking)? onComplete;
  final void Function(Booking)? onCheckIn;
  final void Function(Booking)? onReschedule;
  final void Function(Booking)? onNoShow;
  final void Function(Booking)? onStartSafeSession;
  final void Function(Booking)? onCheckout;
  final void Function(Booking)? onConfirm;
  final void Function(Booking)? onReject;
  final void Function(Booking)? onCreateInvoice;
  final Map<String, Map<String, dynamic>>? invoiceForBookingId;
  final bool Function(Booking booking)? invoiceSentForBooking;
  final bool isUpcomingTab;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          TrainerEmptyState(
            icon: emptyIcon,
            title: emptyText,
            subtitle: emptySubtitle,
            actionLabel: emptyActionLabel,
            actionIcon: emptyActionIcon,
            onAction: onEmptyAction,
            secondaryActionLabel: emptySecondaryActionLabel,
            secondaryActionIcon: emptySecondaryActionIcon,
            onSecondaryAction: onEmptySecondaryAction,
            padding: const EdgeInsets.all(32),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: bookings.length,
      itemBuilder: (_, i) {
        final b = bookings[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SessionCard(
            booking: b,
            onConfirm: onConfirm != null ? () => onConfirm!(b) : null,
            onReject: onReject != null ? () => onReject!(b) : null,
            onCancel: onCancel != null ? () => onCancel!(b) : null,
            onComplete: onComplete != null ? () => onComplete!(b) : null,
            onCheckIn: onCheckIn != null ? () => onCheckIn!(b) : null,
            onReschedule: onReschedule != null ? () => onReschedule!(b) : null,
            onNoShow: onNoShow != null ? () => onNoShow!(b) : null,
            onStartSafeSession: onStartSafeSession != null
                ? () => onStartSafeSession!(b)
                : null,
            onCheckout: onCheckout != null ? () => onCheckout!(b) : null,
            onCreateInvoice: onCreateInvoice != null
                ? () => onCreateInvoice!(b)
                : null,
            invoice: invoiceForBookingId?[b.id],
            invoiceAlreadySent: invoiceSentForBooking != null
                ? invoiceSentForBooking!(b)
                : false,
            busy: busyBookingIds.contains(b.id),
            isUpcomingTab: isUpcomingTab,
          ),
        );
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.booking,
    this.onConfirm,
    this.onReject,
    this.onCancel,
    this.onComplete,
    this.onCheckIn,
    this.onReschedule,
    this.onNoShow,
    this.onStartSafeSession,
    this.onCheckout,
    this.onCreateInvoice,
    this.invoice,
    this.invoiceAlreadySent = false,
    this.busy = false,
    this.isUpcomingTab = false,
  });

  final Booking booking;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;
  final VoidCallback? onCheckIn;
  final VoidCallback? onReschedule;
  final VoidCallback? onNoShow;
  final VoidCallback? onStartSafeSession;
  final VoidCallback? onCheckout;
  final VoidCallback? onCreateInvoice;
  final Map<String, dynamic>? invoice;
  final bool invoiceAlreadySent;
  final bool busy;
  final bool isUpcomingTab;

  @override
  Widget build(BuildContext context) {
    final d = booking.scheduledAt;
    final name = booking.clientName ?? booking.trainerName;
    final displayName = name.isNotEmpty ? name : 'Klant';
    final invoiceEligible =
        booking.isPast ||
        booking.status == 'completed' ||
        booking.status == 'done' ||
        booking.status == 'finished';

    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: GymiesColors.darkBlue.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _statusColor(booking.status).withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: GymiesColors.primary.withValues(alpha: 0.3),
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: GymiesColors.darkBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} · ${booking.durationMinutes} min',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(booking.status).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(booking.status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(booking.status),
                    ),
                  ),
                ),
                if (!isUpcomingTab)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (busy) return;
                      switch (value) {
                        case 'checkin':
                          onCheckIn?.call();
                          break;
                        case 'reschedule':
                          onReschedule?.call();
                          break;
                        case 'cancel':
                          onCancel?.call();
                          break;
                        case 'complete':
                          onComplete?.call();
                          break;
                        case 'safe_session':
                          onStartSafeSession?.call();
                          break;
                        case 'checkout':
                          onCheckout?.call();
                          break;
                        case 'no_show':
                          onNoShow?.call();
                          break;
                        case 'invoice':
                          onCreateInvoice?.call();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      if (booking.status == 'confirmed' &&
                          booking.checkInAt == null)
                        const PopupMenuItem(
                          value: 'checkin',
                          child: Text('Check-in registreren'),
                        ),
                      const PopupMenuItem(
                        value: 'reschedule',
                        child: Text('Verplaatsen'),
                      ),
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Text('Annuleren'),
                      ),
                      const PopupMenuItem(
                        value: 'complete',
                        child: Text('Voltooien'),
                      ),
                      if (onStartSafeSession != null &&
                          (booking.status == 'checked_in' ||
                              booking.checkInAt != null))
                        const PopupMenuItem(
                          value: 'safe_session',
                          child: Text('Safe session starten'),
                        ),
                      if (onCheckout != null &&
                          (booking.status == 'checked_in' ||
                              booking.checkInAt != null))
                        const PopupMenuItem(
                          value: 'checkout',
                          child: Text('Beëindig sessie'),
                        ),
                      if (onNoShow != null &&
                          (booking.status == 'confirmed' ||
                              booking.status == 'checked_in'))
                        const PopupMenuItem(
                          value: 'no_show',
                          child: Text('No-show registreren'),
                        ),
                      if (onCreateInvoice != null &&
                          (booking.isPast ||
                              booking.status == 'completed' ||
                              booking.status == 'done' ||
                              booking.status == 'finished'))
                        PopupMenuItem(
                          value: 'invoice',
                          child: Text(
                            invoiceAlreadySent
                                ? 'Factuur opnieuw versturen'
                                : 'Factuur opstellen',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (isUpcomingTab && (onCancel != null || onReschedule != null)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (onCancel != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : onCancel,
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Annuleren'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade400),
                        ),
                      ),
                    ),
                  if (onCancel != null && onReschedule != null)
                    const SizedBox(width: 12),
                  if (onReschedule != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : onReschedule,
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: const Text('Verplaatsen'),
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (invoiceEligible) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: invoiceAlreadySent
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  invoiceAlreadySent
                      ? 'Factuur verstuurd'
                      : 'Factuur niet verstuurd',
                  style: TextStyle(
                    color: invoiceAlreadySent
                        ? Colors.green.shade800
                        : Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      color: GymiesColors.darkBlue.withValues(alpha: 0.8),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        invoiceAlreadySent
                            ? 'Factuur sectie: review en opnieuw versturen'
                            : 'Factuur sectie: opstellen en review',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: (busy || onCreateInvoice == null)
                          ? null
                          : onCreateInvoice,
                      child: Text(
                        invoiceAlreadySent
                            ? 'Review factuur'
                            : 'Factuur opstellen',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (booking.checkInAt != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ingecheckt op ${booking.checkInAt!.day.toString().padLeft(2, '0')}-${booking.checkInAt!.month.toString().padLeft(2, '0')} ${booking.checkInAt!.hour.toString().padLeft(2, '0')}:${booking.checkInAt!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if ((booking.noShowReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No-show: ${booking.noShowReason}${(booking.noShowNote ?? '').isEmpty ? '' : ' · ${booking.noShowNote}'}',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if (onConfirm != null &&
                onReject != null &&
                booking.status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : onReject,
                    child: Text(
                      'Afwijzen',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : onConfirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Bevestigen'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'confirmed':
        return Colors.green.shade700;
      case 'checked_in':
        return Colors.teal.shade700;
      case 'pending':
        return Colors.orange.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      case 'no_show':
      case 'noshow':
        return Colors.red.shade800;
      default:
        return GymiesColors.darkBlue;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'confirmed':
        return 'Bevestigd';
      case 'pending':
        return 'Te bevestigen';
      case 'cancelled':
        return 'Geannuleerd';
      case 'completed':
        return 'Voltooid';
      case 'checked_in':
        return 'Ingecheckt';
      case 'no_show':
      case 'noshow':
        return 'No-show';
      default:
        return s;
    }
  }
}
