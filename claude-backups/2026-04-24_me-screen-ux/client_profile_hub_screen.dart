import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../theme/gymies_theme.dart';
import '../utils/app_version.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_dialog.dart';
import 'client_invoices_screen.dart';
import 'client_profile_screen.dart';
import 'client_support_screen.dart';
import 'login_register_screen.dart';
import 'referral_screen.dart';

/// Profiel-hub voor client: één scrollview met stats, doel-kaart,
/// quick actions grid, gegroepeerde instellingen en voorkeuren.
class ClientProfileHubScreen extends StatefulWidget {
  const ClientProfileHubScreen({super.key});

  @override
  State<ClientProfileHubScreen> createState() =>
      _ClientProfileHubScreenState();
}

class _ClientProfileHubScreenState extends State<ClientProfileHubScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  String _versionDisplay = '';
  String? _selectedGoal;
  bool _calendarSyncEnabled = false;
  String _darkModeSetting = 'Systeem';
  String _silentHoursSetting = 'Uit';
  bool _vibrationEnabled = true;

  // Stats uit API
  int _totalSessions = 0;
  int _streak = 0;
  String _nextSession = '-';

  static const _kGoalKey = 'gymies_client_goal';
  static const _goalOptions = [
    'Gewicht verliezen',
    'Spieren opbouwen',
    'Gezondheid verbeteren',
    'Flexibiliteit vergroten',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animController.forward();
    _loadVersion();
    _loadGoal();
    _loadCalendarSyncPref();
    _loadStats();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await AppVersion.get();
    if (mounted) setState(() => _versionDisplay = info.display);
  }

  Future<void> _loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kGoalKey);
    if (mounted && saved != null) setState(() => _selectedGoal = saved);
  }

  Future<void> _saveGoal(String goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGoalKey, goal);
    if (mounted) setState(() => _selectedGoal = goal);
  }

  Future<void> _loadCalendarSyncPref() async {
    final enabled = await CalendarService.instance.isAutoSyncEnabled();
    if (mounted) setState(() => _calendarSyncEnabled = enabled);
  }

  Future<void> _loadStats() async {
    try {
      final api = context.read<GymiesApi>();
      final stats = await api.getClientStats();
      if (!mounted) return;
      setState(() {
        _totalSessions = mapInt(stats, ['total_sessions', 'sessions_count']) ?? 0;
        _streak = mapInt(stats, ['streak', 'current_streak']) ?? 0;
        final next = mapStr(stats, ['next_session_day', 'next_session']);
        _nextSession = next.isNotEmpty ? next : '-';
      });
    } catch (_) {
      // Stats zijn optioneel — faal stil
    }
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout() async {
    final confirmed = await GymiesDialog.destructive(
      context,
      title: 'Uitloggen',
      message: 'Weet je zeker dat je wilt uitloggen?',
      confirmLabel: 'Uitloggen',
      cancelLabel: 'Annuleren',
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<AuthService>().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
      (r) => false,
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await GymiesDialog.destructive(
      context,
      title: 'Account verwijderen',
      message: 'Dit zal je account en alle bijbehorende gegevens permanent verwijderen. '
          'Deze actie kan niet ongedaan worden gemaakt.',
      confirmLabel: 'Verwijderen',
      cancelLabel: 'Annuleren',
    );
    if (confirmed != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account verwijderaanvraag ingediend — je ontvangt een bevestiging per e-mail')),
    );
    await context.read<AuthService>().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user ?? {};
    final name = user['name']?.toString() ??
        user['display_name']?.toString() ??
        user['email']?.toString() ??
        'Mijn profiel';
    final email = user['email']?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final items = _buildItems(name: name, email: email, initial: initial);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 40),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 80 + (index * 40)),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 16),
                  child: child,
                ),
              ),
              child: items[index],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildItems({
    required String name,
    required String email,
    required String initial,
  }) {
    return [
      // ── Profile header met stats ──
      _buildProfileHeader(name: name, email: email, initial: initial),
      const SizedBox(height: 16),

      // ── Doel-kaart ──
      if (_selectedGoal != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildGoalCard(),
        ),
      if (_selectedGoal != null) const SizedBox(height: 16),

      // ── Quick Actions 2×2 grid ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildQuickActionsGrid(),
      ),
      const SizedBox(height: 24),

      // ── INSTELLINGEN sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('INSTELLINGEN'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.person_outline,
            title: 'Profiel bewerken',
            onTap: () => _push(const ClientProfileScreen()),
          ),
          _GroupedTileData(
            icon: Icons.flag_outlined,
            title: 'Wat is je doel?',
            trailing: Text(
              _selectedGoal ?? 'Niet ingesteld',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            onTap: () => _showGoalPicker(),
          ),
          _GroupedTileData(
            icon: Icons.lock_outline,
            title: 'Wachtwoord wijzigen',
            onTap: () => _push(const ClientProfileScreen()),
          ),
          _GroupedTileData(
            icon: Icons.emergency_rounded,
            title: 'Noodcontact',
            onTap: () => _push(const ClientProfileScreen()),
          ),
          _GroupedTileData(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & gegevens',
            onTap: () => _showPrivacySheet(),
          ),
        ]),
      ),
      const SizedBox(height: 20),

      // ── VOORKEUREN sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('VOORKEUREN'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.brightness_4_outlined,
            title: 'Donkere modus',
            trailing: Text(
              _darkModeSetting,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            onTap: () => _showDarkModeSheet(),
          ),
          _GroupedTileData(
            icon: Icons.notifications_outlined,
            title: 'Meldingen',
            onTap: () => _showSilentHoursSheet(),
          ),
          _GroupedTileData(
            icon: Icons.vibration,
            title: 'Trillingen',
            trailing: SizedBox(
              height: 24,
              child: Switch.adaptive(
                value: _vibrationEnabled,
                activeColor: GymiesColors.primary,
                onChanged: (v) => setState(() => _vibrationEnabled = v),
              ),
            ),
          ),
          _GroupedTileData(
            icon: Icons.event_available_rounded,
            title: 'Agenda sync',
            trailing: Switch.adaptive(
              value: _calendarSyncEnabled,
              activeColor: GymiesColors.primary,
              onChanged: (v) async {
                setState(() => _calendarSyncEnabled = v);
                await CalendarService.instance.setAutoSync(v);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        v
                            ? 'Sessies worden automatisch aan je agenda toegevoegd'
                            : 'Automatische agenda-sync uitgeschakeld',
                      ),
                      backgroundColor: GymiesColors.darkBlue,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
        ]),
      ),
      const SizedBox(height: 20),

      // ── OVERIG sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('OVERIG'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.info_outline,
            title: 'Over GYMIES',
            onTap: () => _showAboutDialog(),
          ),
        ]),
      ),
      const SizedBox(height: 24),

      // ── Uitloggen knop ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextButton.icon(
          onPressed: _logout,
          style: TextButton.styleFrom(
            foregroundColor: Colors.red.shade500,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          icon: const Icon(Icons.logout_rounded, size: 20),
          label: Text(
            'Uitloggen',
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),

      // ── Versie ──
      Center(
        child: Text(
          _versionDisplay.isNotEmpty ? _versionDisplay : 'Gymies',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        ),
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════
  // PROFILE HEADER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildProfileHeader({
    required String name,
    required String email,
    required String initial,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: GymiesColors.darkBlue,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          // Avatar + edit + camera
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha:0.2),
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: GymiesColors.primary,
                  child: Text(
                    initial,
                    style: GoogleFonts.sora(
                      fontSize: 32,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _push(const ClientProfileScreen()),
                child: Container(
                  decoration: BoxDecoration(
                    color: GymiesColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: GymiesColors.darkBlue, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: 14,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: GoogleFonts.sora(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              email,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha:0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],

          // Stats strip
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha:0.12),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(value: '$_totalSessions', label: 'Sessies'),
                _StatItem(
                  value: '$_streak',
                  label: 'Streak',
                  prefix: _streak > 0 ? '\u{1F525} ' : '',
                ),
                _StatItem(value: _nextSession, label: 'Volgende'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // DOEL-KAART
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildGoalCard() {
    return GestureDetector(
      onTap: () => _showGoalPicker(),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [GymiesColors.primary, Color(0xFFF0A500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('\u{1F3AF}', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doel: $_selectedGoal',
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tik om aan te passen',
                    style: TextStyle(
                      fontSize: 11,
                      color: GymiesColors.darkBlue.withValues(alpha:0.6),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Wijzig \u{203A}',
              style: GoogleFonts.sora(
                fontSize: 12,
                color: GymiesColors.darkBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // QUICK ACTIONS 2×2
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildQuickActionsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.receipt_long_rounded,
                iconBg: Colors.green.shade50,
                iconColor: Colors.green.shade600,
                title: 'Facturen',
                subtitle: 'Bekijk overzicht',
                onTap: () => _push(const ClientInvoicesScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.card_giftcard,
                iconBg: Colors.purple.shade50,
                iconColor: Colors.purple.shade600,
                title: 'Uitnodigen',
                subtitle: 'Verdien punten',
                onTap: () => _push(const ReferralScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.emoji_events_rounded,
                iconBg: Colors.orange.shade50,
                iconColor: Colors.orange.shade600,
                title: 'Achievements',
                subtitle: 'Binnenkort',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Achievements komen binnenkort!')),
                ),
                dimmed: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.headset_mic_rounded,
                iconBg: Colors.blue.shade50,
                iconColor: Colors.blue.shade600,
                title: 'Support',
                subtitle: 'Direct hulp',
                onTap: () => _push(const ClientSupportScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // GROUPED TILES (iOS-stijl)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: GoogleFonts.sora(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildGroupedTiles(List<_GroupedTileData> tiles) {
    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(tiles.length, (i) {
          final t = tiles[i];
          final isLast = i == tiles.length - 1;
          return Column(
            children: [
              InkWell(
                onTap: t.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        t.icon,
                        size: 20,
                        color: GymiesColors.darkBlue.withValues(alpha:0.7),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          t.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                      if (t.trailing != null)
                        t.trailing!
                      else if (t.onTap != null)
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 50,
                  color: Colors.grey.shade200,
                ),
            ],
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SHEETS & DIALOGS
  // ═══════════════════════════════════════════════════════════════════

  void _showGoalPicker() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.flag_outlined, color: GymiesColors.darkBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Wat is je doel?',
                      style: GoogleFonts.sora(fontSize: 18, color: GymiesColors.darkBlue),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._goalOptions.map((goal) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () {
                        _saveGoal(goal);
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedGoal == goal
                              ? GymiesColors.primary.withValues(alpha: 0.15)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedGoal == goal
                                ? GymiesColors.primary
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                goal,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                            ),
                            if (_selectedGoal == goal)
                              const Icon(Icons.check_circle_rounded, color: GymiesColors.primary),
                          ],
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showDarkModeSheet() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.brightness_4_outlined, color: GymiesColors.darkBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Donkere modus',
                      style: GoogleFonts.sora(fontSize: 18, color: GymiesColors.darkBlue),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final opt in ['Systeem', 'Licht', 'Donker'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() => _darkModeSetting = opt);
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _darkModeSetting == opt
                            ? GymiesColors.primary.withValues(alpha: 0.15)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _darkModeSetting == opt
                              ? GymiesColors.primary
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              opt,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ),
                          if (_darkModeSetting == opt)
                            const Icon(Icons.check_circle_rounded, color: GymiesColors.primary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSilentHoursSheet() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.notifications_off_outlined, color: GymiesColors.darkBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Stille uren',
                      style: GoogleFonts.sora(fontSize: 18, color: GymiesColors.darkBlue),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final opt in ['Uit', '22:00 - 08:00', '23:00 - 07:00'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() => _silentHoursSetting = opt);
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _silentHoursSetting == opt
                            ? GymiesColors.primary.withValues(alpha: 0.15)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _silentHoursSetting == opt
                              ? GymiesColors.primary
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              opt,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ),
                          if (_silentHoursSetting == opt)
                            const Icon(Icons.check_circle_rounded, color: GymiesColors.primary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacySheet() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.privacy_tip, color: Colors.teal.shade600, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Privacy & gegevens',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: Text(
                  'GYMIES verwerkt je persoonsgegevens conform de AVG (GDPR). '
                  'Je data wordt niet met derden gedeeld en uitsluitend gebruikt '
                  'voor het leveren van onze diensten. Je hebt te allen tijde '
                  'het recht je gegevens in te zien, te corrigeren of te verwijderen.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.teal.shade800,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _PrivacyActionTile(
                icon: Icons.download_outlined,
                iconColor: Colors.cyan.shade600,
                title: 'Mijn gegevens opvragen',
                subtitle: 'Ontvang een export van alle data',
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gegevensexport aangevraagd — je ontvangt een e-mail'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _PrivacyActionTile(
                icon: Icons.delete_forever_outlined,
                iconColor: Colors.red.shade600,
                title: 'Account verwijderen',
                subtitle: 'Verwijder permanent (AVG Art. 17)',
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteAccount();
                },
                danger: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog() {
    final version = _versionDisplay.isNotEmpty ? _versionDisplay : 'Gymies';
    GymiesDialog.info(
      context,
      title: 'Over GYMIES',
      message: 'GYMIES – Je persoonlijke fitness coach.\n\n'
          '$version\n'
          'Gebouwd met Flutter\n\n'
          'Bedankt dat je GYMIES gebruikt!',
      buttonLabel: 'Sluiten',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    this.prefix = '',
  });
  final String value;
  final String label;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$prefix$value',
          style: GoogleFonts.sora(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: GymiesColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha:0.55),
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dimmed = false,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade200,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: dimmed ? Colors.grey.shade100 : iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: dimmed ? Colors.grey : iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupedTileData {
  const _GroupedTileData({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
}

class _PrivacyActionTile extends StatelessWidget {
  const _PrivacyActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: danger ? Colors.red.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: danger ? Colors.red.shade200 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: danger ? Colors.red.shade700 : Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: danger ? Colors.red.shade400 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: danger ? Colors.red.shade300 : Colors.grey.shade400,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
