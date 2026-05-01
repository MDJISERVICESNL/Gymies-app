import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../config/timing_constants.dart';
import '../theme/gymies_theme.dart';
import '../models/trainer_models.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import 'trainer_chat_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';
import '../utils/haptics.dart';

/// Berichtenoverzicht voor trainer.
class TrainerMessagesScreen extends StatefulWidget {
  const TrainerMessagesScreen({super.key});

  @override
  State<TrainerMessagesScreen> createState() => _TrainerMessagesScreenState();
}

class _TrainerMessagesScreenState extends State<TrainerMessagesScreen>
    with WidgetsBindingObserver {
  List<TrainerConversation> _conversations = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _unreadOnly = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(TimingConstants.trainerRefreshInterval, (_) {
      if (!mounted) return;
      _load(background: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startTimer();
      if (mounted) _load(background: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool background = false}) async {
    if (!mounted) return;
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (_error != null) {
      setState(() => _error = null);
    }
    try {
      final api = context.read<GymiesApi>();
      final list = await api.getTrainerConversations();
      list.sort((a, b) {
        final ad =
            DateTime.tryParse(a.lastMessageAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            DateTime.tryParse(b.lastMessageAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
        if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
        return bd.compareTo(ad);
      });
      if (mounted) {
        setState(() {
          _conversations = list;
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
      if (kDebugMode) debugPrint('[TrainerMessages] Berichten laden fout: $e');
      if (mounted) {
        setState(() {
          _error = 'Kon berichten niet laden.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _conversations.where((c) {
      if (_unreadOnly && c.unreadCount <= 0) return false;
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      return c.clientName.toLowerCase().contains(q) ||
          (c.lastMessage ?? '').toLowerCase().contains(q);
    }).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: 'Berichten',
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _conversations.isEmpty
                  ? ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        TrainerEmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: 'Geen berichten',
                          subtitle:
                              'Nieuwe chats van klanten verschijnen hier zodra er een bericht binnenkomt.',
                          actionLabel: 'Ververs berichten',
                          onAction: _load,
                          padding: const EdgeInsets.all(32),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      children: [
                        TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: 'Zoek op klant of laatste bericht',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilterChip(
                          selected: _unreadOnly,
                          onSelected: (v) {
                            Haptics.selection();
                            setState(() => _unreadOnly = v);
                          },
                          label: const Text('Alleen ongelezen'),
                        ),
                        const SizedBox(height: 10),
                        if (filtered.isEmpty)
                          const TrainerEmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'Geen resultaten',
                            subtitle: 'Pas je zoekterm of filter aan.',
                            padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
                          )
                        else
                          ...filtered.asMap().entries.map((entry) {
                            final i = entry.key;
                            final c = entry.value;
                            final lastAt = DateTime.tryParse(
                              c.lastMessageAt ?? '',
                            );
                            final lastAtLabel = lastAt == null
                                ? ''
                                : '${lastAt.day.toString().padLeft(2, '0')}-${lastAt.month.toString().padLeft(2, '0')} ${lastAt.hour.toString().padLeft(2, '0')}:${lastAt.minute.toString().padLeft(2, '0')}';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Dismissible(
                                key: Key(c.id.isNotEmpty ? c.id : 'conv_$i'),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (direction) async {
                                  Haptics.heavy();
                                  if (c.id.isNotEmpty) {
                                    try {
                                      await context.read<GymiesApi>().deleteTrainerConversation(c.id);
                                    } catch (e) {
                                      if (kDebugMode) debugPrint('[TrainerMessages] Gesprek verwijderen API fout: $e');
                                    }
                                  }
                                  return true;
                                },
                                onDismissed: (direction) {
                                  if (mounted) {
                                    setState(() {
                                      _conversations.remove(c);
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('Gesprek verwijderd'),
                                        backgroundColor: GymiesColors.darkBlue,
                                        action: SnackBarAction(
                                          label: 'Herstellen',
                                          textColor: GymiesColors.primary,
                                          onPressed: () => _load(),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                background: Container(
                                  color: Colors.red.shade600,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  child: const Icon(
                                    Icons.delete_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: GymiesColors.primary.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          c.clientName.isNotEmpty
                                              ? c.clientName[0].toUpperCase()
                                              : '?',
                                          style: GoogleFonts.sora(
                                            color: GymiesColors.darkBlue,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            c.clientName,
                                            style: GoogleFonts.sora(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        if (c.unreadCount > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: GymiesColors.primary,
                                              borderRadius: BorderRadius.circular(
                                                12,
                                              ),
                                            ),
                                            child: Text(
                                              '${c.unreadCount}',
                                              style: GoogleFonts.sora(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: GymiesColors.darkBlue,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (c.lastMessage != null)
                                          Text(
                                            c.lastMessage!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.sora(
                                              fontSize: 13,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        if (lastAtLabel.isNotEmpty)
                                          Text(
                                            lastAtLabel,
                                            style: GoogleFonts.sora(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () {
                                      Haptics.selection();
                                      Navigator.of(context)
                                          .push(
                                            MaterialPageRoute(
                                              builder: (_) => TrainerChatScreen(
                                                conversation: c,
                                              ),
                                            ),
                                          )
                                          .then((_) => _load());
                                    },
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
            ),
    );
  }
}
