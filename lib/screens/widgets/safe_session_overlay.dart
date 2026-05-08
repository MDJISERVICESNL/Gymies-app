import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/booking.dart';
import '../../services/api_client.dart';
import '../../services/gymies_api.dart';
import '../../theme/gymies_theme.dart';
import '../../utils/haptics.dart';
import 'gymies_dialog.dart';

/// Safe Session Overlay
///
/// Wordt getoond op het client sessie scherm wanneer een safe session actief is.
/// Features:
/// - Live timer die aftelt tot verwacht einde
/// - "Ik ben OK" heartbeat knop (verlengt timer met 30 min)
/// - SOS panic knop (stuurt noodalert)
/// - Noodcontact info
/// - Pulserende groene ring als alles OK is
/// - Rode ring als sessie overdue is
///
/// Gebruik: SafeSessionOverlay(booking: booking) in een Stack boven de content.
class SafeSessionOverlay extends StatefulWidget {
  const SafeSessionOverlay({
    super.key,
    required this.booking,
    this.onDismiss,
  });

  final Booking booking;
  final VoidCallback? onDismiss;

  @override
  State<SafeSessionOverlay> createState() => _SafeSessionOverlayState();
}

class _SafeSessionOverlayState extends State<SafeSessionOverlay>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────
  bool _active = false;
  // ignore: unused_field
  DateTime? _startedAt;
  DateTime? _expectedEndAt;
  int _minutesRemaining = 0;
  String _escalation = 'none';
  bool _sendingHeartbeat = false;
  bool _expanded = true;

  // ── Timer ─────────────────────────────────────────────────────
  Timer? _refreshTimer;
  Timer? _countdownTimer;

  // ── Animation ─────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialiseer vanuit booking data
    _active = widget.booking.safeSessionActive;
    _startedAt = widget.booking.safeSessionStartedAt;
    _expectedEndAt = widget.booking.safeSessionExpectedEndAt;

    if (_active) {
      _updateMinutesRemaining();
      _startCountdown();
      // Poll status elke 60 seconden
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _fetchStatus(),
      );
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Status ophalen ────────────────────────────────────────────
  Future<void> _fetchStatus() async {
    if (!mounted) return;
    try {
      final api = context.read<GymiesApi>();
      final status = await api.getSafeSessionStatus(widget.booking.id);
      if (!mounted) return;

      final active = status['active'] == true;
      if (!active) {
        // Safe session is gestopt (trainer heeft uitgecheckt)
        setState(() => _active = false);
        _countdownTimer?.cancel();
        _refreshTimer?.cancel();
        return;
      }

      setState(() {
        _active = true;
        _escalation = (status['escalation'] ?? 'none').toString();
        if (status['expected_end_at'] != null) {
          _expectedEndAt = DateTime.tryParse(status['expected_end_at'].toString());
        }
        _updateMinutesRemaining();
      });
    } catch (_) {
      // Stille fout — probeer het later opnieuw
    }
  }

  void _updateMinutesRemaining() {
    if (_expectedEndAt == null) {
      _minutesRemaining = 0;
      _escalation = 'none';
      return;
    }
    final diff = _expectedEndAt!.difference(DateTime.now()).inMinutes;
    _minutesRemaining = diff;
    if (diff < -90) {
      _escalation = 'critical';
    } else if (diff < -30) {
      _escalation = 'emergency';
    } else if (diff < 0) {
      _escalation = 'warning';
    } else {
      _escalation = 'none';
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _updateMinutesRemaining());
    });
  }

  // ── Heartbeat ─────────────────────────────────────────────────
  Future<void> _sendHeartbeat() async {
    if (_sendingHeartbeat) return;
    setState(() => _sendingHeartbeat = true);
    Haptics.medium();

    try {
      await context.read<GymiesApi>().safeSessionHeartbeat(
        bookingId: widget.booking.id,
      );
      if (!mounted) return;

      // Timer verlengen met 30 minuten
      setState(() {
        _expectedEndAt = DateTime.now().add(const Duration(minutes: 30));
        _updateMinutesRemaining();
        _sendingHeartbeat = false;
      });

      Haptics.heavy();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(S.of(context).timerExtended30Min),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sendingHeartbeat = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendingHeartbeat = false);
    }
  }

  // ── SOS ───────────────────────────────────────────────────────
  Future<void> _sendSos() async {
    final ok = await GymiesDialog.destructive(
      context,
      title: 'SOS Noodalert',
      message: S.of(context).weetJeZekerDatJeEen3,
      icon: Icons.emergency_rounded,
      confirmLabel: 'Verstuur SOS',
    );
    if (ok != true || !mounted) return;

    Haptics.heavy();

    // GPS ophalen (best-effort, niet blokkerend bij weigering)
    double? lat;
    double? lng;
    try {
      final perm = await Geolocator.checkPermission();
      final usable = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      if (!usable) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.always ||
            req == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          );
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } else {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // GPS niet beschikbaar — SOS gaat gewoon zonder locatie door
    }

    if (!mounted) return;

    try {
      await context.read<GymiesApi>().sendSosAlert(
        bookingId: widget.booking.id,
        latitude: lat,
        longitude: lng,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(S.of(context).emergencyContactAutoNotified),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();

    final isOverdue = _escalation != 'none';
    final statusColor = switch (_escalation) {
      'critical' => Colors.red.shade700,
      'emergency' => Colors.red.shade500,
      'warning' => Colors.orange.shade600,
      _ => Colors.green.shade600,
    };

    // Minimized banner
    if (!_expanded) {
      return Positioned(
        bottom: 16,
        left: 16,
        right: 16,
        child: GestureDetector(
          onTap: () => setState(() => _expanded = true),
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (ctx, child) => Transform.scale(
              scale: isOverdue ? _pulseAnimation.value : 1.0,
              child: child,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    isOverdue
                        ? Icons.warning_rounded
                        : Icons.shield_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isOverdue
                          ? S.of(context).sessionTakingLonger
                          : S.of(context).veiligheidssessieActief,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.expand_less_rounded,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Expanded overlay
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: statusColor.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (ctx, child) => Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    ),
                    child: Icon(
                      isOverdue
                          ? Icons.warning_rounded
                          : Icons.shield_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isOverdue
                          ? 'Alles goed?' // Keep for now or add a key
                          : S.of(context).veiligheidssessieActief,
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = false),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Timer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.timer_rounded,
                        size: 20,
                        color: isOverdue ? statusColor : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _minutesRemaining > 0
                            ? '$_minutesRemaining min resterend'
                            : _minutesRemaining == 0
                                ? S.of(context).sessieEindeBereikt
                                : '${_minutesRemaining.abs()} min over tijd',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isOverdue ? statusColor : GymiesColors.darkBlue,
                        ),
                      ),
                    ],
                  ),

                  if (isOverdue) ...[
                    const SizedBox(height: 12),
                    Text(
                      S.of(context).jeSessieDuurtLangerDanVerwacht
                      'Tik op "Ik ben OK" als alles goed gaat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ── "Ik ben OK" knop ──────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sendingHeartbeat ? null : _sendHeartbeat,
                      icon: _sendingHeartbeat
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.favorite_rounded,
                              size: 20,
                            ),
                      label: Text(
                        _sendingHeartbeat ? S.of(context).versturen2 : S.of(context).sosHelpNeeded, // Use the appropriate key or keep dynamic
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ── SOS knop ──────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _sendSos,
                      icon: const Icon(Icons.emergency_rounded, size: 20),
                      label: const Text(
                        S.of(context).sosHulpNodig,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Info tekst ────────────────────────────
                  Text(
                    S.of(context).jeNoodcontactWordtAutomatischGenformeerdAls
                    S.of(context).reageertNaHetVerwachteEindeVan,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
