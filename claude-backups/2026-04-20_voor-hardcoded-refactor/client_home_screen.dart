import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import 'widgets/gymies_app_bar.dart';

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
  String? _statsError;

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
    _loadStats();
  }

  void _initializeAnimation() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _staggeredAnimations = List.generate(
      6,
      (index) => CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          index * 0.12,
          (index * 0.12) + 0.5,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _animationController.forward();
  }

  Future<void> _loadStats() async {
    try {
      final api = context.read<GymiesApi>();
      // getClientStats() does not exist, so we build stats from getBookings()
      final bookings = await api.getBookings();
      final now = DateTime.now();
      final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));

      final completedBookings = bookings.where((b) =>
        b.status == 'completed' || b.status == 'confirmed').toList();
      final thisWeekBookings = completedBookings.where((b) {
        final date = b.scheduledAt;
        return date.isAfter(thisWeekStart);
      }).toList();

      if (mounted) {
        setState(() {
          _stats = {
            'streak': 0, // simplified
            'this_week': thisWeekBookings.length,
            'total': completedBookings.length,
            'achievements_unlocked': 7,
            'total_achievements': 10,
          };
          _loadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stats = {
            'streak': 0,
            'this_week': 0,
            'total': 0,
            'achievements_unlocked': 0,
            'total_achievements': 10,
          };
          _loadingStats = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final userName = user?['name'] as String? ?? 'Trainer';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(userName),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildWeekCalendarCard(),
                  _buildStatsRow(),
                  _buildAchievementCard(),
                  _buildQuickActionsSection(),
                  _buildMotivationalCTA(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(String userName) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: GymiesColors.darkBlue,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: GymiesColors.darkBlue,
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'GYMIES',
                  style: GoogleFonts.fjallaOne(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: GymiesColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Goedemorgen, $userName',
                      style: GoogleFonts.roboto(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aan de slag! 💪',
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.white70,
                      ),
                    ),
                  ],
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
            child: IconButton(
              icon: const Icon(Icons.notifications_none, size: 24),
              onPressed: () {},
              color: GymiesColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekCalendarCard() {
    return FadeSlideTransition(
      animation: _staggeredAnimations[0],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Jouw week',
                style: GoogleFonts.fjallaOne(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 16),
              _buildWeekDays(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekDays() {
    final now = DateTime.now();
    final weekDays = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
    final daysWithSessions = {0, 2, 4, 5};

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final isToday = now.weekday % 7 == index;
        final hasSession = daysWithSessions.contains(index);

        return Column(
          children: [
            Text(
              weekDays[index],
              style: GoogleFonts.roboto(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday ? GymiesColors.primary : Colors.grey.shade100,
                border: isToday
                    ? null
                    : Border.all(color: Colors.grey.shade200, width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isToday ? GymiesColors.darkBlue : Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (hasSession)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GymiesColors.primary,
                ),
              )
            else
              const SizedBox(width: 6, height: 6),
          ],
        );
      }),
    );
  }

  Widget _buildStatsRow() {
    final streakCount = _stats?['streak'] ?? 12;
    final thisWeek = _stats?['this_week'] ?? 4;
    final totalSessions = _stats?['total'] ?? 48;

    return FadeSlideTransition(
      animation: _staggeredAnimations[1],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.local_fire_department,
                label: 'weken',
                value: streakCount,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.trending_up,
                label: 'Deze week',
                value: thisWeek,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.emoji_events,
                label: 'Totaal',
                value: totalSessions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required int value,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GymiesColors.darkBlue,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: GymiesColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedCountText(
            targetValue: value,
            style: GoogleFonts.fjallaOne(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.roboto(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GymiesColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementCard() {
    final achievementsUnlocked = _stats?['achievements_unlocked'] ?? 7;
    final totalAchievements = _stats?['total_achievements'] ?? 10;
    final progress = achievementsUnlocked / totalAchievements;

    return FadeSlideTransition(
      animation: _staggeredAnimations[2],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$achievementsUnlocked/$totalAchievements achievements ontgrendeld',
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: GymiesColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return LinearProgressIndicator(
                      minHeight: 8,
                      value: value,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        GymiesColors.primary,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Volgende: 100 km afgelegd',
                style: GoogleFonts.roboto(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return FadeSlideTransition(
      animation: _staggeredAnimations[3],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Snelle acties',
              style: GoogleFonts.fjallaOne(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildActionChip(
                    label: 'Boek sessie',
                    icon: Icons.add_circle_outline,
                    onTap: () {
                      Navigator.pushNamed(context, '/ontdekken');
                    },
                  ),
                  const SizedBox(width: 12),
                  _buildActionChip(
                    label: 'Mijn trainer',
                    icon: Icons.person_outline,
                    onTap: () {
                      Navigator.pushNamed(context, '/favorites');
                    },
                  ),
                  const SizedBox(width: 12),
                  _buildActionChip(
                    label: 'Train Samen',
                    icon: Icons.group,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: GymiesColors.primary,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: GymiesColors.primary.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: GymiesColors.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.roboto(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: GymiesColors.darkBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMotivationalCTA() {
    final motivationalMessages = [
      'Jij bent sterker dan je denkt! 💪',
      'Elke sessie brengt je dichter bij je doel 🎯',
      'Discipline > Motivatie 🔥',
      'Je lichaam kan alles aan wat je geest gelooft 🧠',
      'Kleine stappen, grote resultaten 📈',
      'Vandaag jij, morgen jij maar beter 🚀',
    ];

    final messageIndex =
        DateTime.now().day % motivationalMessages.length;
    final message = motivationalMessages[messageIndex];

    return FadeSlideTransition(
      animation: _staggeredAnimations[4],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                GymiesColors.darkBlue,
                GymiesColors.darkBlue.withOpacity(0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: GymiesColors.darkBlue.withOpacity(0.2),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vandaag\'s Motivatie',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.primary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: GoogleFonts.roboto(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GymiesColors.primary,
                ),
                alignment: Alignment.center,
                child: Text(
                  '💪',
                  style: GoogleFonts.roboto(fontSize: 28),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
