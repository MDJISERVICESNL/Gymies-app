import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/haptics.dart';

import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../services/notification_realtime_service.dart';
import '../theme/gymies_theme.dart';
import '../models/booking.dart';
import '../models/trainer.dart';
import 'client_check_in_qr_screen.dart';
import 'client_favorites_standalone_screen.dart';
import 'client_invoices_screen.dart';
import 'client_notifications_screen.dart';
import 'client_trainer_profile_screen.dart';
import 'client_support_screen.dart';
import 'client_group_sessions_screen.dart';
import 'client_dossier_screen.dart';
import 'shells/client_shell.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late List<CurvedAnimation> _staggeredAnimations;

  Map<String, dynamic>? _stats;
  bool _loadingStats = true;
  List<Booking> _allBookings = [];
  bool _noSessionDismissed = false;
  Timer? _countdownTimer;

  // Weekkalender state: per dag → status
  Map<int, _DayStatus> _weekDayStatus = {}; // 0=Ma … 6=Zo

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
    _loadStats();
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _initializeAnimation() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _staggeredAnimations = List.generate(
      5,
      (index) => CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          index * 0.10,
          (index * 0.10) + 0.5,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _animationController.forward();
  }

  /// Dynamische begroeting op basis van tijdstip
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'Goedenacht';
    if (hour < 12) return 'Goedemorgen';
    if (hour < 18) return 'Goedemiddag';
    return 'Goedenavond';
  }

  /// Bereken trainingsstreak (opeenvolgende weken met minstens 1 sessie)
  int _calculateStreak(List<Booking> completedBookings) {
    if (completedBookings.isEmpty) return 0;

    final now = DateTime.now();
    // Huidige week maandag
    final currentMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    int streak = 0;
    var checkMonday = currentMonday;

    // Ga weken terug en check of er minstens 1 voltooide sessie in zit
    for (int i = 0; i < 52; i++) {
      final weekEnd = checkMonday.add(const Duration(days: 7));
      final hasSession = completedBookings.any((b) =>
          !b.scheduledAt.isBefore(checkMonday) &&
          b.scheduledAt.isBefore(weekEnd));

      if (hasSession) {
        streak++;
        checkMonday = checkMonday.subtract(const Duration(days: 7));
      } else if (i == 0) {
        // Huidige week nog geen sessie → check of we al sessies hadden
        checkMonday = checkMonday.subtract(const Duration(days: 7));
        continue;
      } else {
        break;
      }
    }

    return streak;
  }

  /// Volgende aankomende sessie ophalen
  Booking? _nextSession() {
    final now = DateTime.now();
    final upcoming = _allBookings
        .where((b) =>
            b.scheduledAt.isAfter(now) &&
            b.status != 'cancelled' &&
            b.status != 'no_show')
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return upcoming.isNotEmpty ? upcoming.first : null;
  }

  /// Persoonlijke tip op basis van trainingsdata
  String _smartTip() {
    final thisWeek = _stats?['this_week'] ?? 0;
    final weekGoal = _stats?['week_goal'] ?? 3;
    final streak = _stats?['streak'] ?? 0;
    final total = _stats?['total'] ?? 0;

    if (total == 0) {
      return 'Welkom bij Gymies! Boek je eerste sessie en begin je fitnessreis.';
    }

    // Near milestone: if total > 0 and (total % 10) >= 8
    if (total > 0 && (total % 10) >= 8) {
      final nextMilestone = ((total ~/ 10) + 1) * 10;
      final remaining = nextMilestone - total;
      return 'Nog $remaining sessie${remaining == 1 ? '' : 's'} tot je volgende milestone ($nextMilestone)!';
    }

    // Long time since last session
    if (_allBookings.isNotEmpty) {
      final completedBookings = _allBookings
          .where((b) =>
              b.status == 'completed' ||
              b.status == 'confirmed' ||
              b.status == 'checked_in' ||
              b.status == 'done')
          .toList();
      if (completedBookings.isNotEmpty) {
        completedBookings.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
        final lastSession = completedBookings.first.scheduledAt;
        final daysSince = DateTime.now().difference(lastSession).inDays;
        if (daysSince > 7) {
          return 'Je laatste sessie was $daysSince dagen geleden. Tijd om weer te starten!';
        }
      }
    }

    if (thisWeek >= weekGoal) {
      return 'Weekdoel behaald! Je hebt al $thisWeek sessie${thisWeek == 1 ? '' : 's'} gedaan. Lekker bezig!';
    }
    if (thisWeek > 0) {
      final remaining = weekGoal - thisWeek;
      return 'Nog $remaining sessie${remaining == 1 ? '' : 's'} te gaan deze week. Je zit op $thisWeek van $weekGoal!';
    }
    if (streak > 0) {
      return 'Je hebt een streak van $streak ${streak == 1 ? 'week' : 'weken'}. Plan een sessie om hem vast te houden!';
    }
    return 'Train minstens 3x per week voor optimaal resultaat. Plan je eerste sessie van de week!';
  }

  Future<void> _loadStats() async {
    try {
      final api = context.read<GymiesApi>();
      final bookings = await api.getBookings();
      final now = DateTime.now();
      final thisWeekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final thisWeekEnd = thisWeekStart.add(const Duration(days: 7));

      // Load week goal: server intake → local fallback
      final prefs = await SharedPreferences.getInstance();
      int weekGoal = prefs.getInt('gymies_week_goal') ?? 3;
      try {
        final api = context.read<GymiesApi>();
        final intake = await api.getIntake();
        final serverVal = intake['training_frequency_preferred'];
        if (serverVal != null) {
          final parsed = int.tryParse(serverVal.toString());
          if (parsed != null && parsed > 0) {
            weekGoal = parsed;
            await prefs.setInt('gymies_week_goal', weekGoal);
          }
        }
      } catch (_) {}

      // Weekkalender: status per dag berekenen
      final dayStatus = <int, _DayStatus>{};
      for (int i = 0; i < 7; i++) {
        dayStatus[i] = _DayStatus.none;
      }

      for (final b in bookings) {
        final d = b.scheduledAt;
        if (!d.isBefore(thisWeekStart) && d.isBefore(thisWeekEnd)) {
          final dayIndex = d.weekday - 1; // 0=Ma … 6=Zo
          final isCompleted = b.status == 'completed' ||
              b.status == 'checked_in' ||
              b.status == 'done';
          final isCancelled = b.status == 'cancelled' || b.status == 'no_show';

          if (!isCancelled) {
            if (isCompleted) {
              dayStatus[dayIndex] = _DayStatus.completed;
            } else if (dayStatus[dayIndex] != _DayStatus.completed) {
              dayStatus[dayIndex] = _DayStatus.planned;
            }
          }
        }
      }

      final completedBookings = bookings
          .where((b) =>
              b.status == 'completed' ||
              b.status == 'confirmed' ||
              b.status == 'checked_in' ||
              b.status == 'done')
          .toList();

      final thisWeekCompleted = completedBookings
          .where((b) {
            final d = b.scheduledAt;
            return !d.isBefore(thisWeekStart) && d.isBefore(thisWeekEnd);
          })
          .toList();

      final streak = _calculateStreak(completedBookings);

      if (mounted) {
        setState(() {
          _allBookings = bookings;
          _weekDayStatus = dayStatus;
          _stats = {
            'streak': streak,
            'this_week': thisWeekCompleted.length,
            'week_goal': weekGoal,
            'total': completedBookings.length,
          };
          _loadingStats = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ClientHome] Stats laden mislukt: $e');
      if (mounted) {
        setState(() {
          _allBookings = [];
          _weekDayStatus = {};
          _stats = null;
          _loadingStats = false;
        });
      }
    }
  }

  void _openCheckInQr() {
    final next = _nextSession();
    if (next == null) return;
    Haptics.light();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientCheckInQrScreen(booking: next),
      ),
    );
  }

  void _openNotifications() {
    Haptics.selection();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ClientNotificationsScreen(),
      ),
    );
  }

  /// Open het openbare profiel van een trainer — haalt alleen het
  /// Trainer-object op en navigeert direct. Packages/availability/media/
  /// reviews worden async geladen door het profiel-screen zelf.
  Future<void> _openTrainerProfile(Booking booking) async {
    if (booking.trainerUserId == null) return;
    Haptics.selection();

    // Toon een korte loading indicator terwijl we het trainer-object ophalen
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: GymiesColors.primary)),
    );

    try {
      final api = context.read<GymiesApi>();
      final trainer = await api.getTrainerById(booking.trainerUserId!);
      if (trainer == null || !mounted) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // Sluit loading

      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => ClientPublicTrainerProfileScreen(
            trainer: trainer,
            onBookTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClientTrainerProfileScreen(
                    trainer: trainer,
                    focusBookingForm: true,
                  ),
                ),
              );
            },
          ),
        ),
      );

      if (!mounted) return;
      if (result == 'book') {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClientTrainerProfileScreen(
              trainer: trainer,
              focusBookingForm: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      // Fallback: open de booking screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientTrainerProfileScreen(
            trainerId: booking.trainerUserId!,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final firstName =
        (user?['display_name'] as String? ?? user?['name'] as String? ?? 'Sporter').split(' ').first;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        color: GymiesColors.primary,
        onRefresh: () async {
          setState(() => _loadingStats = true);
          await _loadStats();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Compacte header ──
            SliverAppBar(
              expandedHeight: 100,
              pinned: true,
              backgroundColor: GymiesColors.darkBlue,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: GymiesColors.darkBlue,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          DateFormat('EEEE d MMMM', 'nl_NL').format(DateTime.now()),
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: Colors.white60,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '${_greeting()}, $firstName',
                          style: GoogleFonts.sora(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: GymiesColors.primary,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: _NotificationBell(onTap: _openNotifications),
                  ),
                ),
              ],
            ),

            // ── Content ──
            SliverToBoxAdapter(
              child: _loadingStats
                ? _buildLoadingSkeleton()
                : Column(
                    children: [
                      const SizedBox(height: 16),

                      // ── 1. Volgende sessie ──
                      _buildNextSessionCard(),

                      // ── 1b. Mijn trainers ──
                      _buildMyTrainersCard(),

                      // ── 2. Stats row (inclusief streak) ──
                      _buildStatsRow(),

                      // ── 3. Weekkalender ──
                      _buildWeekCalendarCard(),

                      // ── 4. Snel naar (quick actions) ──
                      _buildQuickActions(),

                      // ── 5. Slimme tip (contextual) ──
                      _buildSmartTip(),

                      const SizedBox(height: 32),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LOADING SKELETON
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          // Sessie kaart skeleton
          _SkeletonBox(height: 160, borderRadius: 16),
          const SizedBox(height: 12),
          // Stats row skeleton
          Row(
            children: [
              Expanded(child: _SkeletonBox(height: 90, borderRadius: 14)),
              const SizedBox(width: 8),
              Expanded(child: _SkeletonBox(height: 90, borderRadius: 14)),
              const SizedBox(width: 8),
              Expanded(child: _SkeletonBox(height: 90, borderRadius: 14)),
            ],
          ),
          const SizedBox(height: 12),
          // Weekkalender skeleton
          _SkeletonBox(height: 80, borderRadius: 14),
          const SizedBox(height: 12),
          // Quick actions skeleton
          _SkeletonBox(height: 60, borderRadius: 14),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // COUNTDOWN HELPER
  // ═══════════════════════════════════════════════════════════════

  String _countdownText(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return 'Nu';
    if (diff.inMinutes < 60) return 'Over ${diff.inMinutes} min';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return m > 0 ? 'Over ${h}u ${m}m' : 'Over ${h} uur';
    }
    if (diff.inDays == 1) return 'Morgen';
    if (diff.inDays < 7) return 'Over ${diff.inDays} dagen';
    return 'Over ${diff.inDays} dagen';
  }

  // ═══════════════════════════════════════════════════════════════
  // VOLGENDE SESSIE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNextSessionCard() {
    final next = _nextSession();

    if (next == null) {
      // Geen aankomende sessie → subtiele hint
      return FadeSlideTransition(
        animation: _staggeredAnimations[0],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            decoration: BoxDecoration(
              color: GymiesColors.darkBlue.withValues(alpha:0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: GymiesColors.darkBlue.withValues(alpha:0.1),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: GymiesColors.darkBlue.withValues(alpha:0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.calendar_today_rounded,
                        color: GymiesColors.darkBlue.withValues(alpha:0.5),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Geen sessies gepland',
                            style: GoogleFonts.sora(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ga naar Ontdekken om een trainer te boeken',
                            style: GoogleFonts.sora(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        setState(() => _noSessionDismissed = true);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    Haptics.selection();
                    context.clientShell?.jumpToTab(1);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: GymiesColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Ontdek trainers',
                      style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Datum formatteren
    final dayFormat = DateFormat('EEE d MMM');
    final timeFormat = DateFormat('HH:mm');
    if (next == null) return const SizedBox.shrink();
    final endTime =
        next.scheduledAt.add(Duration(minutes: next.durationMinutes));
    final dateStr = dayFormat.format(next.scheduledAt);
    final timeStr =
        '${timeFormat.format(next.scheduledAt)} – ${timeFormat.format(endTime)}';

    // Check of sessie vandaag is
    final now = DateTime.now();
    final isToday = next.scheduledAt.year == now.year &&
        next.scheduledAt.month == now.month &&
        next.scheduledAt.day == now.day;

    return FadeSlideTransition(
      animation: _staggeredAnimations[0],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                GymiesColors.darkBlue,
                GymiesColors.darkBlue.withValues(alpha:0.88),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: GymiesColors.darkBlue.withValues(alpha:0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Label
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isToday ? 'VANDAAG' : 'VOLGENDE SESSIE',
                      style: GoogleFonts.sora(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.primary,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Trainer naam
              Text(
                'Met ${next.trainerName}',
                style: GoogleFonts.sora(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),

              // Datum + tijd + countdown
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: Colors.white60,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$dateStr  •  $timeStr',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                  const Spacer(),
                  // ── Countdown chip ──
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _countdownText(next.scheduledAt),
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.primary,
                      ),
                    ),
                  ),
                ],
              ),

              // Sessie type als beschikbaar
              if (next.sessionType != null &&
                  next.sessionType!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.fitness_center_rounded,
                      color: Colors.white60,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      next.sessionType!,
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // Actieknoppen — check-in alleen binnen 15 min window
              Row(
                children: [
                  if (_isWithinCheckInWindow(next)) ...[
                    // Check-in (primary) — alleen zichtbaar binnen 15 min
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Haptics.light();
                          _openCheckInQr();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: GymiesColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_rounded,
                                color: GymiesColors.darkBlue,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Check in',
                                style: GoogleFonts.sora(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],

                  // Bekijk trainer
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        _openTrainerProfile(next);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: _isWithinCheckInWindow(next)
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                )
                              : null,
                          color: _isWithinCheckInWindow(next)
                              ? null
                              : GymiesColors.primary,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Bekijk trainer',
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _isWithinCheckInWindow(next)
                                ? Colors.white
                                : GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Package progress bar
              if (next.sessionsRemaining != null && next.packageSessionsTotal != null) ...[
                const SizedBox(height: 14),
                // Separator
                Container(height: 0.5, color: Colors.white.withValues(alpha: 0.15)),
                const SizedBox(height: 12),
                // Package progress
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Colors.white60, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${next.packageName ?? "Pakket"}',
                      style: GoogleFonts.sora(fontSize: 12, color: Colors.white60),
                    ),
                    const Spacer(),
                    Text(
                      '${(next.packageSessionsTotal! - next.sessionsRemaining!)}/${next.packageSessionsTotal} sessies',
                      style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: GymiesColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: next.packageSessionsTotal! > 0
                        ? (next.packageSessionsTotal! - next.sessionsRemaining!) / next.packageSessionsTotal!
                        : 0,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(GymiesColors.primary),
                    minHeight: 6,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // MIJN TRAINERS (horizontale lijst op home)
  // ═══════════════════════════════════════════════════════════════

  /// Unieke trainer namen en IDs uit afgelopen bookings
  List<Map<String, String>> _uniqueTrainerInfos() {
    final seen = <String>{};
    final result = <Map<String, String>>[];
    for (final b in _allBookings) {
      final id = b.trainerUserId ?? '';
      final name = b.trainerName.trim();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      result.add({'id': id, 'name': name.isNotEmpty ? name : 'Trainer'});
    }
    return result;
  }

  Widget _buildMyTrainersCard() {
    final trainers = _uniqueTrainerInfos();
    if (trainers.isEmpty) return const SizedBox.shrink();

    return FadeSlideTransition(
      animation: _staggeredAnimations.length > 1
          ? _staggeredAnimations[1]
          : _staggeredAnimations[0],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.people_rounded, size: 18, color: GymiesColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      trainers.length == 1 ? 'Mijn trainer' : 'Mijn trainers',
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: trainers.length,
                  itemBuilder: (_, i) {
                    final info = trainers[i];
                    final name = info['name'] ?? 'Trainer';
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                    return Padding(
                      padding: EdgeInsets.only(right: i < trainers.length - 1 ? 12 : 0),
                      child: GestureDetector(
                        onTap: () {
                          Haptics.selection();
                          // Vind een booking met deze trainer om _openTrainerProfile te gebruiken
                          final match = _allBookings.cast<Booking?>().firstWhere(
                            (b) => b?.trainerUserId == info['id'],
                            orElse: () => null,
                          );
                          final booking = match ?? (_allBookings.isNotEmpty ? _allBookings.first : null);
                          if (booking == null) return;
                          _openTrainerProfile(booking);
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    GymiesColors.darkBlue,
                                    GymiesColors.darkBlue.withValues(alpha: 0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: GymiesColors.primary.withValues(alpha: 0.4),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: GymiesColors.darkBlue.withValues(alpha: 0.15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initial,
                                style: GoogleFonts.sora(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: GymiesColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 64,
                              child: Text(
                                name.split(' ').first,
                                style: GoogleFonts.sora(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: GymiesColors.darkBlue,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // WEEKKALENDER (verbeterd)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildWeekCalendarCard() {
    return FadeSlideTransition(
      animation: _staggeredAnimations[2],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titel met weekrange
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Deze week',
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  Text(
                    _weekRangeLabel(),
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildWeekDays(),
              // Only show legend when multiple statuses are present
              if (_weekDayStatus.values.where((s) => s != _DayStatus.none).map((s) => s.name).toSet().length > 1) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _legendItem(
                      color: const Color(0xFF4CAF50),
                      filled: true,
                      label: 'Voltooid',
                    ),
                    const SizedBox(width: 16),
                    _legendItem(
                      color: GymiesColors.primary,
                      filled: true,
                      label: 'Vandaag',
                    ),
                    const SizedBox(width: 16),
                    _legendItem(
                      color: GymiesColors.primary,
                      filled: false,
                      label: 'Gepland',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _weekRangeLabel() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final mFormat = DateFormat('d MMM');
    return '${mFormat.format(monday)} – ${mFormat.format(sunday)}';
  }

  Widget _legendItem({
    required Color color,
    required bool filled,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: filled
                ? null
                : Border.all(
                    color: color,
                    width: 1.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildWeekDays() {
    final now = DateTime.now();
    final weekDays = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
    final mondayOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final dayDate = mondayOfWeek.add(Duration(days: index));
        final isToday = now.weekday - 1 == index;
        final status = _weekDayStatus[index] ?? _DayStatus.none;

        Color circleColor;
        Color textColor;
        BoxBorder? border;

        if (status == _DayStatus.completed) {
          // Groen = voltooid
          circleColor = const Color(0xFFE8F5E9);
          textColor = const Color(0xFF2E7D32);
          border = Border.all(color: const Color(0xFF4CAF50), width: 1.5);
        } else if (isToday) {
          // Goud = vandaag
          circleColor = GymiesColors.primary;
          textColor = GymiesColors.darkBlue;
          border = null;
        } else if (status == _DayStatus.planned) {
          // Gestippeld = gepland
          circleColor = Colors.grey.shade100;
          textColor = GymiesColors.darkBlue;
          border = Border.all(
            color: GymiesColors.primary,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          );
        } else {
          // Leeg
          circleColor = Colors.grey.shade100;
          textColor = Colors.grey.shade600;
          border = null;
        }

        return Column(
          children: [
            Text(
              weekDays[index],
              style: GoogleFonts.sora(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isToday ? GymiesColors.darkBlue : Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: circleColor,
                border: border,
              ),
              alignment: Alignment.center,
              child: Text(
                '${dayDate.day}',
                style: GoogleFonts.sora(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Dot indicator
            if (status != _DayStatus.none)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status == _DayStatus.completed
                      ? const Color(0xFF4CAF50)
                      : GymiesColors.primary,
                ),
              )
            else
              const SizedBox(width: 5, height: 5),
          ],
        );
      }),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STATS ROW (compact)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStatsRow() {
    final streak = _stats?['streak'] ?? 0;
    final thisWeek = _stats?['this_week'] ?? 0;
    final weekGoal = _stats?['week_goal'] ?? 3;
    final total = _stats?['total'] ?? 0;

    return FadeSlideTransition(
      animation: _staggeredAnimations[1],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            // Streak (featured, navy)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: GymiesColors.darkBlue,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: GymiesColors.darkBlue.withValues(alpha:0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: GymiesColors.primary,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    AnimatedCountText(
                      targetValue: streak,
                      style: GoogleFonts.sora(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: GymiesColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Streak',
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Deze week (met doel)
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final current = _stats?['week_goal'] ?? 3;
                  final result = await showDialog<int>(
                    context: context,
                    builder: (ctx) => _WeekGoalDialog(currentGoal: current),
                  );
                  if (result != null && result != current && mounted) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('gymies_week_goal', result);
                    setState(() {
                      _stats?['week_goal'] = result;
                    });
                    // Sync naar server
                    try {
                      await context.read<GymiesApi>().updateIntake({
                        'training_frequency_preferred': result,
                      });
                    } catch (_) {}
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Icon(
                        Icons.trending_up_rounded,
                        color: GymiesColors.darkBlue,
                        size: 22,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$thisWeek/$weekGoal',
                        style: GoogleFonts.sora(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Deze week',
                        style: GoogleFonts.sora(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Totaal
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      color: GymiesColors.darkBlue,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    AnimatedCountText(
                      targetValue: total,
                      style: GoogleFonts.sora(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Totaal',
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SLIMME TIP
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSmartTip() {
    return FadeSlideTransition(
      animation: _staggeredAnimations[4],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(
                color: GymiesColors.primary,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: const Color(0xFF92400E),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TIP',
                      style: GoogleFonts.sora(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF92400E),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _smartTip(),
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        color: const Color(0xFF78350F),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CHECK-IN WINDOW HELPER
  // ═══════════════════════════════════════════════════════════════

  /// Check-in is alleen beschikbaar 15 minuten voor de sessie
  bool _isWithinCheckInWindow(Booking booking) {
    final now = DateTime.now();
    final sessionStart = booking.scheduledAt;
    final windowStart = sessionStart.subtract(const Duration(minutes: 15));
    return now.isAfter(windowStart) && now.isBefore(sessionStart.add(Duration(minutes: booking.durationMinutes)));
  }

  // ═══════════════════════════════════════════════════════════════
  // QUICK ACTIONS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildQuickActions() {
    return FadeSlideTransition(
      animation: _staggeredAnimations[3],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Snel naar',
              style: GoogleFonts.sora(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 10),
            // Row 1: Zoek trainer, Favorieten, Facturen
            Row(
              children: [
                _quickActionTile(
                  icon: Icons.search_rounded,
                  label: 'Zoek trainer',
                  onTap: () {
                    Haptics.selection();
                    context.clientShell?.jumpToTab(1);
                  },
                ),
                const SizedBox(width: 10),
                _quickActionTile(
                  icon: Icons.favorite_outline_rounded,
                  label: 'Favorieten',
                  onTap: () {
                    Haptics.selection();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ClientFavoritesStandaloneScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _quickActionTile(
                  icon: Icons.receipt_long_rounded,
                  label: 'Facturen',
                  onTap: () {
                    Haptics.selection();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ClientInvoicesScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Row 2: Support, Groepslessen, Mijn dossier
            Row(
              children: [
                _quickActionTile(
                  icon: Icons.support_agent_rounded,
                  label: 'Support',
                  onTap: () {
                    Haptics.selection();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ClientSupportScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _quickActionTile(
                  icon: Icons.groups_rounded,
                  label: 'Groepslessen',
                  onTap: () {
                    Haptics.selection();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ClientGroupSessionsScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _quickActionTile(
                  icon: Icons.folder_shared_outlined,
                  label: 'Dossier',
                  onTap: () {
                    Haptics.selection();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ClientDossierScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: GymiesColors.darkBlue,
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// WEEK GOAL DIALOG
// ═══════════════════════════════════════════════════════════════════

class _WeekGoalDialog extends StatefulWidget {
  const _WeekGoalDialog({required this.currentGoal});
  final int currentGoal;
  @override
  State<_WeekGoalDialog> createState() => _WeekGoalDialogState();
}

class _WeekGoalDialogState extends State<_WeekGoalDialog> {
  late int _selected;
  @override
  void initState() {
    super.initState();
    _selected = widget.currentGoal;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Weekdoel instellen', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue)),
            const SizedBox(height: 4),
            Text('Hoeveel sessies per week?', style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: List.generate(7, (i) {
                final val = i + 1;
                final selected = val == _selected;
                return GestureDetector(
                  onTap: () => setState(() => _selected = val),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? GymiesColors.primary : Colors.grey.shade100,
                      border: selected ? null : Border.all(color: Colors.grey.shade300),
                    ),
                    alignment: Alignment.center,
                    child: Text('$val', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: selected ? GymiesColors.darkBlue : Colors.grey.shade600)),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selected),
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Opslaan', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// HELPER ENUMS & WIDGETS
// ═══════════════════════════════════════════════════════════════════

enum _DayStatus { none, planned, completed }

/// Shimmer skeleton box voor loading state.
class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox({required this.height, this.borderRadius = 12});
  final double height;
  final double borderRadius;

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) {
        final t = _shimmer.value;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * t, 0),
              end: Alignment(-0.5 + 2.0 * t, 0),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade100,
                Colors.grey.shade200,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Notificatie bel met live unread badge
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nrs = context.watch<NotificationRealtimeService>();
    final unread = nrs.unreadCount;

    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              color: GymiesColors.primary,
              size: 24,
            ),
            if (unread > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fade + slide animatie wrapper
class FadeSlideTransition extends StatelessWidget {
  const FadeSlideTransition({
    Key? key,
    required this.animation,
    required this.child,
  }) : super(key: key);

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

/// Animated count-up tekst
class AnimatedCountText extends StatefulWidget {
  const AnimatedCountText({
    Key? key,
    required this.targetValue,
    required this.style,
  }) : super(key: key);

  final int targetValue;
  final TextStyle style;

  @override
  State<AnimatedCountText> createState() => _AnimatedCountTextState();
}

class _AnimatedCountTextState extends State<AnimatedCountText> {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: widget.targetValue),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Text(
          value.toString(),
          style: widget.style,
        );
      },
    );
  }
}
