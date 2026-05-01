import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/timing_constants.dart';
import '../config/ui_constants.dart';
import '../theme/gymies_theme.dart';
import '../models/booking.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../services/action_retry_queue_service.dart';
import '../services/subscription_entitlements_service.dart';
import 'trainer_agenda_screen.dart';
import 'trainer_documents_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/gymies_segment_tab_bar.dart';
import 'widgets/gymies_upgrade_prompt.dart';
import 'widgets/trainer_state_views.dart';
import '../utils/haptics.dart';

/// Overzicht van alle sessies (pending, komend, voltooid) met bevestigen/afwijzen.
/// [initialTabIndex] 0=Te bevestigen, 1=Komend, 2=Voltooid – handig voor deep links.
class TrainerSessionsScreen extends StatefulWidget {
  const TrainerSessionsScreen({
    super.key,
    this.initialTabIndex,
  });

  final int? initialTabIndex;

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
      length: 4,
      vsync: this,
      initialIndex: (idx != null && idx >= 0 && idx < 4) ? idx : 0,
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
      } catch (e) {
        if (kDebugMode) debugPrint('[TrainerSessions] Invoices laden fout: $e');
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
      if (kDebugMode) debugPrint('[TrainerSessions] Sessies laden fout: $e');
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
    Haptics.light();
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
    Haptics.light();
    final confirmed = await GymiesDialog.destructive(
      context,
      title: 'Sessie afwijzen',
      message: 'Weet je zeker dat je deze aanvraag wilt afwijzen?',
      icon: Icons.block_rounded,
      confirmLabel: 'Afwijzen',
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
    Haptics.light();
    final api = context.read<GymiesApi>();
    bool notifyStandby = true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setModalState) => GymiesDialog(
          headerIcon: Icons.event_busy_rounded,
          headerIconColor: UiConstants.errorRed,
          headerIconBgColor: UiConstants.errorRed.withValues(alpha: 0.1),
          title: 'Sessie annuleren',
          subtitle: 'Weet je zeker dat je deze sessie wilt annuleren?',
          content: CheckboxListTile(
            value: notifyStandby,
            contentPadding: EdgeInsets.zero,
            title: const Text('Stuur direct standby push'),
            subtitle: const Text(
              'Geinteresseerde klanten krijgen meteen een boekkans.',
            ),
            onChanged: (v) =>
                setModalState(() => notifyStandby = v ?? true),
          ),
          actions: [
            GymiesDialogAction(
              label: 'Ja, annuleren',
              isPrimary: true,
              isDestructive: true,
              returnValue: true,
            ),
            GymiesDialogAction(
              label: 'Nee',
              returnValue: false,
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
        } catch (e) {
          if (kDebugMode) debugPrint('[TrainerSessions] Waitlist notificatie fout: $e');
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
    Haptics.light();
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
    Haptics.light();

    // ── Bevestigingsdialoog ──
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ──
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.shield_rounded,
                  color: Colors.green.shade700,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Safe session activeren?',
                style: GoogleFonts.sora(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Het systeem stuurt elke 2 minuten een heartbeat. '
                'Als er geen reactie komt, wordt er een noodmelding verstuurd.',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              // ── Sessie-info ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(
                      'Sessie',
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        '${b.clientName ?? 'Klant'} · '
                        '${b.scheduledAt.hour.toString().padLeft(2, '0')}:'
                        '${b.scheduledAt.minute.toString().padLeft(2, '0')}–'
                        '${b.scheduledAt.add(Duration(minutes: b.durationMinutes)).hour.toString().padLeft(2, '0')}:'
                        '${b.scheduledAt.add(Duration(minutes: b.durationMinutes)).minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.sora(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: GymiesColors.darkBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // ── Optionele notitie ──
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: noteController,
                  style: GoogleFonts.sora(fontSize: 12, color: GymiesColors.darkBlue),
                  decoration: InputDecoration(
                    hintText: 'Optionele notitie...',
                    hintStyle: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade400),
                    contentPadding: const EdgeInsets.all(12),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // ── Knoppen ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        'Annuleren',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Activeren',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    noteController.dispose();
    if (confirmed != true || !mounted) return;

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
    Haptics.light();

    // ── Beëindigingsdialoog (met samenvatting bij safe session) ──
    final isSafe = b.safeSessionActive;
    final startedAt = b.safeSessionStartedAt;
    final now = DateTime.now();
    final durationMin = startedAt != null
        ? now.difference(startedAt).inMinutes
        : b.durationMinutes;
    final heartbeats = startedAt != null
        ? (now.difference(startedAt).inMinutes / 2).floor()
        : 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ──
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.green.shade700,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Sessie beëindigen?',
                style: GoogleFonts.sora(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isSafe
                    ? 'De safe session monitoring wordt gestopt en '
                      'de klant wordt automatisch uitgecheckt.'
                    : 'De klant wordt uitgecheckt en de sessie wordt voltooid.',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              if (isSafe) ...[
                const SizedBox(height: 16),
                // ── Samenvatting ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(label: 'Duur', value: '$durationMin min'),
                      const SizedBox(height: 8),
                      _SummaryRow(
                        label: 'Heartbeats',
                        value: '$heartbeats succesvol',
                      ),
                      const SizedBox(height: 8),
                      _SummaryRow(
                        label: 'Escalaties',
                        value: 'Geen',
                        valueColor: Colors.green.shade700,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              // ── Knoppen ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        'Terug',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: GymiesColors.darkBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Beëindigen',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

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
    Haptics.heavy();
    final ok = await GymiesDialog.destructive(
      context,
      title: 'SOS-alert',
      message: 'Weet je zeker dat je een noodalert wilt versturen? '
          'Admin wordt direct op de hoogte gesteld.',
      icon: Icons.sos_rounded,
      confirmLabel: 'Verstuur SOS',
    );
    if (ok != true || !mounted) return;

    // GPS best-effort
    double? lat;
    double? lng;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {}

    if (!mounted) return;

    try {
      await context.read<GymiesApi>().sendSosAlert(
        latitude: lat,
        longitude: lng,
      );
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
    Haptics.light();
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
    Haptics.light();
    final reasonController = TextEditingController();
    final noteController = TextEditingController();
    final evidenceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => GymiesDialog(
        headerIcon: Icons.person_off_rounded,
        headerIconColor: UiConstants.errorRed,
        headerIconBgColor: UiConstants.errorRed.withValues(alpha: 0.1),
        title: 'No-show registreren',
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
                const SizedBox(height: 20),
                SizedBox(
                  width: double.maxFinite,
                  child: FilledButton(
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      Navigator.of(ctx).pop(true);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: UiConstants.errorRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('No-show registreren',
                        style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.maxFinite,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text('Annuleren',
                        style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
        showCloseButton: true,
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
    Haptics.selection();
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
    Haptics.selection();
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
        } catch (e) {
          if (kDebugMode) debugPrint('[TrainerSessions] Invoice PDF link ophalen fout: $e');
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
          booking.scheduledAt.add(Duration(days: TimingConstants.invoiceDueDays)),
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
    DateTime dueDate = serviceDate.add(Duration(days: TimingConstants.invoiceDueDays));
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => GymiesDialog(
          headerIcon: Icons.receipt_long_rounded,
          headerIconColor: GymiesColors.primary,
          headerIconBgColor: GymiesColors.primary.withValues(alpha: 0.1),
          title: 'Factuur opstellen',
          content: Form(
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
                        lastDate: now.add(TimingConstants.twoYearRange),
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
                        lastDate: now.add(TimingConstants.twoYearRange),
                        initialDate: dueDate.isBefore(serviceDate)
                            ? serviceDate
                            : dueDate,
                      );
                      if (picked == null) return;
                      setModalState(() => dueDate = picked);
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.maxFinite,
                    child: FilledButton(
                      onPressed: () {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        Navigator.of(ctx).pop(true);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: GymiesColors.primary,
                        foregroundColor: GymiesColors.darkBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Opstellen & versturen',
                          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.maxFinite,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('Annuleren',
                          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          showCloseButton: true,
        ),
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
        } catch (e) {
          if (kDebugMode) debugPrint('[TrainerSessions] Invoice list reload fout: $e');
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
      builder: (ctx) => GymiesDialog(
        headerIcon: Icons.receipt_long_rounded,
        headerIconColor: GymiesColors.primary,
        headerIconBgColor: GymiesColors.primary.withValues(alpha: 0.1),
        title: resend ? 'Factuur review (opnieuw versturen)' : 'Factuur review',
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
                style: GoogleFonts.sora(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                'Na versturen moet de klant de PDF direct downloaden.',
                style: GoogleFonts.sora(
                  color: Colors.orange.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.maxFinite,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    foregroundColor: GymiesColors.darkBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(resend ? 'Opnieuw versturen' : 'Verstuur naar klant',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.maxFinite,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(resend ? 'Annuleren' : 'Terug bewerken',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
        showCloseButton: true,
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
              style: GoogleFonts.sora(fontWeight: FontWeight.w600),
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

    final goToDocs = await GymiesDialog.confirm(
      context,
      title: 'Factuurgegevens ontbreken',
      message: 'Vul eerst je factuurdocumenten in:\n- ${missing.join('\n- ')}',
      icon: Icons.description_outlined,
      confirmLabel: 'Naar documenten',
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

  /// Heeft de trainer een sessie die nu actief is (ingecheckt of in check-in window)?
  bool _hasActiveSession() {
    final now = DateTime.now();
    for (final b in _bookings) {
      final status = b.status.toLowerCase();
      if (status == 'cancelled' || status == 'completed') continue;
      // Ingecheckt of safe session actief → altijd tonen
      if (b.isCheckedIn || b.safeSessionActive) return true;
      // Bevestigde sessie in check-in window (15 min voor tot 15 min na)
      if (status == 'confirmed') {
        final startWindow = b.scheduledAt.subtract(TimingConstants.checkInWindow);
        final endWindow = b.scheduledAt
            .add(Duration(minutes: b.durationMinutes))
            .add(TimingConstants.checkInWindow);
        if (!now.isBefore(startWindow) && !now.isAfter(endWindow)) return true;
      }
    }
    return false;
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
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: 'Mijn sessies',
        actions: [
          GymiesAppBarAction(
            icon: Icons.calendar_month_rounded,
            tooltip: 'Agenda',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const TrainerAgendaScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: GymiesSegmentTabBar(
          controller: _tabController,
          tabs: const ['Nieuw', 'Komend', 'Voltooid', 'Groep'],
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
                  // ── Tab 3: Groepslessen (Pro+) ──
                  _GroupClassesTab(),
                ],
              ),
                  if (_hasActiveSession())
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton(
                        onPressed: _sendSos,
                        backgroundColor: Colors.red.shade700,
                        elevation: 4,
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

  static const _weekdays = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
  static const _months = [
    'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
    'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
  ];

  String _formatSessionType(String? type) {
    if (type == null || type.isEmpty) return 'Personal training';
    switch (type.toLowerCase()) {
      case 'personal_training':
      case 'personal':
        return 'Personal training';
      case 'group':
      case 'group_class':
        return 'Groepsles';
      case 'online':
        return 'Online sessie';
      case 'assessment':
        return 'Assessment';
      case 'intro':
      case 'introduction':
        return 'Kennismaking';
      default:
        return type[0].toUpperCase() + type.substring(1);
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    if (date == today) return 'vandaag';
    if (date == today.add(const Duration(days: 1))) return 'morgen';
    return _weekdays[d.weekday - 1];
  }

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

    final now = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    final weekday = _weekdays[d.weekday - 1];

    final hasLocation = (booking.locationName ?? '').isNotEmpty;
    final hasAmount = (booking.amountCents ?? 0) > 0;
    final amountLabel = hasAmount
        ? '€${((booking.amountCents ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',')}'
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday
              ? GymiesColors.primary.withValues(alpha: 0.6)
              : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // ── Tijd-badge ──
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isToday
                        ? GymiesColors.primary.withValues(alpha: 0.12)
                        : const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        _dayLabel(d),
                        style: GoogleFonts.sora(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isToday ? GymiesColors.darkBlue : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: GoogleFonts.sora(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: GymiesColors.darkBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${isToday ? 'Vandaag' : weekday} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} · ${_formatSessionType(booking.sessionType)} · ${booking.durationMinutes} min',
                        style: GoogleFonts.sora(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      // ── Locatie + prijs ──
                      if (hasLocation || hasAmount) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (hasLocation) ...[
                              Icon(Icons.place_outlined, size: 12, color: Colors.grey.shade400),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  booking.locationName!,
                                  style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (hasLocation && hasAmount)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text('·', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                              ),
                            if (hasAmount)
                              Text(
                                amountLabel!,
                                style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade500),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(booking.status).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(booking.status),
                    style: GoogleFonts.sora(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(booking.status),
                    ),
                  ),
                ),
                if (!isUpcomingTab)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (busy) return;
                      Haptics.selection();
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
            // ── Safe Session actieve banner (verbeterd) ─────
            if (booking.safeSessionActive) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    // ── Header banner ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                        border: Border(
                          bottom: BorderSide(color: Colors.green.shade200, width: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.shield_rounded, color: Colors.green.shade700, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Safe session actief',
                            style: GoogleFonts.sora(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (booking.safeSessionStartedAt != null)
                            Text(
                              'gestart ${booking.safeSessionStartedAt!.hour.toString().padLeft(2, '0')}:${booking.safeSessionStartedAt!.minute.toString().padLeft(2, '0')}',
                              style: GoogleFonts.sora(
                                color: Colors.green.shade600,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // ── Timer + progress + heartbeat ──
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          // Timer progress
                          Builder(builder: (_) {
                            final startedAt = booking.safeSessionStartedAt;
                            final endAt = booking.safeSessionExpectedEndAt ??
                                booking.scheduledAt.add(Duration(minutes: booking.durationMinutes));
                            final now = DateTime.now();
                            final totalDuration = endAt.difference(startedAt ?? booking.scheduledAt);
                            final elapsed = now.difference(startedAt ?? booking.scheduledAt);
                            final progress = totalDuration.inSeconds > 0
                                ? (elapsed.inSeconds / totalDuration.inSeconds).clamp(0.0, 1.0)
                                : 0.0;
                            final elapsedStr =
                                '${elapsed.inHours.toString().padLeft(2, '0')}:'
                                '${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}:'
                                '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
                            final startStr = startedAt != null
                                ? '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}'
                                : '';
                            final endStr =
                                '${endAt.hour.toString().padLeft(2, '0')}:${endAt.minute.toString().padLeft(2, '0')}';

                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Verstreken tijd',
                                      style: GoogleFonts.sora(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                    Text(
                                      elapsedStr,
                                      style: GoogleFonts.sora(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: GymiesColors.darkBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 4,
                                    backgroundColor: Colors.grey.shade200,
                                    color: Colors.green.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(startStr,
                                        style: GoogleFonts.sora(
                                            fontSize: 10, color: Colors.grey.shade400)),
                                    Text(endStr,
                                        style: GoogleFonts.sora(
                                            fontSize: 10, color: Colors.grey.shade400)),
                                  ],
                                ),
                              ],
                            );
                          }),
                          const SizedBox(height: 10),
                          // Heartbeat info
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Heartbeat actief · elke 2 min',
                                style: GoogleFonts.sora(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          if (onCheckout != null) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: busy ? null : onCheckout,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade300),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Sessie beëindigen',
                                  style: GoogleFonts.sora(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
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
              ),
            ],
            // ── Quick action buttons ──
            if (!isUpcomingTab) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (booking.status == 'pending' && onConfirm != null) ...[
                    Expanded(
                      child: _ActionBtn(
                        label: 'Bevestig',
                        icon: Icons.check_rounded,
                        color: Colors.green.shade700,
                        onTap: busy ? null : onConfirm,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionBtn(
                        label: 'Afwijzen',
                        icon: Icons.close_rounded,
                        color: Colors.red.shade600,
                        onTap: busy ? null : onReject,
                      ),
                    ),
                  ] else if (booking.status == 'confirmed' && onComplete != null) ...[
                    Expanded(
                      child: _ActionBtn(
                        label: 'Voltooien',
                        icon: Icons.check_circle_outline_rounded,
                        color: Colors.green.shade700,
                        onTap: busy ? null : onComplete,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionBtn(
                        label: 'Verplaatsen',
                        icon: Icons.schedule_rounded,
                        color: GymiesColors.darkBlue,
                        onTap: busy ? null : onReschedule,
                      ),
                    ),
                  ] else if ((booking.status == 'completed' || booking.status == 'done' || booking.status == 'finished') && onCreateInvoice != null) ...[
                    Expanded(
                      child: _ActionBtn(
                        label: invoiceAlreadySent ? 'Factuur opnieuw' : 'Factuur',
                        icon: Icons.receipt_outlined,
                        color: GymiesColors.darkBlue,
                        onTap: busy ? null : onCreateInvoice,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (isUpcomingTab && (onCancel != null || onReschedule != null)) ...[
            if (isUpcomingTab && (onCancel != null || onReschedule != null)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  if (onReschedule != null)
                    IconButton(
                      onPressed: busy ? null : onReschedule,
                      icon: const Icon(Icons.event_outlined, size: 20),
                      tooltip: 'Verplaatsen',
                      style: IconButton.styleFrom(
                        foregroundColor: GymiesColors.darkBlue,
                        backgroundColor: GymiesColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                  if (onReschedule != null && onCancel != null)
                    const SizedBox(width: 8),
                  if (onCancel != null)
                    IconButton(
                      onPressed: busy ? null : onCancel,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Annuleren',
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        backgroundColor: Colors.red.shade50,
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
                  style: GoogleFonts.sora(
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
                        style: GoogleFonts.sora(
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
                  style: GoogleFonts.sora(
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
                  style: GoogleFonts.sora(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
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

/// ── Summary row helper (voor checkout dialoog) ─────────────────
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
        ),
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: valueColor ?? GymiesColors.darkBlue,
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.sora(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ── Groepslessen tab (Pro+ feature) ────────────────────────────
/// Toont een overzicht van groepslessen als de trainer Pro+ of Studio is.
/// Voor lagere tiers wordt een upgrade-prompt getoond.
class _GroupClassesTab extends StatefulWidget {
  const _GroupClassesTab();

  @override
  State<_GroupClassesTab> createState() => _GroupClassesTabState();
}

class _GroupClassesTabState extends State<_GroupClassesTab> {
  List<Map<String, dynamic>> _classes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final list = await api.getGroupClasses();
      if (mounted) {
        setState(() {
          _classes = List<Map<String, dynamic>>.from(list);
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('[GroupClasses] Laden fout: $e');
      if (mounted) setState(() { _error = 'Kon groepslessen niet laden.'; _loading = false; });
    }
  }

  Future<void> _createClass() async {
    Haptics.selection();
    final nameCtrl = TextEditingController();
    final capacityCtrl = TextEditingController(text: '10');
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int selectedDuration = 60;
    DateTime? scheduledAt;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => GymiesDialog(
          headerIcon: Icons.groups_rounded,
          headerIconColor: GymiesColors.primary,
          headerIconBgColor: GymiesColors.primary.withValues(alpha: 0.1),
          title: 'Nieuwe groepsles',
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Naam'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Vul een naam in' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: capacityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max deelnemers'),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return (n == null || n < 2) ? 'Min. 2 deelnemers' : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Duur', style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 60, label: Text('60 min')),
                      ButtonSegment(value: 90, label: Text('90 min')),
                      ButtonSegment(value: 120, label: Text('120 min')),
                    ],
                    selected: {selectedDuration},
                    onSelectionChanged: (v) =>
                        setDialogState(() => selectedDuration = v.first),
                  ),
                  const SizedBox(height: 12),
                  Text('Datum & tijd', style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final date = await showDatePicker(
                        context: ctx,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                        initialDate: scheduledAt ?? now.add(const Duration(days: 1)),
                      );
                      if (date == null) return;
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: scheduledAt != null
                            ? TimeOfDay.fromDateTime(scheduledAt!)
                            : const TimeOfDay(hour: 9, minute: 0),
                      );
                      if (time == null) return;
                      setDialogState(() {
                        scheduledAt = DateTime(
                          date.year, date.month, date.day,
                          time.hour, time.minute,
                        );
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        scheduledAt != null
                            ? '${scheduledAt!.day}/${scheduledAt!.month}/${scheduledAt!.year} '
                              '${scheduledAt!.hour.toString().padLeft(2, '0')}:${scheduledAt!.minute.toString().padLeft(2, '0')}'
                            : 'Kies datum en tijd',
                        style: GoogleFonts.sora(
                          color: scheduledAt != null ? Colors.black87 : Colors.grey.shade500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Beschrijving (optioneel)',
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.maxFinite,
                    child: FilledButton(
                      onPressed: () {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        if (scheduledAt == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kies een datum en tijd')),
                          );
                          return;
                        }
                        Navigator.of(ctx).pop(true);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: GymiesColors.primary,
                        foregroundColor: GymiesColors.darkBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Aanmaken',
                          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.maxFinite,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('Annuleren',
                          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          showCloseButton: true,
        ),
      ),
    );

    if (result != true || !mounted) return;
    try {
      await context.read<GymiesApi>().createGroupClass(
        name: nameCtrl.text.trim(),
        maxParticipants: int.parse(capacityCtrl.text.trim()),
        durationMinutes: selectedDuration,
        description: descCtrl.text.trim(),
        scheduledAt: scheduledAt!,
      );
      if (mounted) {
        await _load();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Groepsles aangemaakt!'),
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

  @override
  Widget build(BuildContext context) {
    final ent = Provider.of<SubscriptionEntitlementsService>(context);
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    if (!isProPlus) {
      return const GymiesUpgradePrompt(
        icon: Icons.groups_rounded,
        feature: 'Groepslessen',
        tier: 'Pro+',
        description:
            'Geef groepslessen, beheer capaciteit en laat meerdere klanten '
            'tegelijk boeken. Verhoog je omzet per uur met groepstraining.',
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_error!, style: GoogleFonts.sora(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw proberen'),
            ),
          ],
        ),
      );
    }

    if (_classes.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          TrainerEmptyState(
            icon: Icons.groups_rounded,
            title: 'Nog geen groepslessen',
            subtitle:
                'Maak je eerste groepsles aan en laat meerdere klanten tegelijk boeken.',
            actionLabel: 'Groepsles aanmaken',
            actionIcon: Icons.add_rounded,
            onAction: _createClass,
            padding: const EdgeInsets.all(32),
          ),
        ],
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            itemCount: _classes.length,
            itemBuilder: (_, i) {
              final cls = _classes[i];
              final name = (cls['name'] ?? cls['title'] ?? 'Groepsles').toString();
              final capacityRaw = cls['max_participants'] ?? cls['capacity'];
              final enrolledRaw = cls['enrolled_count'] ?? cls['participants'];
              final capacityNum = capacityRaw is num
                  ? capacityRaw.toInt()
                  : int.tryParse(capacityRaw?.toString() ?? '') ?? 0;
              final enrolledNum = enrolledRaw is num
                  ? enrolledRaw.toInt()
                  : int.tryParse(enrolledRaw?.toString() ?? '') ?? 0;
              final duration = cls['duration_minutes'] ?? cls['duration'] ?? '?';
              final scheduledRaw = cls['scheduled_at'] ?? cls['next_session'];
              final scheduled = scheduledRaw != null
                  ? DateTime.tryParse(scheduledRaw.toString())
                  : null;
              final isFull = capacityNum > 0 && enrolledNum >= capacityNum;

              const weekdays = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
              const months = [
                'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
                'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
              ];
              final now2 = DateTime.now();
              final isClassToday = scheduled != null &&
                  scheduled.year == now2.year &&
                  scheduled.month == now2.month &&
                  scheduled.day == now2.day;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isClassToday
                        ? GymiesColors.primary
                        : Colors.grey.shade200,
                    width: isClassToday ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: GymiesColors.darkBlue.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // ── Datum-badge ──
                      if (scheduled != null)
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isClassToday
                                ? GymiesColors.primary.withValues(alpha: 0.15)
                                : GymiesColors.darkBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${scheduled.day}',
                                style: GoogleFonts.sora(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              Text(
                                months[scheduled.month - 1],
                                style: GoogleFonts.sora(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: GymiesColors.darkBlue.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: GymiesColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.groups_rounded,
                              color: GymiesColors.darkBlue, size: 24),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.sora(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${scheduled != null ? (isClassToday ? 'Vandaag' : weekdays[scheduled.weekday - 1]) : ''}'
                              '${scheduled != null ? ' · ${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}' : ''}'
                              ' · $duration min',
                              style: GoogleFonts.sora(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$enrolledNum/${capacityNum > 0 ? capacityNum : '?'} deelnemers',
                              style: GoogleFonts.sora(
                                color: GymiesColors.darkBlue.withValues(alpha: 0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isFull
                              ? Colors.orange.shade100
                              : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isFull ? 'Vol' : 'Open',
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isFull
                                ? Colors.orange.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'fab_group_class',
            onPressed: _createClass,
            backgroundColor: GymiesColors.primary,
            tooltip: 'Nieuwe groepsles',
            child: const Icon(Icons.add_rounded, color: GymiesColors.darkBlue),
          ),
        ),
      ],
    );
  }
}
