import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/action_retry_queue_service.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';

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

  static const _ticketTypes = <String>{
    'booking',
    'invoice',
    'check_in',
    'payment',
    'dispute',
    'incident',
    'other',
  };

  late GymiesApi _api;
  bool _didFirstLoad = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<GymiesApi>();
    if (!_didFirstLoad) {
      _didFirstLoad = true;
      _load();
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
      List<Map<String, dynamic>> list = [];
      try {
        list = await _api.getSupportTickets();
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          list = [];
        } else {
          rethrow;
        }
      }
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
    return _strHelper(ticket, ['id', 'ticket_id', 'ticketId']);
  }

  DateTime _ticketCreatedAt(Map<String, dynamic> ticket) {
    final raw = _strHelper(ticket, ['created_at', 'createdAt', 'date']).trim();
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _ticketTrainerContext(Map<String, dynamic> ticket) {
    final trainerName = _strHelper(ticket, [
      'trainer_name',
      'trainerName',
      'coach_name',
      'coachName',
    ]).trim();
    final bookingId = _strHelper(ticket, ['booking_id', 'bookingId']).trim();
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
    final message = _strHelper(ticket, ['message', 'body', 'description']);
    if (message.isNotEmpty) return message;
    return 'Nieuw supportverzoek aangemaakt.';
  }

  int get _openTicketCount =>
      _tickets.where((t) {
        final s = _strHelper(t, ['status', 'state']).toLowerCase();
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
        final loaded = await _api.getSupportTicketDetail(
          id,
        );
        if (loaded.isNotEmpty) detail = loaded;
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Kon ticket niet laden',
              style: GoogleFonts.sora(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Kon ticket niet laden',
              style: GoogleFonts.sora(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
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
          statusLabel: _statusLabel(_strHelper(ticket, ['status', 'state'])),
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

    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.8,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                                child: Icon(Icons.mail_outline_rounded, color: GymiesColors.primary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Nieuw supportverzoek',
                                      style: GoogleFonts.sora(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: GymiesColors.darkBlue,
                                      ),
                                    ),
                                    Text(
                                      'Beschrijf je probleem zo duidelijk mogelijk',
                                      style: GoogleFonts.sora(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                icon: const Icon(Icons.close_rounded),
                                iconSize: 20,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Info banner
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 16, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Support blijft gekoppeld aan de trainer/sessie-context van je verzoek.',
                                    style: GoogleFonts.sora(
                                      color: Colors.blue.shade900,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Type chips
                          Text(
                            'Type',
                            style: GoogleFonts.sora(
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
                                    style: GoogleFonts.sora(
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
                                style: GoogleFonts.sora(fontSize: 16),
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
          },
        );
      },
    );

    if (submit != true || !mounted || _submittingTicket) {
      subjectCtrl.dispose();
      messageCtrl.dispose();
      bookingIdCtrl.dispose();
      invoiceIdCtrl.dispose();
      return;
    }
    setState(() => _submittingTicket = true);

    try {
      await _api.createSupportTicket(
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
      Haptics.success();
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
      final failedPayload = {
        'type': type,
        'subject': subjectCtrl.text.trim(),
        'message': messageCtrl.text.trim(),
        'booking_id': bookingIdCtrl.text.trim(),
        'invoice_id': invoiceIdCtrl.text.trim(),
      };
      _lastFailedTicketPayload = failedPayload;
      await ActionRetryQueueService.log(
        actionType: 'support_ticket',
        status: 'failed',
        payload: failedPayload,
        detail: 'ApiException: ${e.statusCode} - ${e.message}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      final failedPayload = {
        'type': type,
        'subject': subjectCtrl.text.trim(),
        'message': messageCtrl.text.trim(),
        'booking_id': bookingIdCtrl.text.trim(),
        'invoice_id': invoiceIdCtrl.text.trim(),
      };
      _lastFailedTicketPayload = failedPayload;
      await ActionRetryQueueService.log(
        actionType: 'support_ticket',
        status: 'failed',
        payload: failedPayload,
        detail: 'Exception: ${e.toString()}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supportverzoek mislukt'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submittingTicket = false);
      subjectCtrl.dispose();
      messageCtrl.dispose();
      bookingIdCtrl.dispose();
      invoiceIdCtrl.dispose();
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
      await _api.createSupportTicket(
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
      backgroundColor: const Color(0xFFF7F8FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // ── AppBar ──
          SliverAppBar(
            backgroundColor: GymiesColors.darkBlue,
            foregroundColor: GymiesColors.primary,
            pinned: true,
            expandedHeight: 200,
            title: Text('Support',
                style: GoogleFonts.sora(fontSize: 20)),
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
                            style: GoogleFonts.sora(
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
                color: GymiesColors.darkBlue,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hoe kunnen we je helpen?',
                          style: GoogleFonts.sora(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Vind een antwoord of neem contact op',
                          style: GoogleFonts.sora(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: Container(
                margin: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
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
                  labelStyle: GoogleFonts.sora(
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
            childAspectRatio: 1.05,
          ),
          itemCount: supportFaqCategories.length,
          itemBuilder: (context, index) {
            final cat = supportFaqCategories[index];
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
              style: GoogleFonts.sora(
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
            Text(_error!, style: GoogleFonts.sora(color: Colors.grey.shade700)),
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
                          style: GoogleFonts.sora(
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Controleer je internet en probeer opnieuw.',
                          style: GoogleFonts.sora(
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
                    child: Text('Opnieuw', style: GoogleFonts.sora(fontSize: 12)),
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
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.mail_outline_rounded,
                        size: 32, color: GymiesColors.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nog geen supportverzoeken',
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hier verschijnen je tickets wanneer\nje contact opneemt.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sora(
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
                  str: _strHelper,
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
                    style: GoogleFonts.sora(
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
//  HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════

String _strHelper(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final v = map[key];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return '';
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
                    color: GymiesColors.primary, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                category.label,
                style: GoogleFonts.sora(
                  fontSize: 15,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                category.description,
                style: GoogleFonts.sora(
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
                  style: GoogleFonts.sora(
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: GymiesColors.primary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: GymiesColors.primary.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
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
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Start een gesprek met ons team',
                      style: GoogleFonts.sora(
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
                        style: GoogleFonts.sora(
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
                        style: GoogleFonts.sora(
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
                        style: GoogleFonts.sora(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    if (typeRaw.isNotEmpty && created.isNotEmpty)
                      Text(' · ',
                          style: GoogleFonts.sora(color: Colors.grey.shade400)),
                    if (created.isNotEmpty)
                      Text(
                        created.length > 10
                            ? created.substring(0, 10)
                            : created,
                        style: GoogleFonts.sora(
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
                    style: GoogleFonts.sora(
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
                    style: GoogleFonts.sora(
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
        title: Text('Support', style: GoogleFonts.sora(fontSize: 20)),
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
                      style: GoogleFonts.sora(
                        fontSize: 20,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${items.length} veelgestelde vragen',
                      style: GoogleFonts.sora(
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
                                  style: GoogleFonts.sora(
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
                                style: GoogleFonts.sora(
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
                                      style: GoogleFonts.sora(
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
                              style: GoogleFonts.sora(
                                color: GymiesColors.darkBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stuur ons een bericht',
                              style: GoogleFonts.sora(
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
                          style: GoogleFonts.sora(
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
  late GymiesApi _api;
  bool _didFirstLoad = false;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<GymiesApi>();
    if (!_didFirstLoad) {
      _didFirstLoad = true;
      _refreshTicket(silent: true);
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
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
    final rawStatus = _strHelper(_ticket, ['status', 'state']);
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
    final created = _strHelper(message, ['created_at', 'createdAt']);
    final time = _timeLabel(created);
    if (!mine) return time;

    final readAt = _strHelper(message, ['read_at', 'readAt', 'seen_at', 'seenAt']);
    if (readAt.trim().isNotEmpty) return '$time · Gelezen';
    return time;
  }

  bool _mineFromMessage(Map<String, dynamic> m) {
    final explicitMine = m['is_mine'] ?? m['mine'] ?? m['isMine'];
    if (explicitMine == true || explicitMine == 1 || explicitMine == '1') {
      return true;
    }
    final senderId = _strHelper(m, [
      'user_id', 'sender_id', 'author_id', 'from_user_id', 'fromUserId',
    ]);
    if (widget.currentUserId.isNotEmpty &&
        senderId.isNotEmpty &&
        senderId == widget.currentUserId) {
      return true;
    }
    final author = _strHelper(m, [
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
      final detail = await _api.getSupportTicketDetail(
        widget.ticketId,
      );
      if (!mounted) return;
      if (detail.isNotEmpty) setState(() => _ticket = detail);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Dit ticket bestaat niet meer',
              style: GoogleFonts.sora(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (mounted) Navigator.of(context).pop();
      }
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
      await _api.sendSupportTicketReply(
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
      if (e.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Dit ticket bestaat niet meer',
              style: GoogleFonts.sora(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatDateNice(String raw) {
    final dt = _dateFrom(raw);
    if (dt.millisecondsSinceEpoch == 0) return '';
    const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabelLocal(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('resolved') || s.contains('closed') || s.contains('done')) return 'Opgelost';
    if (s.contains('in_progress') || s.contains('pending') || s.contains('waiting')) return 'In behandeling';
    return 'Open';
  }

  Color _statusColorLocal(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('resolved') || s.contains('closed') || s.contains('done')) return Colors.green.shade600;
    if (s.contains('in_progress') || s.contains('pending') || s.contains('waiting')) return Colors.orange.shade600;
    return Colors.blue.shade600;
  }

  Color _statusBgLocal(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('resolved') || s.contains('closed') || s.contains('done')) return Colors.green.shade50;
    if (s.contains('in_progress') || s.contains('pending') || s.contains('waiting')) return Colors.orange.shade50;
    return Colors.blue.shade50;
  }

  String _categoryLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'booking': return 'Boeking';
      case 'invoice': return 'Factuur';
      case 'check_in': return 'Check-in';
      case 'payment': return 'Betaling';
      case 'dispute': return 'Geschil';
      case 'incident': return 'Incident';
      case 'billing': return 'Facturatie';
      case 'account': return 'Account';
      case 'technical': return 'Technisch';
      case 'general': return 'Algemeen';
      default: return raw.isEmpty ? 'Overig' : raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages();
    final created = _strHelper(_ticket, ['created_at', 'createdAt', 'date']);
    final statusRaw = _strHelper(_ticket, ['status', 'state']);
    final subject = _strHelper(_ticket, ['subject', 'title', 'name']);
    final category = _strHelper(_ticket, ['category', 'type', 'ticket_type']);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: Colors.white,
        title: Text('Support', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Info card ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
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
                        style: GoogleFonts.sora(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusBgLocal(statusRaw),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusLabelLocal(statusRaw),
                        style: GoogleFonts.sora(
                          color: _statusColorLocal(statusRaw),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      _formatDateNice(created),
                      style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.label_outline_rounded, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        _categoryLabel(category),
                        style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // ── Messages ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Wacht op reactie van support',
                          style: GoogleFonts.sora(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  ...messages.map((m) {
                    final body = _strHelper(m, ['message', 'body', 'text', 'content']);
                    final mine = _mineFromMessage(m);
                    final title = mine ? widget.currentUserName : 'Gymies Support';
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
                          style: GoogleFonts.sora(
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

          // ── Reply bar ──
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _replyController,
                        minLines: 1,
                        maxLines: 4,
                        enabled: !_ticketClosed() && !_sending,
                        textCapitalization: TextCapitalization.sentences,
                        style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue),
                        decoration: InputDecoration(
                          hintText: _ticketClosed()
                              ? 'Ticket is afgerond'
                              : 'Typ een bericht...',
                          hintStyle: GoogleFonts.sora(fontSize: 14, color: Colors.grey.shade400),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendReply(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: (_ticketClosed() || _sending) ? Colors.grey.shade300 : GymiesColors.primary,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: (_ticketClosed() || _sending) ? null : _sendReply,
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        child: _sending
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: GymiesColors.darkBlue,
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                size: 20,
                                color: GymiesColors.darkBlue,
                              ),
                      ),
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
    final maxWidth = (MediaQuery.of(context).size.width * 0.7).clamp(0.0, 400.0);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: maxWidth),
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
                    child: Center(
                      child: Text(
                        'G',
                        style: GoogleFonts.sora(
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
                  style: GoogleFonts.sora(
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
              style: GoogleFonts.sora(
                color: mine ? Colors.white : GymiesColors.darkBlue,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if ((meta ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                meta!.trim(),
                style: GoogleFonts.sora(
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
