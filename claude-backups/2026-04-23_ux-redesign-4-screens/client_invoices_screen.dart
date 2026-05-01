import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/booking.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'client_support_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class ClientInvoicesScreen extends StatefulWidget {
  const ClientInvoicesScreen({super.key});

  @override
  State<ClientInvoicesScreen> createState() => _ClientInvoicesScreenState();
}

class _ClientInvoicesScreenState extends State<ClientInvoicesScreen> {
  bool _loading = true;
  bool _openingLink = false;
  final Set<String> _requestingInvoiceBookingIds = {};
  String? _error;
  List<Map<String, dynamic>> _invoices = [];
  List<Booking> _bookings = [];
  String _statusFilter = 'all';
  String _viewMode = 'invoices';

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
      final api = context.read<GymiesApi>();
      final list = await api.getClientInvoices();
      List<Booking> bookings = [];
      try {
        bookings = await api.getBookings();
      } catch (_) {
        bookings = [];
      }
      if (!mounted) return;
      setState(() {
        _invoices = list;
        _bookings = bookings;
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
        _error = 'Kon facturen niet laden.';
        _loading = false;
      });
    }
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _moneyFromAny(Map<String, dynamic> invoice) {
    final cents = _toInt(
      mapPick(invoice, ['total_cents', 'totalCents', 'amount_cents']),
    );
    if (cents != null) return '€${(cents / 100).toStringAsFixed(2)}';
    final amount = mapStr(invoice, ['total', 'amount']);
    return amount.isEmpty ? '-' : amount;
  }

  String _status(Map<String, dynamic> invoice) {
    final raw = mapStr(invoice, [
      'status',
      'payment_status',
      'state',
    ]).toLowerCase();
    if (raw.contains('paid') || raw == 'succeeded' || raw == 'completed') {
      return 'paid';
    }
    if (raw.contains('open') ||
        raw.contains('pending') ||
        raw.contains('unpaid') ||
        raw.contains('due')) {
      return 'open';
    }
    return raw.isEmpty ? 'unknown' : raw;
  }

  String _statusLabel(Map<String, dynamic> invoice) {
    final s = _status(invoice);
    if (s == 'paid') return 'Betaald';
    if (s == 'open') return 'Openstaand';
    if (s == 'unknown') return 'Onbekend';
    return s;
  }

  Color _statusColor(Map<String, dynamic> invoice) {
    final s = _status(invoice);
    if (s == 'paid') return Colors.green.shade700;
    if (s == 'open') return Colors.orange.shade800;
    return Colors.grey.shade700;
  }

  List<Map<String, dynamic>> _filteredInvoices() {
    final sentInvoices = _invoices.where(_isSentInvoice).toList();
    if (_statusFilter == 'all') return sentInvoices;
    return sentInvoices
        .where(
          (invoice) => _statusFilter == 'paid'
              ? _status(invoice) == 'paid'
              : _status(invoice) == 'open',
        )
        .toList();
  }

  bool _isSentInvoice(Map<String, dynamic> invoice) {
    final sentAt = mapStr(invoice, ['sent_at', 'sentAt', 'delivered_at']);
    final isSentRaw = mapPick(invoice, ['is_sent', 'sent']);
    final isSent =
        isSentRaw == true ||
        isSentRaw == 1 ||
        isSentRaw?.toString().toLowerCase() == 'true';
    final number = mapStr(invoice, [
      'number',
      'invoice_number',
      'trainer_invoice_number',
      'gymies_invoice_number',
    ]);
    final link = _invoiceLink(invoice);
    return isSent ||
        sentAt.isNotEmpty ||
        (number.isNotEmpty && link.isNotEmpty);
  }

  List<Booking> _sessionRecords() {
    bool isSession(Booking b) {
      final status = b.status.toLowerCase();
      return b.isPast ||
          status == 'completed' ||
          status == 'done' ||
          status == 'finished';
    }

    return _bookings.where(isSession).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
  }

  String _invoiceLink(Map<String, dynamic> invoice) {
    return mapStr(invoice, [
      'download_url',
      'pdf_url',
      'pdf_public_url',
      'pdf_download_url',
      'invoice_pdf_url',
      'invoice_url',
      'payment_url',
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

  Future<void> _requestInvoiceForBooking(Booking booking) async {
    final bookingId = booking.id.trim();
    if (bookingId.isEmpty) {
      _showError('Boeking-ID ontbreekt.');
      return;
    }
    if (_requestingInvoiceBookingIds.contains(bookingId)) return;
    setState(() => _requestingInvoiceBookingIds.add(bookingId));
    final trainerName = booking.trainerName.isEmpty
        ? 'trainer'
        : booking.trainerName;
    final message =
        'Klant vraagt factuur aan voor booking $bookingId (${booking.scheduledAt.toIso8601String()}) bij $trainerName.';
    try {
      await context.read<GymiesApi>().requestInvoiceFromTrainer(
        bookingId: bookingId,
        message: message,
      );
      if (!mounted) return;
      _showSuccess('Factuurverzoek verstuurd naar trainer');
    } on ApiException {
      // Fallback: support ticket blijft altijd traceerbaar voor trainer/support.
      try {
        await context.read<GymiesApi>().createSupportTicket(
          type: 'invoice',
          subject: 'Factuurverzoek',
          message:
              'Ik wil graag een factuur voor sessie $bookingId bij $trainerName.',
          bookingId: bookingId,
        );
        if (!mounted) return;
        _showSuccess('Factuurverzoek geregistreerd');
      } on ApiException catch (e) {
        if (!mounted) return;
        _showError(e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _requestingInvoiceBookingIds.remove(bookingId));
      }
    }
  }

  Map<String, dynamic> _receiptFromInvoice(Map<String, dynamic> invoice) {
    String read(List<String> keys) => mapStr(invoice, keys);
    return <String, dynamic>{
      'paid_at': read(['paid_at', 'paidAt', 'payment_date', 'paymentDate']),
      'method': read(['payment_method', 'method', 'payment_method_label']),
      'reference': read([
        'payment_reference',
        'reference',
        'transaction_id',
        'trx_id',
      ]),
      'booking_id': read(['booking_id', 'bookingId']),
      'referral_credit': read([
        'referral_credit',
        'referral_credit_amount',
        'referralDiscount',
        'discount_referral',
      ]),
      'promo_code': read(['promo_code', 'code', 'coupon_code']),
      'amount': _moneyFromAny(invoice),
    };
  }

  List<Map<String, dynamic>> _receiptRecords() {
    final paidInvoices = _invoices
        .where((i) => _isSentInvoice(i) && _status(i) == 'paid')
        .toList();
    return paidInvoices.map((invoice) {
      final receipt = _receiptFromInvoice(invoice);
      return <String, dynamic>{'invoice': invoice, ...receipt};
    }).toList();
  }

  Future<void> _openInvoiceLink(String link) async {
    if (link.isEmpty) return;
    if (_openingLink) return;
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
    setState(() => _openingLink = true);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showError('Kon link niet openen.');
      }
    } catch (_) {
      _showError('Kon link niet openen.');
    } finally {
      if (mounted) setState(() => _openingLink = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  Future<void> _showInvoiceDetail(Map<String, dynamic> invoice) async {
    final number =
        mapStr(invoice, [
          'number',
          'invoice_number',
          'trainer_invoice_number',
          'gymies_invoice_number',
        ]).isNotEmpty
        ? mapStr(invoice, [
            'number',
            'invoice_number',
            'trainer_invoice_number',
            'gymies_invoice_number',
          ])
        : 'Factuur';
    final date = mapStr(invoice, ['date', 'issued_at', 'created_at']);
    final dueDate = mapStr(invoice, ['due_date', 'expires_at']);
    final amount = _moneyFromAny(invoice);
    final status = _statusLabel(invoice);
    final link = _invoiceLink(invoice);
    var receipt = _receiptFromInvoice(invoice);
    if (status.toLowerCase() == 'betaald' &&
        receipt['paid_at'].toString().isEmpty &&
        receipt['reference'].toString().isEmpty) {
      try {
        final api = context.read<GymiesApi>();
        final bookingId = mapStr(invoice, ['booking_id', 'bookingId']);
        final invoiceId = mapStr(invoice, ['id', 'invoice_id', 'invoiceId']);
        final loaded = await api.getPaymentReceipt(
          bookingId: bookingId.isEmpty ? null : bookingId,
          invoiceId: invoiceId.isEmpty ? null : invoiceId,
        );
        receipt = {
          ...receipt,
          'paid_at': mapStr(loaded, [
            'paid_at',
            'paidAt',
            'payment_date',
            'created_at',
          ]),
          'method': mapStr(loaded, ['payment_method', 'method']),
          'reference': mapStr(loaded, ['reference', 'transaction_id', 'trx_id']),
          'booking_id': mapStr(loaded, ['booking_id', 'bookingId']),
          'referral_credit': mapStr(loaded, [
            'referral_credit',
            'referral_credit_amount',
            'referral_discount',
          ]),
          'promo_code': mapStr(loaded, ['promo_code', 'code', 'coupon_code']),
          'amount': mapStr(loaded, ['amount', 'amount_label']).isEmpty
              ? amount
              : mapStr(loaded, ['amount', 'amount_label']),
        };
      } catch (_) {
        // Geen hard-fail; toon wat al bekend is uit factuurdata.
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  number,
                  style: GoogleFonts.fjallaOne(
                    fontSize: 22,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _DetailRow(label: 'Status', value: status, valueColor: _statusColor(invoice)),
                      const Divider(height: 16),
                      _DetailRow(label: 'Datum', value: date.isEmpty ? '-' : date),
                      _DetailRow(label: 'Vervaldatum', value: dueDate.isEmpty ? '-' : dueDate),
                      _DetailRow(label: 'Bedrag', value: amount),
                    ],
                  ),
                ),
                if (status.toLowerCase() == 'betaald') ...[
                  const SizedBox(height: 16),
                  Text(
                    'Betaalbewijs',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 16,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow(label: 'Betaald op', value: receipt['paid_at'].toString().isEmpty ? '-' : receipt['paid_at']),
                        _DetailRow(label: 'Methode', value: receipt['method'].toString().isEmpty ? '-' : receipt['method']),
                        _DetailRow(label: 'Referentie', value: receipt['reference'].toString().isEmpty ? '-' : receipt['reference']),
                        if (receipt['booking_id'].toString().isNotEmpty)
                          _DetailRow(label: 'Boeking-ID', value: receipt['booking_id'].toString()),
                        if (receipt['referral_credit'].toString().isNotEmpty)
                          _DetailRow(label: 'Referraltegoed', value: receipt['referral_credit'].toString()),
                        if (receipt['promo_code'].toString().isNotEmpty)
                          _DetailRow(label: 'Promocode', value: receipt['promo_code'].toString()),
                      ],
                    ),
                  ),
                ],
                if (link.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'PDF downloaden',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 16,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Download de factuur direct als PDF. De link kan na verloop van tijd verlopen.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openingLink
                          ? null
                          : () {
                              Navigator.of(ctx).pop();
                              _openInvoiceLink(link);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: GymiesColors.primary,
                        foregroundColor: GymiesColors.darkBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download PDF'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(ctx);
                        await Clipboard.setData(ClipboardData(text: link));
                        if (!mounted) return;
                        navigator.pop();
                        _showSuccess('Link gekopieerd');
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Kopieer link'),
                    ),
                  ),
                ],
                if (link.isEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Geen downloadlink beschikbaar.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredInvoices();
    final sentInvoices = _invoices.where(_isSentInvoice).toList();
    final sessionRecords = _sessionRecords();
    final receipts = _receiptRecords();
    final paidCount = sentInvoices.where((i) => _status(i) == 'paid').length;
    final openCount = sentInvoices.where((i) => _status(i) == 'open').length;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Mijn facturen',
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
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: (_invoices.isEmpty && _bookings.isEmpty)
                  ? ListView(
                      children: const [
                        _EmptyView(
                          title: 'Nog geen facturen',
                          subtitle:
                              'Na een sessie kun je hier je factuur bekijken en downloaden. Boekingen en facturen verschijnen automatisch.',
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _SectionHeader(
                          title: 'Overzicht',
                          subtitle: 'Bekijk je facturen, sessies of betaalbewijzen.',
                        ),
                        const SizedBox(height: 12),
                        _ViewModeTabs(
                          selected: _viewMode,
                          onChanged: (v) => setState(() => _viewMode = v),
                        ),
                        const SizedBox(height: 20),
                        if (_viewMode == 'invoices') ...[
                          _SectionHeader(
                            title: 'Status',
                            subtitle: 'Betaald vs openstaand.',
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _StatTile(
                                  label: 'Betaald',
                                  value: '$paidCount',
                                  color: Colors.green.shade700,
                                  icon: Icons.check_circle_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatTile(
                                  label: 'Openstaand',
                                  value: '$openCount',
                                  color: Colors.orange.shade800,
                                  icon: Icons.schedule_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _SectionHeader(
                            title: 'Filter',
                            subtitle: 'Toon alle facturen of filter op status.',
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'all', label: Text('Alles')),
                              ButtonSegment(
                                value: 'paid',
                                label: Text('Betaald'),
                              ),
                              ButtonSegment(
                                value: 'open',
                                label: Text('Openstaand'),
                              ),
                            ],
                            selected: {_statusFilter},
                            onSelectionChanged: (v) {
                              setState(() => _statusFilter = v.first);
                            },
                          ),
                          const SizedBox(height: 20),
                          _SectionHeader(
                            title: 'Facturen',
                            subtitle: filtered.isEmpty
                                ? 'Geen facturen die voldoen aan het filter.'
                                : 'Tik op een factuur om details te zien of te downloaden.',
                          ),
                          const SizedBox(height: 10),
                          if (filtered.isEmpty)
                            const _EmptyView(
                              title: 'Geen facturen',
                              subtitle:
                                  'Facturen verschijnen hier zodra je trainer ze verstuurt. Vraag anders een factuur aan via het sessie-overzicht.',
                            )
                          else
                            ...filtered.map((invoice) {
                              final number =
                                  mapStr(invoice, [
                                    'number',
                                    'invoice_number',
                                    'trainer_invoice_number',
                                    'gymies_invoice_number',
                                  ]).isNotEmpty
                                  ? mapStr(invoice, [
                                      'number',
                                      'invoice_number',
                                      'trainer_invoice_number',
                                      'gymies_invoice_number',
                                    ])
                                  : 'Factuur';
                              final date = mapStr(invoice, [
                                'date',
                                'issued_at',
                                'created_at',
                              ]);
                              final status = _statusLabel(invoice);
                              final amount = _moneyFromAny(invoice);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: InkWell(
                                  onTap: () => _showInvoiceDetail(invoice),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: _statusColor(invoice)
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            Icons.receipt_long_rounded,
                                            color: _statusColor(invoice),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                number,
                                                style: GoogleFonts.fjallaOne(
                                                  fontSize: 15,
                                                  color: GymiesColors.darkBlue,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                date.isEmpty ? '-' : date,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              amount,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _statusColor(invoice)
                                                    .withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                status,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _statusColor(invoice),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.chevron_right,
                                          color: Colors.grey.shade500,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                        ] else if (_viewMode == 'sessions') ...[
                          _SectionHeader(
                            title: 'Sessie-overzicht',
                            subtitle: sessionRecords.isEmpty
                                ? 'Geen voltooide sessies.'
                                : 'Per sessie zie je of er al een factuur is verstuurd. Zo niet, kun je er een aanvragen.',
                          ),
                          const SizedBox(height: 10),
                          if (sessionRecords.isEmpty)
                            const _EmptyView(
                              title: 'Nog geen sessies',
                              subtitle:
                                  'Zodra een sessie is geweest zie je hier het overzicht.',
                            )
                          else
                            ...sessionRecords.map((b) {
                              final date =
                                  '${b.scheduledAt.day.toString().padLeft(2, '0')}-${b.scheduledAt.month.toString().padLeft(2, '0')}-${b.scheduledAt.year}';
                              final time =
                                  '${b.scheduledAt.hour.toString().padLeft(2, '0')}:${b.scheduledAt.minute.toString().padLeft(2, '0')}';
                              final amount = b.amountCents == null
                                  ? 'Onbekend bedrag'
                                  : '€${(b.amountCents! / 100).toStringAsFixed(2)}';
                              final sentInvoice = _sentInvoiceForBooking(b.id);
                              final requestBusy = _requestingInvoiceBookingIds
                                  .contains(b.id);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: GymiesColors.primary
                                              .withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.event_note_rounded,
                                          color: GymiesColors.darkBlue,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              b.trainerName.isEmpty
                                                  ? 'Trainer'
                                                  : b.trainerName,
                                              style: GoogleFonts.fjallaOne(
                                                fontSize: 15,
                                                color: GymiesColors.darkBlue,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '$date om $time',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              sentInvoice == null
                                                  ? 'Factuur nog niet verstuurd'
                                                  : 'Factuur beschikbaar',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: sentInvoice == null
                                                    ? Colors.orange.shade700
                                                    : Colors.green.shade700,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            amount,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          sentInvoice != null
                                              ? FilledButton.icon(
                                                  onPressed: () =>
                                                      _showInvoiceDetail(sentInvoice),
                                                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                                                  label: const Text('Bekijk'),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: GymiesColors.primary,
                                                    foregroundColor: GymiesColors.darkBlue,
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                  ),
                                                )
                                              : requestBusy
                                                  ? const SizedBox(
                                                      width: 24,
                                                      height: 24,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  : TextButton(
                                                      onPressed: () =>
                                                          _requestInvoiceForBooking(b),
                                                      child: const Text('Vraag aan'),
                                                    ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ] else ...[
                          _SectionHeader(
                            title: 'Betaalbewijzen',
                            subtitle: receipts.isEmpty
                                ? 'Geen betaalde facturen.'
                                : 'Overzicht van betaalde facturen met betalingsgegevens.',
                          ),
                          const SizedBox(height: 10),
                          if (receipts.isEmpty)
                            const _EmptyView(
                              title: 'Nog geen betaalbewijzen',
                              subtitle:
                                  'Betaalde facturen verschijnen hier met betaalmethode en referentie.',
                            )
                          else
                            ...receipts.map((r) {
                              final invoice =
                                  (r['invoice'] as Map<String, dynamic>?) ??
                                  <String, dynamic>{};
                              final number =
                                  mapStr(invoice, [
                                    'number',
                                    'invoice_number',
                                    'trainer_invoice_number',
                                    'gymies_invoice_number',
                                  ]).isEmpty
                                  ? 'Factuur'
                                  : mapStr(invoice, [
                                      'number',
                                      'invoice_number',
                                      'trainer_invoice_number',
                                      'gymies_invoice_number',
                                    ]);
                              final paidAt = r['paid_at'].toString().isEmpty ? '-' : r['paid_at'];
                              final method = r['method'].toString().isEmpty ? '-' : r['method'];
                              final ref = r['reference'].toString().isEmpty ? '-' : r['reference'];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: InkWell(
                                  onTap: () => _showInvoiceDetail(invoice),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            Icons.verified_rounded,
                                            color: Colors.green.shade700,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                number,
                                                style: GoogleFonts.fjallaOne(
                                                  fontSize: 15,
                                                  color: GymiesColors.darkBlue,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              _ReceiptRow(label: 'Betaald op', value: paidAt),
                                              _ReceiptRow(label: 'Methode', value: method),
                                              if (ref != '-') _ReceiptRow(label: 'Referentie', value: ref),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              r['amount'].toString(),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Icon(Icons.chevron_right, color: Colors.grey.shade500),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ],
                    ),
        ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? GymiesColors.darkBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(fontWeight: FontWeight.w500)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.fjallaOne(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

class _ViewModeTabs extends StatelessWidget {
  const _ViewModeTabs({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TabChip(
            label: 'Facturen',
            icon: Icons.receipt_long_rounded,
            isSelected: selected == 'invoices',
            onTap: () => onChanged('invoices'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TabChip(
            label: 'Sessies',
            icon: Icons.event_note_rounded,
            isSelected: selected == 'sessions',
            onTap: () => onChanged('sessions'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TabChip(
            label: 'Betaalbewijs',
            icon: Icons.verified_rounded,
            isSelected: selected == 'receipts',
            onTap: () => onChanged('receipts'),
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? GymiesColors.primary.withValues(alpha: 0.2)
          : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24,
                color: isSelected ? GymiesColors.darkBlue : Colors.grey.shade600,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? GymiesColors.darkBlue : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 6),
          ],
          Text(
            value,
            style: GoogleFonts.fjallaOne(fontSize: 22, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ],
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
        children: [
          const SizedBox(height: 72),
          const Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.fjallaOne(
              fontSize: 20,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
