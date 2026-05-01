import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/action_retry_queue_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';

class TrainerCheckInScannerScreen extends StatefulWidget {
  const TrainerCheckInScannerScreen({super.key});

  @override
  State<TrainerCheckInScannerScreen> createState() =>
      _TrainerCheckInScannerScreenState();
}

class _TrainerCheckInScannerScreenState
    extends State<TrainerCheckInScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;
  bool _torchOn = false;
  String? _lastValue;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  Map<String, String> _parseScanValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const {};
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final bookingId =
            (decoded['booking_id'] ??
                    decoded['bookingId'] ??
                    decoded['id'] ??
                    '')
                .toString();
        final token = (decoded['token'] ?? decoded['qr_token'] ?? '')
            .toString();
        return {
          if (bookingId.isNotEmpty) 'booking_id': bookingId,
          if (token.isNotEmpty) 'token': token,
          'payload': trimmed,
        };
      }
    } catch (_) {
      // Not a JSON payload; fall through.
    }
    return {'payload': trimmed};
  }

  Future<void> _submitCheckIn({
    required String bookingId,
    String? token,
    String? payload,
  }) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await context.read<GymiesApi>().markBookingCheckedIn(
        bookingId: bookingId,
        qrToken: token,
        payload: payload,
      );
      await ActionRetryQueueService.log(
        actionType: 'trainer_check_in',
        status: 'sent',
        payload: {
          'booking_id': bookingId,
          ...?(token == null ? null : {'token': token}),
          ...?(payload == null ? null : {'payload': payload}),
        },
        detail: 'Scanner check-in direct gelukt',
      );
      if (!mounted) return;
      _showSuccess('Check-in geregistreerd voor boeking $bookingId');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      await ActionRetryQueueService.enqueue(
        actionType: 'trainer_check_in',
        payload: {
          'booking_id': bookingId,
          ...?(token == null ? null : {'token': token}),
          ...?(payload == null ? null : {'payload': payload}),
        },
        reason: e.message,
      );
      _showError(
        'Check-in tijdelijk offline opgeslagen en komt in de retry-queue.',
      );
    } catch (_) {
      _showError('Check-in mislukt. Probeer opnieuw.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _handleScan(String rawValue) async {
    if (_processing) return;
    if (_lastValue == rawValue) return;
    _lastValue = rawValue;
    final parsed = _parseScanValue(rawValue);
    final bookingId = (parsed['booking_id'] ?? '').trim();
    final token = parsed['token'];
    final payload = parsed['payload'] ?? rawValue;
    if (bookingId.isEmpty) {
      _showError(
        'Geen booking_id gevonden in QR. Gebruik handmatige check-in.',
      );
      return;
    }
    await _submitCheckIn(bookingId: bookingId, token: token, payload: payload);
  }

  Future<void> _openManualCheckIn() async {
    final bookingController = TextEditingController();
    final tokenController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Handmatige check-in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: bookingController,
              decoration: const InputDecoration(labelText: 'Booking ID'),
            ),
            TextField(
              controller: tokenController,
              decoration: const InputDecoration(labelText: 'Token (optioneel)'),
            ),
          ],
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
            child: const Text('Inchecken'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final bookingId = bookingController.text.trim();
    final token = tokenController.text.trim();
    if (bookingId.isEmpty) {
      _showError('Booking ID is verplicht.');
      return;
    }
    await _submitCheckIn(
      bookingId: bookingId,
      token: token.isEmpty ? null : token,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        title: Text(
          'Scan check-in QR',
          style: GoogleFonts.fjallaOne(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Zaklamp',
            onPressed: () async {
              await _controller.toggleTorch();
              if (!mounted) return;
              setState(() => _torchOn = !_torchOn);
            },
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
          IconButton(
            tooltip: 'Handmatig',
            onPressed: _processing ? null : _openManualCheckIn,
            icon: const Icon(Icons.keyboard_alt_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black.withValues(alpha: 0.55),
              padding: const EdgeInsets.all(14),
              child: Text(
                _processing
                    ? 'Check-in verwerken...'
                    : 'Richt de camera op de QR-code van de klant',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
