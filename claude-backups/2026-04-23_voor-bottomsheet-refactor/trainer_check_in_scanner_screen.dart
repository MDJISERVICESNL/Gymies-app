import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/action_retry_queue_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';

/// Trainer QR Scanner Screen
///
/// Professioneel scanner scherm met:
/// - Animated viewfinder overlay met hoekmarkeringen
/// - Success animatie (vinkje + groen flash)
/// - Haptic feedback bij scan, success en error
/// - Fix voor _lastValue bug (reset bij error)
/// - Handmatige backup code fallback
/// - Offline retry queue support
class TrainerCheckInScannerScreen extends StatefulWidget {
  const TrainerCheckInScannerScreen({super.key});

  @override
  State<TrainerCheckInScannerScreen> createState() =>
      _TrainerCheckInScannerScreenState();
}

class _TrainerCheckInScannerScreenState
    extends State<TrainerCheckInScannerScreen> with TickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _processing = false;
  bool _torchOn = false;
  String? _lastValue;
  bool _showSuccess = false;
  String _successName = '';
  String? _statusMessage;

  // ── Animations ────────────────────────────────────────────────
  late AnimationController _scanLineController;
  late AnimationController _successController;
  late Animation<double> _successScale;
  late Animation<double> _successOpacity;
  late AnimationController _cornerController;
  late Animation<double> _cornerPulse;

  @override
  void initState() {
    super.initState();

    // Scan line animatie (op en neer)
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Success animatie
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _successScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _successOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    // Corner pulse animatie
    _cornerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _cornerPulse = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _cornerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _successController.dispose();
    _cornerController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ── QR Parsing ────────────────────────────────────────────────
  Map<String, String> _parseScanValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const {};

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        // Controleer of het een Gymies check-in QR is
        final type = decoded['type']?.toString() ?? '';
        if (type.isNotEmpty && type != 'gymies_checkin') {
          return {}; // Niet onze QR → negeren
        }

        final bookingId = (decoded['booking_id'] ??
                decoded['bookingId'] ??
                decoded['id'] ??
                '')
            .toString()
            .trim();
        final token =
            (decoded['token'] ?? decoded['qr_token'] ?? '').toString().trim();

        return {
          if (bookingId.isNotEmpty) 'booking_id': bookingId,
          if (token.isNotEmpty) 'token': token,
          'payload': trimmed,
        };
      }
    } catch (_) {
      // Niet-JSON payload → probeer als plain booking ID
    }

    // Fallback: als het een numeriek ID lijkt, behandel als booking_id
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return {'booking_id': trimmed, 'payload': trimmed};
    }

    return {'payload': trimmed};
  }

  // ── Check-in verwerken ────────────────────────────────────────
  Future<void> _submitCheckIn({
    required String bookingId,
    String? token,
    String? payload,
    String source = 'trainer_scan',
  }) async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _statusMessage = 'Check-in verwerken...';
    });

    HapticFeedback.mediumImpact();

    try {
      await context.read<GymiesApi>().markBookingCheckedIn(
        bookingId: bookingId,
        qrToken: token,
        payload: payload,
        source: source,
      );

      await ActionRetryQueueService.log(
        actionType: 'trainer_check_in',
        status: 'sent',
        payload: {
          'booking_id': bookingId,
          if (token != null) 'token': token,
          'source': source,
        },
        detail: 'Check-in direct gelukt',
      );

      if (!mounted) return;

      // Success state
      HapticFeedback.heavyImpact();
      setState(() {
        _showSuccess = true;
        _processing = false;
        _statusMessage = null;
      });

      _successController.forward();

      // Wacht even, dan terug
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      // Offline → retry queue
      await ActionRetryQueueService.enqueue(
        actionType: 'trainer_check_in',
        payload: {
          'booking_id': bookingId,
          if (token != null) 'token': token,
          'source': source,
        },
        reason: e.message,
      );

      if (!mounted) return;
      HapticFeedback.heavyImpact();

      // Reset _lastValue zodat opnieuw scannen mogelijk is
      _lastValue = null;

      setState(() {
        _processing = false;
        _statusMessage = null;
      });

      _showErrorSheet(
        title: 'Check-in offline opgeslagen',
        message: 'Geen verbinding. De check-in is opgeslagen en wordt '
            'automatisch verstuurd zodra je weer online bent.',
        icon: Icons.cloud_off_rounded,
        iconColor: Colors.orange,
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _lastValue = null; // Reset zodat opnieuw scannen kan

      setState(() {
        _processing = false;
        _statusMessage = null;
      });

      _showErrorSheet(
        title: 'Check-in mislukt',
        message: 'Er ging iets mis. Probeer opnieuw te scannen of '
            'gebruik de handmatige check-in.',
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
      );
    }
  }

  // ── Scan handler ──────────────────────────────────────────────
  Future<void> _handleScan(String rawValue) async {
    if (_processing || _showSuccess) return;
    if (_lastValue == rawValue) return;
    _lastValue = rawValue;

    HapticFeedback.selectionClick();

    final parsed = _parseScanValue(rawValue);
    final bookingId = (parsed['booking_id'] ?? '').trim();
    final token = parsed['token'];
    final payload = parsed['payload'] ?? rawValue;

    if (bookingId.isEmpty && (token == null || token.isEmpty)) {
      _lastValue = null; // Reset zodat een andere QR wél gescand kan worden
      _showErrorSheet(
        title: 'Ongeldige QR-code',
        message:
            'Deze QR-code bevat geen geldige check-in data. '
            'Vraag de klant om een nieuwe QR-code te genereren in de app.',
        icon: Icons.qr_code_scanner_rounded,
        iconColor: Colors.orange,
      );
      return;
    }

    await _submitCheckIn(
      bookingId: bookingId,
      token: token,
      payload: payload,
    );
  }

  // ── Handmatige check-in ───────────────────────────────────────
  Future<void> _openManualCheckIn() async {
    final codeController = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              Row(
                children: [
                  Icon(Icons.dialpad_rounded,
                      color: GymiesColors.darkBlue, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Handmatige check-in',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Voer de 6-cijferige backup code in die de klant op '
                'het scherm heeft staan.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: codeController,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  color: GymiesColors.darkBlue,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade300,
                    fontSize: 32,
                    letterSpacing: 8,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: GymiesColors.primary,
                      width: 2,
                    ),
                  ),
                ),
                onSubmitted: (val) {
                  if (val.length == 6) Navigator.of(ctx).pop(val);
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final code = codeController.text.trim();
                    if (code.length == 6) {
                      Navigator.of(ctx).pop(code);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    foregroundColor: GymiesColors.darkBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Inchecken',
                    style: GoogleFonts.fjallaOne(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (result == null || result.length != 6 || !mounted) return;

    // Handmatige check-in via backup code: we hebben geen booking_id
    // De backup code is uniek per actieve boeking, dus de backend kan
    // de boeking vinden op basis van de code
    setState(() {
      _processing = true;
      _statusMessage = 'Backup code verifiëren...';
    });

    HapticFeedback.mediumImpact();

    try {
      final api = context.read<GymiesApi>();
      await api.manualCheckin(backupCode: result);

      if (!mounted) return;
      HapticFeedback.heavyImpact();

      setState(() {
        _showSuccess = true;
        _processing = false;
        _statusMessage = null;
      });
      _successController.forward();

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _processing = false;
        _statusMessage = null;
      });
      _showErrorSheet(
        title: 'Code ongeldig',
        message: e.message.isNotEmpty
            ? e.message
            : 'De backup code is ongeldig of verlopen. '
                'Vraag de klant een nieuwe code op te vragen.',
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _statusMessage = null;
      });
      _showErrorSheet(
        title: 'Fout',
        message: 'Er ging iets mis. Probeer het opnieuw.',
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
      );
    }
  }

  // ── Error bottom sheet ────────────────────────────────────────
  void _showErrorSheet({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.fjallaOne(
                fontSize: 18,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.darkBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Begrepen'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera ──────────────────────────────────────────
          if (!_showSuccess)
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                final code = capture.barcodes.isNotEmpty
                    ? (capture.barcodes.first.rawValue ?? '')
                    : '';
                if (code.isEmpty) return;
                _handleScan(code);
              },
            ),

          // ── Success overlay ────────────────────────────────
          if (_showSuccess)
            Container(
              color: Colors.green.shade600,
              child: Center(
                child: AnimatedBuilder(
                  animation: _successController,
                  builder: (ctx, child) => Opacity(
                    opacity: _successOpacity.value,
                    child: Transform.scale(
                      scale: _successScale.value,
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 72,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Ingecheckt!',
                        style: GoogleFonts.fjallaOne(
                          fontSize: 28,
                          color: Colors.white,
                        ),
                      ),
                      if (_successName.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _successName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // ── Viewfinder overlay ─────────────────────────────
          if (!_showSuccess) _buildViewfinderOverlay(),

          // ── Top bar ────────────────────────────────────────
          if (!_showSuccess)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: Colors.white,
                          iconSize: 26,
                        ),
                        const Spacer(),
                        Text(
                          'Scan check-in QR',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Zaklamp',
                          onPressed: () async {
                            await _controller.toggleTorch();
                            if (!mounted) return;
                            setState(() => _torchOn = !_torchOn);
                            HapticFeedback.selectionClick();
                          },
                          icon: Icon(
                            _torchOn
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            color: _torchOn
                                ? GymiesColors.primary
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Bottom controls ────────────────────────────────
          if (!_showSuccess)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Status tekst
                        Text(
                          _statusMessage ??
                              'Richt de camera op de QR-code van de klant',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Handmatige check-in knop
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                _processing ? null : _openManualCheckIn,
                            icon: const Icon(
                                Icons.dialpad_rounded, size: 20),
                            label: const Text('Backup code invoeren'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color:
                                    Colors.white.withValues(alpha: 0.3),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
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

  // ── Viewfinder overlay met animated corners ───────────────────
  Widget _buildViewfinderOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanSize = constraints.maxWidth * 0.7;
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight * 0.42;

        return Stack(
          children: [
            // Dimmed overlay met transparant vierkant
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _ViewfinderPainter(
                scanSize: scanSize,
                centerX: centerX,
                centerY: centerY,
              ),
            ),

            // Animated corners
            Positioned(
              left: centerX - scanSize / 2,
              top: centerY - scanSize / 2,
              child: AnimatedBuilder(
                animation: _cornerPulse,
                builder: (ctx, child) => CustomPaint(
                  size: Size(scanSize, scanSize),
                  painter: _CornerPainter(
                    color: GymiesColors.primary,
                    opacity: _cornerPulse.value,
                  ),
                ),
              ),
            ),

            // Scan line
            Positioned(
              left: centerX - scanSize / 2 + 20,
              top: centerY - scanSize / 2,
              child: AnimatedBuilder(
                animation: _scanLineController,
                builder: (ctx, child) => Transform.translate(
                  offset:
                      Offset(0, _scanLineController.value * (scanSize - 4)),
                  child: Container(
                    width: scanSize - 40,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          GymiesColors.primary.withValues(alpha: 0.8),
                          GymiesColors.primary,
                          GymiesColors.primary.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              GymiesColors.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Processing indicator
            if (_processing)
              Positioned(
                left: centerX - scanSize / 2,
                top: centerY - scanSize / 2,
                child: Container(
                  width: scanSize,
                  height: scanSize,
                  decoration: BoxDecoration(
                    color: GymiesColors.darkBlue.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: GymiesColors.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage ?? 'Verwerken...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Custom painters ──────────────────────────────────────────────

/// Tekent de donkere overlay met een transparant vierkant in het midden.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({
    required this.scanSize,
    required this.centerX,
    required this.centerY,
  });

  final double scanSize;
  final double centerX;
  final double centerY;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final scanRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: scanSize,
        height: scanSize,
      ),
      const Radius.circular(16),
    );

    // Teken de volledige overlay
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(scanRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter old) =>
      old.scanSize != scanSize;
}

/// Tekent de geanimeerde hoekmarkeringen van de viewfinder.
class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 30.0;
    const radius = 16.0;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, cornerLen)
        ..lineTo(0, radius)
        ..quadraticBezierTo(0, 0, radius, 0)
        ..lineTo(cornerLen, 0),
      paint,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLen, 0)
        ..lineTo(size.width - radius, 0)
        ..quadraticBezierTo(size.width, 0, size.width, radius)
        ..lineTo(size.width, cornerLen),
      paint,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - cornerLen)
        ..lineTo(0, size.height - radius)
        ..quadraticBezierTo(0, size.height, radius, size.height)
        ..lineTo(cornerLen, size.height),
      paint,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLen, size.height)
        ..lineTo(size.width - radius, size.height)
        ..quadraticBezierTo(
            size.width, size.height, size.width, size.height - radius)
        ..lineTo(size.width, size.height - cornerLen),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.opacity != opacity || old.color != color;
}
