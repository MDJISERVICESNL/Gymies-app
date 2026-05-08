


import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/haptics.dart';
import '../utils/safe_url_launcher.dart';
import '../models/booking.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/currency_format.dart';
import 'client_support_screen.dart';
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

  // ═══════════════════════════════════════════════════════════════════
  // DATA LOADING (ongewijzigd)
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _load() async {
    final api = context.read<GymiesApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Map<String, dynamic>> list = [];
      try {
        list = await api.getClientInvoices();
      } on ApiException catch (e) {
        // 404 = backend route nog niet beschikbaar → toon lege lijst
        if (e.statusCode == 404) {
          list = [];
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
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
        _error = S.of(context).konFacturenNietLaden;
        _loading = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS (ongewijzigd)
  // ═══════════════════════════════════════════════════════════════════

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _moneyFromAny(Map<String, dynamic> invoice) {
    final cents = _toInt(
      mapPick(invoice, ['total_cents', 'totalCents', 'amount_cents']),
    );
    if (cents != null) return formatEuro(cents);
    final amount = mapStr(invoice, ['total', 'amount']);
    return amount.isEmpty ? '-' : amount;
  }

  int _centsFromAny(Map<String, dynamic> invoice) {
    return _toInt(
      mapPick(invoice, ['total_cents', 'totalCents', 'amount_cents']),
    ) ?? 0;
  }

  String _status(Map<String, dynamic> invoice) {
    final raw = mapStr(invoice, [
      'status', 'payment_status', 'state',
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
    if (s == 'paid') return S.of(context).betaald;
    if (s == 'open') return 'Openstaand';
    if (s == 'unknown') return S.of(context).statusOnbekend;
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
      'number', 'invoice_number', S.of(context).trainerinvoicenumber, 'gymies_invoice_number',
    ]);
    final link = _invoiceLink(invoice);
    return isSent || sentAt.isNotEmpty || (number.isNotEmpty && link.isNotEmpty);
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
      'download_url', 'pdf_url', 'pdf_public_url', 'pdf_download_url',
      'invoice_pdf_url', 'invoice_url', 'payment_url', 'url',
    ]);
  }

  Map<String, dynamic>? _sentInvoiceForBooking(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return null;
    for (final invoice in _invoices) {
      final invoiceBookingId = mapStr(invoice, ['booking_id', 'bookingId']).trim();
      if (invoiceBookingId == id && _isSentInvoice(invoice)) return invoice;
    }
    return null;
  }

  Future<void> _requestInvoiceForBooking(Booking booking) async {
    final bookingId = booking.id.trim();
    if (bookingId.isEmpty) {
      _showError(S.of(context).boekingidOntbreekt);
      return;
    }
    if (_requestingInvoiceBookingIds.contains(bookingId)) return;
    setState(() => _requestingInvoiceBookingIds.add(bookingId));
    final trainerName = booking.trainerName.isEmpty ? S.of(context).trainer2 : booking.trainerName;
    final message =
        'Klant vraagt factuur aan voor booking $bookingId (${booking.scheduledAt.toIso8601String()}) bij $trainerName.';
    try {
      await context.read<GymiesApi>().requestInvoiceFromTrainer(
        bookingId: bookingId,
        message: message,
      );
      if (!mounted) return;
      _showSuccess(S.of(context).factuurverzoekVerstuurdNaarTrainer);
    } on ApiException {
      try {
        await context.read<GymiesApi>().createSupportTicket(
          type: 'invoice',
          subject: S.of(context).factuurverzoek,
          message: 'Ik wil graag een factuur voor sessie $bookingId bij $trainerName.',
          bookingId: bookingId,
        );
        if (!mounted) return;
        _showSuccess(S.of(context).factuurverzoekGeregistreerd);
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
      'reference': read(['payment_reference', 'reference', 'transaction_id', 'trx_id']),
      'booking_id': read(['booking_id', 'bookingId']),
      'referral_credit': read(['referral_credit', 'referral_credit_amount', 'referralDiscount', 'discount_referral']),
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
    if (link.isEmpty || _openingLink) return;
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
    setState(() => _openingLink = true);
    try {
      final launched = await SafeUrlLauncher.launchSafeUrl(context, uri.toString());
      if (!launched) _showError(S.of(context).konLinkNietOpenen);
    } catch (_) {
      _showError(S.of(context).konLinkNietOpenen);
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

  // ═══════════════════════════════════════════════════════════════════
  // INVOICE DETAIL BOTTOM SHEET (ongewijzigd)
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _showInvoiceDetail(Map<String, dynamic> invoice) async {
    final number =
        mapStr(invoice, [
          'number', 'invoice_number', S.of(context).trainerinvoicenumber, 'gymies_invoice_number',
        ]).isNotEmpty
        ? mapStr(invoice, [
            'number', 'invoice_number', S.of(context).trainerinvoicenumber, 'gymies_invoice_number',
          ])
        : S.of(context).factuur2;
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
          'paid_at': mapStr(loaded, ['paid_at', 'paidAt', 'payment_date', 'created_at']),
          'method': mapStr(loaded, ['payment_method', 'method']),
          'reference': mapStr(loaded, ['reference', 'transaction_id', 'trx_id']),
          'booking_id': mapStr(loaded, ['booking_id', 'bookingId']),
          'referral_credit': mapStr(loaded, ['referral_credit', 'referral_credit_amount', 'referral_discount']),
          'promo_code': mapStr(loaded, ['promo_code', 'code', 'coupon_code']),
          'amount': mapStr(loaded, ['amount', 'amount_label']).isEmpty
              ? amount
              : mapStr(loaded, ['amount', 'amount_label']),
        };
      } catch (e) {
        // Fail-open: Payment receipt retrieval optional, show available data
        if (kDebugMode) debugPrint('[ClientInvoices] Payment receipt fetch failed: $e');
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: GymiesColors.darkBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: GymiesColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          number,
                          style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
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
                    Text(S.of(context).betaalbewijs, style: GoogleFonts.sora(fontSize: 16, color: GymiesColors.darkBlue)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailRow(label: S.of(context).betaaldOp, value: receipt['paid_at'].toString().isEmpty ? '-' : receipt['paid_at']),
                          _DetailRow(label: 'Methode', value: receipt['method'].toString().isEmpty ? '-' : receipt['method']),
                          _DetailRow(label: 'Referentie', value: receipt['reference'].toString().isEmpty ? '-' : receipt['reference']),
                          if (receipt['booking_id'].toString().isNotEmpty)
                            _DetailRow(label: S.of(context).boekingid, value: receipt['booking_id'].toString()),
                          if (receipt['referral_credit'].toString().isNotEmpty)
                            _DetailRow(label: S.of(context).referraltegoed, value: receipt['referral_credit'].toString()),
                          if (receipt['promo_code'].toString().isNotEmpty)
                            _DetailRow(label: 'Promocode', value: receipt['promo_code'].toString()),
                        ],
                      ),
                    ),
                  ],
                  if (link.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(S.of(context).pdfDownloaden, style: GoogleFonts.sora(fontSize: 16, color: GymiesColors.darkBlue)),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).downloadDeFactuurDirectAlsPdfDeLinkKanNaVerloopVanTijdVerlopen,
                      style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openingLink ? null : () { Navigator.of(ctx).pop(); _openInvoiceLink(link); },
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text(S.of(context).downloadPdf),
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
                        label: const Text(S.of(context).kopieerLink),
                      ),
                    ),
                  ],
                  if (link.isEmpty) ...[
                    const SizedBox(height: 16),
                    Text(S.of(context).geenDownloadlinkBeschikbaar, style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // COMPUTED STATS
  // ═══════════════════════════════════════════════════════════════════

  String _totalPaid() {
    int cents = 0;
    for (final i in _invoices) {
      if (_isSentInvoice(i) && _status(i) == 'paid') {
        cents += _centsFromAny(i);
      }
    }
    if (cents == 0) return '\u20AC0';
    return '\u20AC${(cents / 100).toStringAsFixed(0)}';
  }

  String _totalOpen() {
    int cents = 0;
    for (final i in _invoices) {
      if (_isSentInvoice(i) && _status(i) == 'open') {
        cents += _centsFromAny(i);
      }
    }
    if (cents == 0) return '\u20AC0';
    return '\u20AC${(cents / 100).toStringAsFixed(0)}';
  }

  // ═══════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredInvoices();
    // ignore: unused_local_variable
    final sentInvoices = _invoices.where(_isSentInvoice).toList();
    final sessionRecords = _sessionRecords();
    final receipts = _receiptRecords();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: GymiesListBody(
          loading: _loading,
          error: _error,
          onRefresh: _load,
          child: (_invoices.isEmpty && _bookings.isEmpty)
              ? ListView(
                  children: [
                    _buildHeader(),
                    const _EmptyView(
                      title: S.of(context).nogGeenFacturen,
                      subtitle: S.of(context).naEenSessieKunJeHier,
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    // ── Navy header met stats ──
                    _buildHeader(),
                    const SizedBox(height: 16),

                    // ── View mode tabs ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ViewModeTabs(
                        selected: _viewMode,
                        onChanged: (v) => setState(() => _viewMode = v),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Content per view mode ──
                    if (_viewMode == 'invoices') ..._buildInvoicesList(filtered),
                    if (_viewMode == 'sessions') ..._buildSessionsList(sessionRecords),
                    if (_viewMode == 'receipts') ..._buildReceiptsList(receipts),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final sentInvoices = _invoices.where(_isSentInvoice).toList();
    return Container(
      decoration: BoxDecoration(
        color: GymiesColors.darkBlue,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        children: [
          // Terug + titel + support
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Haptics.selection();
                  Navigator.of(context).pop();
                },
                child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                S.of(context).mijnFacturen,
                style: GoogleFonts.sora(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Haptics.selection();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ClientSupportScreen()),
                  );
                },
                child: Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white.withOpacity(0.7),
                  size: 22,
                ),
              ),
            ],
          ),
          // Stats strip
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _HeaderStat(value: _totalPaid(), label: S.of(context).betaald),
                _HeaderStat(value: _totalOpen(), label: 'Openstaand'),
                _HeaderStat(value: '${sentInvoices.length}', label: S.of(context).facturen),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // INVOICES VIEW
  // ═══════════════════════════════════════════════════════════════════

  List<Widget> _buildInvoicesList(List<Map<String, dynamic>> filtered) {
    return [
      // Pill filters
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _FilterPill(label: S.of(context).allLabel, selected: _statusFilter == 'all', onTap: () {
              Haptics.light();
              setState(() => _statusFilter = 'all');
            }),
            const SizedBox(width: 6),
            _FilterPill(label: S.of(context).betaald, selected: _statusFilter == 'paid', onTap: () {
              Haptics.light();
              setState(() => _statusFilter = 'paid');
            }),
            const SizedBox(width: 6),
            _FilterPill(label: 'Openstaand', selected: _statusFilter == 'open', onTap: () {
              Haptics.light();
              setState(() => _statusFilter = 'open');
            }),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (filtered.isEmpty)
        const _EmptyView(
          title: S.of(context).geenFacturen,
          subtitle: S.of(context).facturenVerschijnenHierZodraJeTrainer,
        )
      else
        ...List.generate(filtered.length, (idx) {
          final invoice = filtered[idx];
          final number = mapStr(invoice, [
            'number', 'invoice_number', S.of(context).trainerinvoicenumber, 'gymies_invoice_number',
          ]).isNotEmpty
              ? mapStr(invoice, ['number', 'invoice_number', S.of(context).trainerinvoicenumber, 'gymies_invoice_number'])
              : S.of(context).factuur2;
          final date = mapStr(invoice, ['date', 'issued_at', 'created_at']);
          final status = _statusLabel(invoice);
          final amount = _moneyFromAny(invoice);

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 100 + (idx * 40)),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 16),
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    Haptics.light();
                    _showInvoiceDetail(invoice);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _statusColor(invoice).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.receipt_long_rounded,
                            color: _statusColor(invoice),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                number,
                                style: GoogleFonts.sora(
                                  fontSize: 14,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                date.isEmpty ? '-' : date,
                                style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              amount,
                              style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _statusColor(invoice).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status,
                                style: GoogleFonts.sora(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _statusColor(invoice),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════
  // SESSIONS VIEW
  // ═══════════════════════════════════════════════════════════════════

  List<Widget> _buildSessionsList(List<Booking> sessionRecords) {
    if (sessionRecords.isEmpty) {
      return [
        const _EmptyView(
          title: S.of(context).nogGeenSessies,
          subtitle: S.of(context).zodraEenSessieIsGeweestZie,
        ),
      ];
    }
    return List.generate(sessionRecords.length, (idx) {
      final b = sessionRecords[idx];
      final date =
          '${b.scheduledAt.day.toString().padLeft(2, '0')}-${b.scheduledAt.month.toString().padLeft(2, '0')}-${b.scheduledAt.year}';
      final time =
          '${b.scheduledAt.hour.toString().padLeft(2, '0')}:${b.scheduledAt.minute.toString().padLeft(2, '0')}';
      final amount = b.amountCents == null
          ? S.of(context).onbekendBedrag
          : formatEuro(b.amountCents);
      final sentInvoice = _sentInvoiceForBooking(b.id);
      final requestBusy = _requestingInvoiceBookingIds.contains(b.id);

      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 100 + (idx * 40)),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.event_note_rounded, color: GymiesColors.darkBlue, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.trainerName.isEmpty ? S.of(context).trainer : b.trainerName,
                          style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue),
                        ),
                        const SizedBox(height: 3),
                        Text('$date om $time', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 2),
                        Text(
                          sentInvoice == null ? S.of(context).factuurNogNietVerstuurd : S.of(context).factuurBeschikbaar,
                          style: GoogleFonts.sora(
                            fontSize: 11,
                            color: sentInvoice == null ? Colors.orange.shade700 : Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(amount, style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 6),
                      sentInvoice != null
                          ? FilledButton.icon(
                              onPressed: () {
                                Haptics.light();
                                _showInvoiceDetail(sentInvoice);
                              },
                              icon: const Icon(Icons.receipt_long_rounded, size: 16),
                              label: const Text(S.of(context).bekijk),
                              style: FilledButton.styleFrom(
                                backgroundColor: GymiesColors.primary,
                                foregroundColor: GymiesColors.darkBlue,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            )
                          : requestBusy
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : TextButton(
                                  onPressed: () {
                                Haptics.light();
                                _requestInvoiceForBooking(b);
                              },
                                  child: const Text(S.of(context).vraagAan),
                                ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // RECEIPTS VIEW
  // ═══════════════════════════════════════════════════════════════════

  List<Widget> _buildReceiptsList(List<Map<String, dynamic>> receipts) {
    if (receipts.isEmpty) {
      return [
        const _EmptyView(
          title: S.of(context).nogGeenBetaalbewijzen,
          subtitle: S.of(context).betaaldeFacturenVerschijnenHierMetBetaalmethode,
        ),
      ];
    }
    return List.generate(receipts.length, (idx) {
      final r = receipts[idx];
      final invoice = (r['invoice'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final number = mapStr(invoice, [
        'number', 'invoice_number', S.of(context).trainerinvoicenumber, 'gymies_invoice_number',
      ]).isEmpty
          ? S.of(context).factuur2
          : mapStr(invoice, ['number', 'invoice_number', S.of(context).trainerinvoicenumber, 'gymies_invoice_number']);
      final paidAt = r['paid_at'].toString().isEmpty ? '-' : r['paid_at'];
      final method = r['method'].toString().isEmpty ? '-' : r['method'];
      final ref = r['reference'].toString().isEmpty ? '-' : r['reference'];

      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 100 + (idx * 40)),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              onTap: () {
                Haptics.light();
                _showInvoiceDetail(invoice);
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.verified_rounded, color: Colors.green.shade700, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(number, style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue)),
                          const SizedBox(height: 4),
                          _ReceiptRow(label: S.of(context).betaaldOp, value: paidAt),
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
                          style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.green.shade700),
                        ),
                        const SizedBox(height: 4),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: GymiesColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.sora(fontSize: 11, color: Colors.white.withOpacity(0.55)),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? GymiesColors.darkBlue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
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
        Expanded(child: _TabChip(label: S.of(context).facturen, icon: Icons.receipt_long_rounded, isSelected: selected == 'invoices', onTap: () => onChanged('invoices'))),
        const SizedBox(width: 8),
        Expanded(child: _TabChip(label: S.of(context).sessionsCountLabel, icon: Icons.event_note_rounded, isSelected: selected == 'sessions', onTap: () => onChanged('sessions'))),
        const SizedBox(width: 8),
        Expanded(child: _TabChip(label: 'Bewijzen', icon: Icons.verified_rounded, isSelected: selected == 'receipts', onTap: () => onChanged('receipts'))),
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
          ? GymiesColors.primary.withOpacity(0.2)
          : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, size: 22, color: isSelected ? GymiesColors.darkBlue : Colors.grey.shade600),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 11,
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});
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
            child: Text(label, style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? GymiesColors.darkBlue),
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
          style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade700),
          children: [
            TextSpan(text: '$label: ', style: GoogleFonts.sora(fontWeight: FontWeight.w500)),
            TextSpan(text: value),
          ],
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
        children: [
          const SizedBox(height: 72),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.receipt_long_rounded, size: 32, color: GymiesColors.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
