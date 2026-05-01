import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/action_retry_queue_service.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';

// Navigatie-schermen (alleen schermen die daadwerkelijk bestaan)
import 'client_sessions_screen.dart';
import 'client_invoices_screen.dart';
import 'client_profile_screen.dart';
import 'client_settings_screen.dart';
import 'client_notifications_screen.dart';
import 'client_dossier_screen.dart';
import 'client_group_sessions_screen.dart';
import 'client_waitlist_screen.dart';
import 'client_favorites_standalone_screen.dart';

// FAQ data
import 'support_faq_data.dart';

// ═══════════════════════════════════════════════════════════════════════
//  CLIENT SUPPORT SCREEN – Help Center + Tickets
// ═══════════════════════════════════════════════════════════════════════

class ClientSupportScreen extends StatefulWidget {
  const ClientSupportScreen({
    super.key,
    this.initialType,
    this.initialSubject,
    this.initialMessage,
    this.initialBookingId,
    this.initialInvoiceId,
    this.openComposerOnStart = false,
  });

  final String? initialType;
  final String? initialSubject;
  final String? initialMessage;
  final String? initialBookingId;
  final String? initialInvoiceId;
  final bool openComposerOnStart;

  @override
  State<ClientSupportScreen> createState() => _ClientSupportScreenState();
}

class _ClientSupportScreenState extends State<ClientSupportScreen>
    with SingleTickerProviderStateMixin {
  // ── Draft keys ──
  static const _kDraftType = 'support_draft_type';
  static const _kDraftSubject = 'support_draft_subject';
  static const _kDraftMessage = 'support_draft_message';
  static const _kDraftBookingId = 'support_draft_booking_id';
  static const _kDraftInvoiceId = 'support_draft_invoice_id';

  // ── State ──
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = [];
  Map<String, String>? _lastFailedTicketPayload;
  bool _submittingTicket = false;
  late TabController _tabController;
  String _searchQuery = '';

  static const _ticketTypes = <String>{
    'booking',
    'invoice',
    'check_in',
    'payment',
    'dispute',
    'incident',
    'other',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
    if (widget.openComposerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openNewTicketSheet(
          initialType: widget.initialType,
          initialSubject: widget.initialSubject,
          initialMessage: widget.initialMessage,
          initialBookingId: widget.initialBookingId,
          initialInvoiceId: widget.initialInvoiceId,
        );
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  //  API / Data
  // ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<GymiesApi>().getSupportTickets();
      if (!mounted) return;
      setState(() {
        _tickets = [...list]
          ..sort((a, b) => _ticketCreatedAt(b).compareTo(_ticketCreatedAt(a)));
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
        _error = 'Kon supporttickets niet laden.';
        _loading = false;
      });
    }
  }

  // ── Helpers ──

  String _str(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final v = map[key];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return '';
  }

  String _statusLabel(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('open') || s.contains('new')) return 'Open';
    if (s.contains('pending') || s.contains('waiting')) return 'In behandeling';
    if (s.contains('resolved') || s.contains('closed') || s.contains('done')) {
      return 'Afgerond';
    }
    return raw.isEmpty ? 'Onbekend' : raw;
  }

  Color _statusColor(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('resolved') || s.contains('closed') || s.contains('done')) {
      return Colors.green.shade700;
    }
    if (s.contains('pending') || s.contains('waiting')) {
      return Colors.orange.shade800;
    }
    return Colors.blueGrey.shade700;
  }

  Color _statusBgColor(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('resolved') || s.contains('closed') || s.contains('done')) {
      return Colors.green.shade50;
    }
    if (s.contains('pending') || s.contains('waiting')) {
      return Colors.orange.shade50;
    }
    return Colors.amber.shade50;
  }

  String _ticketId(Map<String, dynamic> ticket) {
    return _str(ticket, ['id', 'ticket_id', 'ticketId']);
  }

  DateTime _ticketCreatedAt(Map<String, dynamic> ticket) {
    final raw = _str(ticket, ['created_at', 'createdAt', 'date']).trim();
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _ticketTrainerContext(Map<String, dynamic> ticket) {
    final trainerName = _str(ticket, [
      'trainer_name',
      'trainerName',
      'coach_name',
      'coachName',
    ]).trim();
    final bookingId = _str(ticket, ['booking_id', 'bookingId']).trim();
    if (trainerName.isNotEmpty) {
      return bookingId.isNotEmpty
          ? 'Trainer: $trainerName · Boeking $bookingId'
          : 'Trainer: $trainerName';
    }
    if (bookingId.isNotEmpty) {
      return 'Boeking $bookingId';
    }
    return '';
  }

  String _ticketTypeLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'booking':
        return 'Boeking';
      case 'invoice':
        return 'Factuur';
      case 'check_in':
        return 'Check-in';
      case 'payment':
        return 'Betaling';
      case 'dispute':
        return 'Geschil';
      case 'incident':
        return 'Incident';
      default:
        return raw.isEmpty ? 'Overig' : raw;
    }
  }

  String _composeInitialTicketMessage(Map<String, dynamic> ticket) {
    final type = _ticketTypeLabel(
      _str(ticket, ['type', 'category', 'ticket_type']),
    );
    final subject = _str(ticket, ['subject', 'title', 'name']);
    final message = _str(ticket, ['message', 'body', 'description']);
    final bookingId = _str(ticket, ['booking_id', 'bookingId']);
    final invoiceId = _str(ticket, ['invoice_id', 'invoiceId']);
    final parts = <String>[
      if (subject.isNotEmpty) 'Onderwerp: $subject',
      'Type: $type',
      if (bookingId.isNotEmpty) 'Boeking-ID: $bookingId',
      if (invoiceId.isNotEmpty) 'Factuur-ID: $invoiceId',
      '',
      if (message.isNotEmpty) message else 'Geen aanvullende omschrijving.',
    ];
    return parts.join('\n');
  }

  int get _openTicketCount =>
      _tickets.where((t) {
        final s = _str(t, ['status', 'state']).toLowerCase();
        return !s.contains('resolved') &&
            !s.contains('closed') &&
            !s.contains('done');
      }).length;

  // ─────────────────────────────────────────────────────────────────
  //  Navigation helper – vertaalt route-keys naar echte schermen
  // ─────────────────────────────────────────────────────────────────

  void _navigateToRoute(String? route) {
    if (route == null || route.isEmpty) return;

    Widget? target;
    switch (route) {
      case 'sessions':
        target = const ClientSessionsScreen();
        break;
      case 'invoices':
        target = const ClientInvoicesScreen();
        break;
      case 'profile':
        target = const ClientProfileScreen();
        break;
      case 'settings':
        target = const ClientSettingsScreen();
        break;
      case 'notifications':
        target = const ClientNotificationsScreen();
        break;
      case 'dossier':
        target = const ClientDossierScreen();
        break;
      case 'group_sessions':
        target = const ClientGroupSessionsScreen();
        break;
      case 'waitlist':
        target = const ClientWaitlistScreen();
        break;
      case 'favorites':
        target = const ClientFavoritesStandaloneScreen();
        break;
      case 'new_ticket':
        _openNewTicketSheet();
        return;
      default:
        return;
    }

    if (target != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => target!),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────
  //  Ticket thread opener
  // ─────────────────────────────────────────────────────────────────

  Future<void> _openSupportThread(Map<String, dynamic> ticket) async {
    final id = _ticketId(ticket);
    Map<String, dynamic> detail = ticket;
    if (id.isNotEmpty) {
      try {
        final loaded = await context.read<GymiesApi>().getSupportTicketDetail(
          id,
        );
        if (loaded.isNotEmpty) detail = loaded;
      } catch (_) {}
    }
    if (!mounted) return;
    final user = context.read<AuthService>().user;
    final currentUserId =
        ((user?['id'] ?? user?['user_id'] ?? user?['userId']) ?? '')
            .toString()
            .trim();
    final currentUserName =
        ((user?['display_name'] ??
                    user?['name'] ??
                    user?['first_name'] ??
                    user?['email']) ??
                'Jij')
            .toString()
            .trim();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SupportThreadScreen(
          ticket: detail,
          composedInitialMessage: _composeInitialTicketMessage(ticket),
          ticketId: id,
          statusLabel: _statusLabel(_str(ticket, ['status', 'state'])),
          currentUserId: currentUserId,
          currentUserName: currentUserName.isEmpty ? 'Jij' : currentUserName,
        ),
      ),
    );
    // Refresh na terugkeer
    _load();
  }

  // ─────────────────────────────────────────────────────────────────
  //  New ticket bottom sheet
  // ─────────────────────────────────────────────────────────────────

  Future<void> _openNewTicketSheet({
    String? initialType,
    String? initialSubject,
    String? initialMessage,
    String? initialBookingId,
    String? initialInvoiceId,
  }) async {
    final formKey = GlobalKey<FormState>();
    final draft = await _loadDraft();
    if (!mounted) return;

    String type = (initialType ?? '').trim().isNotEmpty
        ? initialType!.trim()
        : (draft['type'] ?? 'booking');
    if (!_ticketTypes.contains(type)) type = 'other';

    final subjectCtrl = TextEditingController(
      text: (initialSubject ?? '').trim().isNotEmpty
          ? initialSubject!.trim()
          : (draft['subject'] ?? ''),
    );
    final messageCtrl = TextEditingController(
      text: (initialMessage ?? '').trim().isNotEmpty
          ? initialMessage!.trim()
          : (draft['message'] ?? ''),
    );
    final bookingIdCtrl = TextEditingController(
      text: (initialBookingId ?? '').trim().isNotEmpty
          ? initialBookingId!.trim()
          : (draft['booking_id'] ?? ''),
    );
    final invoiceIdCtrl = TextEditingController(
      text: (initialInvoiceId ?? '').trim().isNotEmpty
          ? initialInvoiceId!.trim()
          : (draft['invoice_id'] ?? ''),
    );

    final typeLabels = <String, String>{
      'booking': 'Boeking',
      'invoice': 'Factuur',
      'check_in': 'Check-in',
      'payment': 'Betaling',
      'dispute': 'Geschil',
      'incident': 'Incident',
      'other': 'Overig',
    };

    final submit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.9,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Drag handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Text(
                            'Nieuw supportverzoek',
                            style: GoogleFonts.fjallaOne(
                              fontSize: 22,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Beschrijf je probleem zo duidelijk mogelijk',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Info banner
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: Colors.blue.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 16, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Support blijft gekoppeld aan de trainer/sessie-context van je verzoek.',
                                    style: TextStyle(
                                      color: Colors.blue.shade900,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Type chips
                          Text(
                            'Type',
                            style: TextStyle(
                              color: GymiesColors.darkBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: typeLabels.entries.map((e) {
                              final isSelected = type == e.key;
                              return GestureDetector(
                                onTap: () {
                                  setSheetState(() => type = e.key);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? GymiesColors.primary
                                            .withValues(alpha: 0.15)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? GymiesColors.primary
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    e.value,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? GymiesColors.darkBlue
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          // Subject
                          TextFormField(
                            controller: subjectCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Onderwerp',
                              hintText: 'Korte samenvatting',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().length < 4)
                                    ? 'Minimaal 4 tekens'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          // Message
                          TextFormField(
                            controller: messageCtrl,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Bericht',
                              hintText:
                                  'Beschrijf het probleem zo duidelijk mogelijk',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().length < 10)
                                    ? 'Minimaal 10 tekens'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          // Optional IDs
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: bookingIdCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Boeking-ID',
                                    hintText: 'Optioneel',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: invoiceIdCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Factuur-ID',
                                    hintText: 'Optioneel',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          // Submit
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                if (!(formKey.currentState?.validate() ??
                                    false)) return;
                                _saveDraft(
                                  type: type,
                                  subject: subjectCtrl.text.trim(),
                                  message: messageCtrl.text.trim(),
                                  bookingId: bookingIdCtrl.text.trim(),
                                  invoiceId: invoiceIdCtrl.text.trim(),
                                );
                                Navigator.of(ctx).pop(true);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: GymiesColors.primary,
                                foregroundColor: GymiesColors.darkBlue,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.send_rounded, size: 18),
                              label: Text(
                                'Verstuur verzoek',
                                style: GoogleFonts.fjallaOne(fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (submit != true || !mounted || _submittingTicket) return;
    setState(() => _submittingTicket = true);

    try {
      await context.read<GymiesApi>().createSupportTicket(
        type: type,
        subject: subjectCtrl.text.trim(),
        message: messageCtrl.text.trim(),
        bookingId: bookingIdCtrl.text.trim(),
        invoiceId: invoiceIdCtrl.text.trim(),
      );
      await ActionRetryQueueService.log(
        actionType: 'support_ticket',
        status: 'sent',
        payload: {
          'type': type,
          'subject': subjectCtrl.text.trim(),
          'message': messageCtrl.text.trim(),
          'booking_id': bookingIdCtrl.text.trim(),
          'invoice_id': invoiceIdCtrl.text.trim(),
        },
        detail: 'Direct gelukt',
      );
      _lastFailedTicketPayload = null;
      await _clearDraft();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Supportverzoek aangemaakt!'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Switch naar tickets tab
      _tabController.animateTo(1);
      await _load();
    } on ApiException catch (e) {
      _lastFailedTicketPayload = {
        'type': type,
        'subject': subjectCtrl.text.trim(),
        'message': messageCtrl.text.trim(),
        'booking_id': bookingIdCtrl.text.trim(),
        'invoice_id': invoiceIdCtrl.text.trim(),
      };
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      _lastFailedTicketPayload = {
        'type': type,
        'subject': subjectCtrl.text.trim(),
        'message': messageCtrl.text.trim(),
        'booking_id': bookingIdCtrl.text.trim(),
        'invoice_id': invoiceIdCtrl.text.trim(),
      };
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supportverzoek mislukt'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submittingTicket = false);
    }
  }

  // ── Draft persistence ──

  Future<Map<String, String>> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'type': prefs.getString(_kDraftType) ?? '',
      'subject': prefs.getString(_kDraftSubject) ?? '',
      'message': prefs.getString(_kDraftMessage) ?? '',
      'booking_id': prefs.getString(_kDraftBookingId) ?? '',
      'invoice_id': prefs.getString(_kDraftInvoiceId) ?? '',
    };
  }

  Future<void> _saveDraft({
    required String type,
    required String subject,
    required String message,
    required String bookingId,
    required String invoiceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDraftType, type);
    await prefs.setString(_kDraftSubject, subject);
    await prefs.setString(_kDraftMessage, message);
    await prefs.setString(_kDraftBookingId, bookingId);
    await prefs.setString(_kDraftInvoiceId, invoiceId);
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDraftType);
    await prefs.remove(_kDraftSubject);
    await prefs.remove(_kDraftMessage);
    await prefs.remove(_kDraftBookingId);
    await prefs.remove(_kDraftInvoiceId);
  }

  Future<void> _retryLastFailedTicket() async {
    final payload = _lastFailedTicketPayload;
    if (payload == null) return;
    try {
      await context.read<GymiesApi>().createSupportTicket(
        type: payload['type'] ?? 'booking',
        subject: payload['subject'] ?? '',
        message: payload['message'] ?? '',
        bookingId: payload['booking_id'],
        invoiceId: payload['invoice_id'],
      );
      _lastFailedTicketPayload = null;
      await _clearDraft();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Laatste supportverzoek alsnog verstuurd'),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final openCount = _openTicketCount;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // ── AppBar ──
          SliverAppBar(
            backgroundColor: GymiesColors.darkBlue,
            foregroundColor: GymiesColors.primary,
            pinned: true,
            expandedHeight: 200,
            title: Text('Support',
                style: GoogleFonts.fjallaOne(fontSize: 20)),
            actions: [
              if (openCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _tabController.animateTo(1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_rounded,
                            size: 20, color: GymiesColors.primary),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$openCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  color: GymiesColors.darkBlue,
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hoe kunnen we je helpen?',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 24,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Zoek een antwoord of neem contact op',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Zoekbalk
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: TextField(
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Zoek op onderwerp...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: (v) =>
                                setState(() => _searchQuery = v.trim()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: GymiesColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  labelColor: GymiesColors.darkBlue,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  dividerColor: Colors.transparent,
                  padding: const EdgeInsets.all(3),
                  tabs: [
                    const Tab(text: 'Help Center'),
                    Tab(
                      text:
                          'Mijn Tickets${openCount > 0 ? ' ($openCount)' : ''}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildHelpCenterTab(),
            _buildTicketsTab(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  TAB 1 – Help Center (FAQ's + Categorieën)
  // ─────────────────────────────────────────────────────────────────

  Widget _buildHelpCenterTab() {
    // Filter categorieën op zoekquery
    final query = _searchQuery.toLowerCase();
    final filteredCategories = query.isEmpty
        ? supportFaqCategories
        : supportFaqCategories.where((cat) {
            if (cat.label.toLowerCase().contains(query)) return true;
            if (cat.description.toLowerCase().contains(query)) return true;
            return cat.items.any(
              (item) =>
                  item.question.toLowerCase().contains(query) ||
                  item.answer.toLowerCase().contains(query),
            );
          }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Categorieën grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.15,
          ),
          itemCount: filteredCategories.length,
          itemBuilder: (context, index) {
            final cat = filteredCategories[index];
            return _CategoryCard(
              category: cat,
              onTap: () => _openCategoryScreen(cat),
            );
          },
        ),
        const SizedBox(height: 20),
        // CTA – contact opnemen
        _ContactCTA(onTap: () => _openNewTicketSheet()),
        const SizedBox(height: 8),
        // Reactietijd hint
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_rounded,
                size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              'Gemiddelde reactietijd: ~2 uur',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openCategoryScreen(FaqCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FaqCategoryScreen(
          category: category,
          onNavigateToRoute: _navigateToRoute,
          onNewTicket: () => _openNewTicketSheet(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  TAB 2 – Mijn Tickets
  // ─────────────────────────────────────────────────────────────────

  Widget _buildTicketsTab() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Opnieuw proberen'),
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.darkBlue,
                foregroundColor: GymiesColors.primary,
              ),
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Retry banner
          if (_lastFailedTicketPayload != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verzoek niet verstuurd',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Controleer je internet en probeer opnieuw.',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _retryLastFailedTicket,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade900,
                      side: BorderSide(color: Colors.orange.shade400),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                    child: const Text('Opnieuw', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Empty state
          if (_tickets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Icon(Icons.mail_outline_rounded,
                      size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'Nog geen supportverzoeken',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hier verschijnen je tickets wanneer\nje contact opneemt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
          else
            // Ticket list
            ..._tickets.map((t) => _TicketCard(
                  ticket: t,
                  str: _str,
                  statusLabel: _statusLabel,
                  statusColor: _statusColor,
                  statusBgColor: _statusBgColor,
                  ticketTypeLabel: _ticketTypeLabel,
                  trainerContext: _ticketTrainerContext,
                  onTap: () => _openSupportThread(t),
                )),

          const SizedBox(height: 12),
          // New ticket button
          GestureDetector(
            onTap: () => _openNewTicketSheet(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: GymiesColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: GymiesColors.primary,
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded,
                      color: GymiesColors.darkBlue, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Nieuw verzoek aanmaken',
                    style: TextStyle(
                      color: GymiesColors.darkBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});
  final FaqCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(category.icon,
                    color: GymiesColors.darkBlue, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                category.label,
                style: GoogleFonts.fjallaOne(
                  fontSize: 15,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                category.description,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${category.items.length} artikelen',
                  style: TextStyle(
                    color: GymiesColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactCTA extends StatelessWidget {
  const _ContactCTA({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GymiesColors.primary,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: GymiesColors.primary.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kom je er niet uit?',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 16,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Start een gesprek met ons team',
                      style: TextStyle(
                        color: GymiesColors.darkBlue.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GymiesColors.darkBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(Icons.chat_rounded, color: GymiesColors.primary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.str,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBgColor,
    required this.ticketTypeLabel,
    required this.trainerContext,
    required this.onTap,
  });

  final Map<String, dynamic> ticket;
  final String Function(Map<String, dynamic>, List<String>) str;
  final String Function(String) statusLabel;
  final Color Function(String) statusColor;
  final Color Function(String) statusBgColor;
  final String Function(String) ticketTypeLabel;
  final String Function(Map<String, dynamic>) trainerContext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subject = str(ticket, ['subject', 'title', 'name']);
    final statusRaw = str(ticket, ['status', 'state']);
    final typeRaw = str(ticket, ['type', 'category', 'ticket_type']);
    final created = str(ticket, ['created_at', 'createdAt', 'date']);
    final tContext = trainerContext(ticket);
    final message = str(ticket, ['message', 'body', 'description']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subject.isEmpty ? 'Supportverzoek' : subject,
                        style: TextStyle(
                          color: GymiesColors.darkBlue,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBgColor(statusRaw),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel(statusRaw),
                        style: TextStyle(
                          color: statusColor(statusRaw),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (typeRaw.isNotEmpty)
                      Text(
                        ticketTypeLabel(typeRaw),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    if (typeRaw.isNotEmpty && created.isNotEmpty)
                      Text(' · ',
                          style: TextStyle(color: Colors.grey.shade400)),
                    if (created.isNotEmpty)
                      Text(
                        created.length > 10
                            ? created.substring(0, 10)
                            : created,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                if (tContext.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    tContext,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      height: 1.4,
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
}

// ═══════════════════════════════════════════════════════════════════════
//  FAQ CATEGORY SCREEN
// ═══════════════════════════════════════════════════════════════════════

class _FaqCategoryScreen extends StatefulWidget {
  const _FaqCategoryScreen({
    required this.category,
    required this.onNavigateToRoute,
    required this.onNewTicket,
  });

  final FaqCategory category;
  final void Function(String?) onNavigateToRoute;
  final VoidCallback onNewTicket;

  @override
  State<_FaqCategoryScreen> createState() => _FaqCategoryScreenState();
}

class _FaqCategoryScreenState extends State<_FaqCategoryScreen> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final items = widget.category.items;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        title: Text('Support', style: GoogleFonts.fjallaOne(fontSize: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(0),
        children: [
          // Category header
          Container(
            color: GymiesColors.darkBlue,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.category.icon,
                      color: GymiesColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.category.label,
                      style: GoogleFonts.fjallaOne(
                        fontSize: 20,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${items.length} veelgestelde vragen',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // FAQ items
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(items.length, (i) {
                final item = items[i];
                final isExpanded = _expandedIndex == i;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isExpanded
                          ? GymiesColors.primary
                          : Colors.grey.shade200,
                    ),
                    boxShadow: isExpanded
                        ? [
                            BoxShadow(
                              color:
                                  GymiesColors.primary.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => setState(() {
                          _expandedIndex = isExpanded ? null : i;
                        }),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.question,
                                  style: TextStyle(
                                    color: GymiesColors.darkBlue,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              AnimatedRotation(
                                turns: isExpanded ? 0.25 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.grey.shade400,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              Text(
                                item.answer,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                              if (item.actionLabel != null) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      // Pop terug naar support, dan navigeer
                                      Navigator.of(context).pop();
                                      widget.onNavigateToRoute(
                                          item.actionRoute);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: GymiesColors.darkBlue,
                                      side: BorderSide(
                                        color: GymiesColors.primary
                                            .withValues(alpha: 0.5),
                                      ),
                                      backgroundColor: GymiesColors.primary
                                          .withValues(alpha: 0.1),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                    ),
                                    child: Text(
                                      '${item.actionLabel} →',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),

          // Still need help
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onNewTicket();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Niet gevonden wat je zocht?',
                              style: TextStyle(
                                color: GymiesColors.darkBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stuur ons een bericht',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: GymiesColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Contact',
                          style: TextStyle(
                            color: GymiesColors.darkBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SUPPORT THREAD SCREEN (chat view – behouden van origineel)
// ═══════════════════════════════════════════════════════════════════════

class _SupportThreadScreen extends StatefulWidget {
  const _SupportThreadScreen({
    required this.ticket,
    required this.composedInitialMessage,
    required this.ticketId,
    required this.statusLabel,
    required this.currentUserId,
    required this.currentUserName,
  });

  final Map<String, dynamic> ticket;
  final String composedInitialMessage;
  final String ticketId;
  final String statusLabel;
  final String currentUserId;
  final String currentUserName;

  @override
  State<_SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<_SupportThreadScreen> {
  final TextEditingController _replyController = TextEditingController();
  bool _loading = false;
  bool _sending = false;
  late Map<String, dynamic> _ticket;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _refreshTicket(silent: true);
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  String _str(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final v = map[key];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return '';
  }

  DateTime _dateFrom(dynamic raw) {
    if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(raw.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<Map<String, dynamic>> _messages() {
    final raw = _ticket['messages'] ?? _ticket['replies'] ?? _ticket['items'];
    final messages = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          messages.add(item);
        } else if (item is Map) {
          messages.add(Map<String, dynamic>.from(item));
        }
      }
    }
    messages.sort(
      (a, b) => _dateFrom(a['created_at'] ?? a['createdAt'])
          .compareTo(_dateFrom(b['created_at'] ?? b['createdAt'])),
    );
    return messages;
  }

  bool _ticketClosed() {
    final rawStatus = _str(_ticket, ['status', 'state']);
    final s = rawStatus.toLowerCase();
    return s.contains('resolved') ||
        s.contains('closed') ||
        s.contains('done') ||
        widget.statusLabel.toLowerCase().contains('afgerond');
  }

  String _timeLabel(dynamic raw) {
    final dt = _dateFrom(raw);
    if (dt.millisecondsSinceEpoch == 0) return '';
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _receiptLabel(Map<String, dynamic> message, {required bool mine}) {
    final readAt = _str(message, ['read_at', 'readAt', 'seen_at', 'seenAt']);
    if (mine && readAt.trim().isNotEmpty) {
      return 'Gelezen ${_timeLabel(readAt)}'.trim();
    }
    final delivered = _str(message, [
      'delivered_at', 'deliveredAt', 'sent_at', 'sentAt',
    ]);
    if (mine && delivered.trim().isNotEmpty) {
      return 'Verzonden ${_timeLabel(delivered)}'.trim();
    }
    if (mine) return 'Niet gelezen';
    final created = _str(message, ['created_at', 'createdAt']);
    return _timeLabel(created);
  }

  bool _mineFromMessage(Map<String, dynamic> m) {
    final explicitMine = m['is_mine'] ?? m['mine'] ?? m['isMine'];
    if (explicitMine == true || explicitMine == 1 || explicitMine == '1') {
      return true;
    }
    final senderId = _str(m, [
      'user_id', 'sender_id', 'author_id', 'from_user_id', 'fromUserId',
    ]);
    if (widget.currentUserId.isNotEmpty &&
        senderId.isNotEmpty &&
        senderId == widget.currentUserId) {
      return true;
    }
    final author = _str(m, [
      'author', 'sender', 'from', 'role', 'sender_type',
    ]).toLowerCase();
    final supportLike = author.contains('support') ||
        author.contains('gymies') ||
        author.contains('admin') ||
        author.contains('team');
    if (supportLike) return false;
    return author.contains('trainer') ||
        author.contains('client') ||
        author.contains('user') ||
        author.contains('requester') ||
        author.contains('owner') ||
        author == 'me';
  }

  Future<void> _refreshTicket({bool silent = false}) async {
    if (widget.ticketId.trim().isEmpty) return;
    if (!silent) setState(() => _loading = true);
    try {
      final detail = await context.read<GymiesApi>().getSupportTicketDetail(
        widget.ticketId,
      );
      if (!mounted) return;
      if (detail.isNotEmpty) setState(() => _ticket = detail);
    } catch (_) {
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sending || widget.ticketId.trim().isEmpty) return;
    if (_ticketClosed()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ticket is afgerond en kan niet meer worden beantwoord.'),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<GymiesApi>().sendSupportTicketReply(
        ticketId: widget.ticketId,
        message: text,
      );
      if (!mounted) return;
      _replyController.clear();
      await _refreshTicket();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reactie verstuurd')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages();
    final created = _str(_ticket, ['created_at', 'createdAt', 'date']);
    final effectiveStatus = _str(_ticket, ['status', 'state']).isNotEmpty
        ? _str(_ticket, ['status', 'state'])
        : widget.statusLabel;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        title: Text('Support', style: GoogleFonts.fjallaOne(fontSize: 20)),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refreshTicket,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Ververs thread',
          ),
        ],
      ),
      body: Column(
        children: [
          // Ticket header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: GymiesColors.darkBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _str(_ticket, ['subject', 'title', 'name']).isEmpty
                            ? 'Ticket ${widget.ticketId}'
                            : _str(_ticket, ['subject', 'title', 'name']),
                        style: GoogleFonts.fjallaOne(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        effectiveStatus.isNotEmpty
                            ? effectiveStatus
                            : widget.statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (created.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${widget.ticketId.isNotEmpty ? '${widget.ticketId} · ' : ''}$created',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Messages
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              children: [
                // Initial message bubble
                _SupportBubble(
                  mine: true,
                  title: widget.currentUserName,
                  body: widget.composedInitialMessage,
                  meta: created.isEmpty ? null : _timeLabel(created),
                ),
                if (messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nog geen reactie. We pakken je verzoek zo snel mogelijk op.',
                              style: TextStyle(
                                color: Colors.blue.shade900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...messages.map((m) {
                    final body = _str(m, ['message', 'body', 'text', 'content']);
                    final mine = _mineFromMessage(m);
                    final title = mine ? widget.currentUserName : 'GYMIES Support';
                    return _SupportBubble(
                      mine: mine,
                      title: title,
                      body: body.isEmpty ? '-' : body,
                      meta: _receiptLabel(m, mine: mine),
                    );
                  }),

                if (_ticketClosed())
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: Colors.green.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Dit ticket is opgelost',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Reply bar
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_ticketClosed() && !_sending,
                      decoration: InputDecoration(
                        hintText: _ticketClosed()
                            ? 'Ticket is afgerond'
                            : 'Typ je reactie...',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendReply(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        (_ticketClosed() || _sending) ? null : _sendReply,
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportBubble extends StatelessWidget {
  const _SupportBubble({
    required this.mine,
    required this.title,
    required this.body,
    this.meta,
  });

  final bool mine;
  final String title;
  final String body;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: mine ? GymiesColors.darkBlue : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          border: mine ? null : Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!mine) ...[
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: mine ? GymiesColors.primary : GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                color: mine ? Colors.white : GymiesColors.darkBlue,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if ((meta ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                meta!.trim(),
                style: TextStyle(
                  fontSize: 11,
                  color: mine ? Colors.white70 : Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
