import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class GymBookingsScreen extends StatefulWidget {
  const GymBookingsScreen({super.key});

  @override
  State<GymBookingsScreen> createState() => _GymBookingsScreenState();
}

class _GymBookingsScreenState extends State<GymBookingsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bookings = [];

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
      final list = await context.read<GymiesApi>().getGymBookings();
      if (!mounted) return;
      setState(() {
        _bookings = list;
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
        _error = 'Kon boekingen niet laden.';
        _loading = false;
      });
    }
  }

  DateTime _date(Map<String, dynamic> m, List<String> keys) {
    final raw = mapStr(m, keys);
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Boekingen'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _bookings.isEmpty
            ? ListView(
                children: [
                  TrainerEmptyState(
                    icon: Icons.event_available_rounded,
                    title: 'Geen boekingen',
                    subtitle: 'Er zijn nog geen boekingen in dit overzicht.',
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _bookings.length,
                itemBuilder: (_, i) {
                  final b = _bookings[i];
                  final dt = _date(b, ['scheduled_at', 'scheduledAt']);
                  return GestureDetector(
                    onTap: () => Haptics.selection(),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(
                          mapStr(b, ['client_name', 'trainer_name']),
                          style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} · ${mapStr(b, ['status'])}',
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
