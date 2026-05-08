



import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/booking.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'dart:async';
import 'dart:convert';
import 'widgets/gymies_dialog.dart';
/// Client Check-in QR Screen
///
/// Professioneel QR check-in scherm met:
/// - Countdown timer (45s) met visuele ring
/// - Auto-refresh wanneer token verloopt
/// - Backup code duidelijk zichtbaar
/// - Haptic feedback bij acties
/// - SOS noodknop
/// - Geen onveilige lokale fallback tokens
class ClientCheckInQrScreen extends StatefulWidget {
  const ClientCheckInQrScreen({super.key, required this.booking});

  final Booking booking;

  @override
  State<ClientCheckInQrScreen> createState() => _ClientCheckInQrScreenState();
}

class _ClientCheckInQrScreenState extends State<ClientCheckInQrScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────
  bool _loading = true;
  String? _error;
  String _qrPayload = '';
  String _backupCode = '';
  int _secondsLeft = 0;
  bool _showBackupCode = false;

  // ── Timer & Animation ─────────────────────────────────────────
  Timer? _countdownTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _successController;

  static const int _tokenTtl = 45; // seconden (server TTL = 45s)

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadQr();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _successController.dispose();
    super.dispose();
  }

  // ── QR laden ──────────────────────────────────────────────────
  Future<void> _loadQr() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<GymiesApi>();
      final data = await api.getBookingCheckInQr(widget.booking.id);

      if (!mounted) return;

      final token = _str(data, ['token', 'qr_token', 'checkin_token']);
      final qrValue = _str(data, ['qr_value', 'value', 'payload', 'qr']);
      final backupCode = _str(data, ['backup_code', 'backupCode', 'code']);
      final expiresIn = _int(data, ['expires_in', 'expiresIn']) ?? _tokenTtl;

      // QR payload: gebruik server-provided value, of bouw zelf op
      final payload = qrValue.isNotEmpty
          ? qrValue
          : jsonEncode({
              'type': 'gymies_checkin',
              'booking_id': widget.booking.id,
              if (token.isNotEmpty) 'token': token,
              'v': 2,
            });

      setState(() {
        _qrPayload = payload;
        _backupCode = backupCode;
        _secondsLeft = expiresIn;
        _loading = false;
      });

      Haptics.light();
      _startCountdown();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isNotEmpty
            ? e.message
            : S.of(context).konQrcodeNietLadenControleerJe;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = S.of(context).erGingIetsMisProbeerHet;
        _loading = false;
      });
    }
  }

  // ── Countdown ─────────────────────────────────────────────────
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
      });
      // Haptic warning bij 10 seconden
      if (_secondsLeft == 10) {
        Haptics.medium();
      }
      // Auto-refresh bij 0
      if (_secondsLeft <= 0) {
        timer.cancel();
        Haptics.heavy();
        _loadQr(); // Automatisch nieuw token ophalen
      }
    });
  }

  // ── SOS Alert ─────────────────────────────────────────────────
  Future<void> _sendSos() async {
    final ok = await GymiesDialog.destructive(
      context,
      title: 'SOS Noodalert',
      message: '${S.of(context).weetJeZekerDatJeEen} ${S.of(context).jeNoodcontactEnHetPlatformWorden}',
      icon: Icons.emergency_rounded,
      confirmLabel: 'Verstuur SOS',
    );
    if (ok != true || !mounted) return;

    Haptics.heavy();

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
    } catch (e) {
      // Fail-open: Location optional for check-in
      if (kDebugMode) debugPrint('[CheckInQR] Get location failed: $e');
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
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(S.of(context).sosalertVerstuurdJeNoodcontactIsOpDeHoogte),
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

  // ── Helpers ───────────────────────────────────────────────────
  String _str(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final val = map[key];
      if (val != null && val.toString().trim().isNotEmpty) {
        return val.toString().trim();
      }
    }
    return '';
  }

  int? _int(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final val = map[key];
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) {
        final parsed = int.tryParse(val);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  void _copyBackupCode() {
    if (_backupCode.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _backupCode));
    Haptics.light();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(S.of(context).backupCodeGekopieerd),
        backgroundColor: GymiesColors.darkBlue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final date =
        '${booking.scheduledAt.day.toString().padLeft(2, '0')}-'
        '${booking.scheduledAt.month.toString().padLeft(2, '0')}-'
        '${booking.scheduledAt.year}';
    final time =
        '${booking.scheduledAt.hour.toString().padLeft(2, '0')}:'
        '${booking.scheduledAt.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: GymiesColors.darkBlue,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: const BoxDecoration(color: GymiesColors.darkBlue),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    S.of(context).checkin,
                    style: GoogleFonts.sora(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // SOS knop — altijd zichtbaar, rode achtergrond
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    onPressed: _sendSos,
                    tooltip: 'SOS Noodalert',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.emergency_rounded, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : _buildContent(date, time),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: GymiesColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.of(context).qrcodeGenereren,
            style: GoogleFonts.sora(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: Colors.red.shade300,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadQr,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text(S.of(context).opnieuwProberen),
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String date, String time) {
    final isExpiring = _secondsLeft <= 15;
    final timerColor =
        isExpiring ? Colors.red.shade400 : GymiesColors.primary;
    final progress = _secondsLeft / _tokenTtl;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            // ── Sessie info ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    color: GymiesColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.booking.trainerName.isEmpty
                              ? S.of(context).trainer
                              : widget.booking.trainerName,
                          style: GoogleFonts.sora(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$date om $time',
                          style: GoogleFonts.sora(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── QR Code met countdown ring ───────────────────
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: GymiesColors.primary.withOpacity(0.15),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // QR met timer ring eromheen
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Countdown ring
                          SizedBox(
                            width: 260,
                            height: 260,
                            child: CircularProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              strokeWidth: 4,
                              backgroundColor: Colors.grey.shade200,
                              color: timerColor,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          // QR code
                          QrImageView(
                            data: _qrPayload,
                            size: 220,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: GymiesColors.darkBlue,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: GymiesColors.darkBlue,
                            ),
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.all(8),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Timer tekst
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isExpiring
                              ? Icons.timer_off_rounded
                              : Icons.timer_rounded,
                          size: 18,
                          color: isExpiring
                              ? Colors.red.shade600
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _secondsLeft > 0
                              ? 'Verloopt over ${_secondsLeft}s'
                              : 'Vernieuwen...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isExpiring
                                ? Colors.red.shade600
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Instructie ──────────────────────────────────
            Text(
              S.of(context).laatDezeQrcodeScannenDoorJeTrainer,
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                color: Colors.white.withOpacity(0.8),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),

            // ── Backup code sectie ──────────────────────────
            if (_backupCode.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.dialpad_rounded,
                          size: 18,
                          color: Colors.white.withOpacity(0.6),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          S.of(context).backupCode,
                          style: GoogleFonts.sora(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            setState(
                                () => _showBackupCode = !_showBackupCode);
                            Haptics.selection();
                          },
                          child: Icon(
                            _showBackupCode
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _copyBackupCode,
                      onLongPress: _copyBackupCode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _showBackupCode
                                  ? _formatBackupCode(_backupCode)
                                  : '•••  •••',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.primary,
                                letterSpacing: 6,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.copy_rounded,
                              size: 18,
                              color: GymiesColors.primary.withOpacity(0.6),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).kanDeQrNietGescandWordenGeefDezeCodeAanJeTrainer,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.sora(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Handmatig vernieuwen knop ────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _loadQr,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(S.of(context).nieuweQrGenereren),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withOpacity(0.25),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _formatBackupCode(String code) {
    if (code.length >= 6) {
      return '${code.substring(0, 3)}  ${code.substring(3, 6)}';
    }
    return code;
  }
}
