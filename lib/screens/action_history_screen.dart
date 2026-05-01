import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/action_retry_queue_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'client_support_screen.dart';

class ActionHistoryScreen extends StatefulWidget {
  const ActionHistoryScreen({super.key});

  @override
  State<ActionHistoryScreen> createState() => _ActionHistoryScreenState();
}

class _ActionHistoryScreenState extends State<ActionHistoryScreen> {
  bool _loading = true;
  bool _flushing = false;
  List<Map<String, dynamic>> _queue = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final queue = await ActionRetryQueueService.getQueue();
    final history = await ActionRetryQueueService.getHistory();
    if (!mounted) return;
    setState(() {
      _queue = queue;
      _history = history;
      _loading = false;
    });
  }

  Future<void> _flushNow() async {
    if (_flushing) return;
    setState(() => _flushing = true);
    try {
      final sent = await ActionRetryQueueService.flushPending(
        context.read<GymiesApi>(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retry klaar: $sent actie(s) verstuurd')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _flushing = false);
    }
  }

  Future<void> _openIncidentSupport() async {
    final draft = await ActionRetryQueueService.buildIncidentSupportDraft(
      contextLabel: 'ActionHistory',
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientSupportScreen(
          initialType: draft['type'],
          initialSubject: draft['subject'],
          initialMessage: draft['message'],
          initialBookingId: draft['booking_id'],
          initialInvoiceId: draft['invoice_id'],
          openComposerOnStart: true,
        ),
      ),
    );
    if (mounted) await _load();
  }

  String _str(Map<String, dynamic> map, String key) =>
      (map[key] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        title: Text('Actiegeschiedenis', style: GoogleFonts.sora()),
        actions: [
          IconButton(
            tooltip: 'Retry wachtrij',
            onPressed: _flushing ? null : () {
              Haptics.light();
              _flushNow();
            },
            icon: _flushing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.pending_actions_rounded),
                      title: const Text('Wachtrij'),
                      subtitle: Text('${_queue.length} actie(s) in retry queue'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            onPressed: _flushing ? null : () {
                              Haptics.light();
                              _flushNow();
                            },
                            child: const Text('Retry nu'),
                          ),
                          const SizedBox(width: 6),
                          if (_queue.any(
                            (e) =>
                                (e['status'] ?? '').toString().toLowerCase() ==
                                'failed',
                          ))
                            FilledButton(
                              onPressed: () {
                                Haptics.light();
                                _openIncidentSupport();
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Escaleren'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Recente events',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('Nog geen events'),
                        subtitle: Text('Uitgevoerde en gequeue-de acties verschijnen hier.'),
                      ),
                    )
                  else
                    ..._history.take(120).map((h) {
                      final status = _str(h, 'status');
                      final type = _str(h, 'action_type');
                      final created = _str(h, 'created_at');
                      final detail = _str(h, 'detail');
                      Color color;
                      switch (status) {
                        case 'sent':
                          color = Colors.green.shade700;
                          break;
                        case 'queued':
                          color = Colors.orange.shade800;
                          break;
                        case 'failed':
                          color = Colors.red.shade700;
                          break;
                        default:
                          color = Colors.blueGrey.shade700;
                      }
                      return Card(
                        child: ListTile(
                          leading: Icon(Icons.history_rounded, color: color),
                          title: Text(type.isEmpty ? 'actie' : type),
                          subtitle: Text(
                            '${status.isEmpty ? 'unknown' : status} · $created\n${detail.isEmpty ? '-' : detail}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
