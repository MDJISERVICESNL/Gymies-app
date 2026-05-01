import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../utils/haptics.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/trainer_state_views.dart';

/// Klant-scherm voor overzicht van standby / wachtlijst-inschrijvingen.
class ClientWaitlistScreen extends StatefulWidget {
  const ClientWaitlistScreen({super.key});

  @override
  State<ClientWaitlistScreen> createState() => _ClientWaitlistScreenState();
}

class _ClientWaitlistScreenState extends State<ClientWaitlistScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _waitlist = [];

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final list = await api.getMyWaitlistEntries();
      if (!mounted) return;
      setState(() {
        _waitlist = list;
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
        _error = 'Kon wachtlijsten niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _removeEntry(Map<String, dynamic> item) async {
    final id = mapStr(item, ['id', 'waitlist_id', 'waitlistId']);
    if (id.isEmpty) return;

    final ok = await GymiesDialog.destructive(
      context,
      title: 'Standby verwijderen',
      message:
          'Weet je zeker dat je je standby-inschrijving wilt verwijderen? Je verliest je plek op de wachtlijst.',
      confirmLabel: 'Ja, verwijderen',
    );
    if (ok != true || !mounted) return;

    try {
      await context.read<GymiesApi>().leaveWaitlistEntry(id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Standby-inschrijving verwijderd'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mijn wachtlijsten',
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GymiesListBody(
              loading: _loading,
              error: _error,
              onRefresh: _load,
              child: _waitlist.isEmpty
                ? _buildEmpty()
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Je staat op de standby-lijst van de volgende trainer(s). Zodra er plek vrijkomt, krijg je een melding.',
                          style: GoogleFonts.sora(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      ..._waitlist.map((w) => _WaitlistCard(
                        item: w,
                        onRemove: () => _removeEntry(w),
                      )),
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: GymiesColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.event_busy_rounded,
            size: 32,
            color: GymiesColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Geen standby-inschrijvingen',
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: GymiesColors.darkBlue,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Je staat nog op geen wachtlijst. Ga naar het profiel van een trainer en klik op "Wachtlijst" om je in te schrijven als er geen plek is.',
          style: GoogleFonts.sora(
            color: Colors.grey.shade600,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _WaitlistCard extends StatelessWidget {
  const _WaitlistCard({
    required this.item,
    required this.onRemove,
  });

  final Map<String, dynamic> item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final trainer = mapStr(item, ['trainer_name', 'trainerName', 'name']);
    final preferredAt = mapStr(item, ['preferred_at', 'preferredAt', 'date']);
    final requestedFor = mapStr(item, ['requested_for_scheduled_at']);
    final note = mapStr(item, ['note', 'notes', 'message']);

    String dateLabel = '';
    if (requestedFor.isNotEmpty) {
      dateLabel = 'Voor sessie: ${_formatDate(requestedFor)}';
    } else if (preferredAt.isNotEmpty) {
      dateLabel = 'Voorkeur: ${_formatDate(preferredAt)}';
    } else {
      dateLabel = 'Standby actief – je krijgt een melding bij vrije plek';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
          child: Icon(
            Icons.person_outline_rounded,
            color: GymiesColors.darkBlue,
          ),
        ),
        title: Text(
          trainer.isEmpty ? 'Trainer' : trainer,
          style: GoogleFonts.sora(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateLabel,
              style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 13),
            ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  note,
                  style: GoogleFonts.sora(color: Colors.grey.shade700, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        trailing: IconButton(
          onPressed: () {
            Haptics.heavy();
            onRemove();
          },
          icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
          tooltip: 'Verwijderen',
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return raw;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length > 16 ? raw.substring(0, 16) : raw;
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
