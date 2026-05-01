import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/booking.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';

class ClientCheckInQrScreen extends StatefulWidget {
  const ClientCheckInQrScreen({super.key, required this.booking});

  final Booking booking;

  @override
  State<ClientCheckInQrScreen> createState() => _ClientCheckInQrScreenState();
}

class _ClientCheckInQrScreenState extends State<ClientCheckInQrScreen> {
  bool _loading = true;
  String? _error;
  String _qrPayload = '';
  String _code = '';
  bool _usingFallback = false;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final booking = widget.booking;
    try {
      final api = context.read<GymiesApi>();
      final data = await api.getBookingCheckInQr(booking.id);
      final bookingId = _str(data, ['booking_id', 'bookingId', 'id']).isNotEmpty
          ? _str(data, ['booking_id', 'bookingId', 'id'])
          : booking.id;
      final token = _str(data, ['token', 'qr_token', 'checkin_token']);
      final value = _str(data, ['qr_value', 'value', 'payload', 'qr']);
      final fallbackPayload = jsonEncode({
        'type': 'gymies_checkin',
        'booking_id': bookingId,
        if (token.isNotEmpty) 'token': token,
      });
      if (!mounted) return;
      setState(() {
        _qrPayload = value.isNotEmpty ? value : fallbackPayload;
        _code = token.isNotEmpty ? token : bookingId;
        _usingFallback = value.isEmpty;
        _loading = false;
      });
    } on ApiException catch (_) {
      final fallbackPayload = jsonEncode({
        'type': 'gymies_checkin',
        'booking_id': booking.id,
        'token': 'LOCAL-${booking.id}-${DateTime.now().millisecondsSinceEpoch}',
      });
      if (!mounted) return;
      setState(() {
        _qrPayload = fallbackPayload;
        _code = booking.id;
        _usingFallback = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon QR-code niet laden.';
        _loading = false;
      });
    }
  }

  String _str(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key].toString();
      }
    }
    return '';
  }

  Future<void> _sendSos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SOS-alert'),
        content: const Text(
          'Weet je zeker dat je een noodalert wilt versturen? '
          'Hulp wordt direct ingeschakeld.',
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
      await context.read<GymiesApi>().sendSosAlert(bookingId: widget.booking.id);
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

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final date =
        '${booking.scheduledAt.day.toString().padLeft(2, '0')}-${booking.scheduledAt.month.toString().padLeft(2, '0')}-${booking.scheduledAt.year}';
    final time =
        '${booking.scheduledAt.hour.toString().padLeft(2, '0')}:${booking.scheduledAt.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.emergency_rounded),
            onPressed: _sendSos,
            tooltip: 'SOS-alert',
          ),
        ],
        title: Text(
          'Check-in QR',
          style: GoogleFonts.fjallaOne(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 42,
                    ),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadQr,
                      style: FilledButton.styleFrom(
                        backgroundColor: GymiesColors.primary,
                        foregroundColor: GymiesColors.darkBlue,
                      ),
                      child: const Text('Opnieuw proberen'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_available_rounded),
                    title: Text(
                      booking.trainerName.isEmpty
                          ? 'Trainer'
                          : booking.trainerName,
                    ),
                    subtitle: Text('$date om $time'),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        QrImageView(
                          data: _qrPayload,
                          size: 240,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Laat deze QR-code scannen door de trainer om in te checken.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          'Code: $_code',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_usingFallback) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: Colors.orange.shade50,
                    child: const ListTile(
                      leading: Icon(Icons.info_outline, color: Colors.orange),
                      title: Text('Lokale test QR'),
                      subtitle: Text(
                        'Backend QR endpoint niet gevonden. Deze code werkt voor app-flow tests.',
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
