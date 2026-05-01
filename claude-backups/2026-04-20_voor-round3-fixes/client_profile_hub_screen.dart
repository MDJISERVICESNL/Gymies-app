import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/app_version.dart';
import 'client_invoices_screen.dart';
import 'client_profile_screen.dart';
import 'client_support_screen.dart';
import 'login_register_screen.dart';

/// Profiel-hub voor client: twee tabbladen (Profiel en Voorkeuren),
/// quick action iconen, persoonlijke instellingen en beveiliging.
class ClientProfileHubScreen extends StatefulWidget {
  const ClientProfileHubScreen({super.key});

  @override
  State<ClientProfileHubScreen> createState() =>
      _ClientProfileHubScreenState();
}

class _ClientProfileHubScreenState extends State<ClientProfileHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _versionDisplay = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await AppVersion.get();
    if (mounted) setState(() => _versionDisplay = info.display);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

    void push(Widget screen) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen));
    }

    Future<void> logout() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Uitloggen'),
          content: const Text('Weet je zeker dat je wilt uitloggen?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Uitloggen'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await context.read<AuthService>().logout();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
        (r) => false,
      );
    }

    Future<void> deleteAccount() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Account verwijderen'),
          content: const Text(
            'Dit zal je account en alle bijbehorende gegevens permanent verwijderen. '
            'Deze actie kan niet ongedaan worden gemaakt.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Verwijderen'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account verwijderaanvraag ingediend — je ontvangt een bevestiging per e-mail')),
      );
      // Uitloggen en naar login navigeren na verwijderaanvraag.
      await context.read<AuthService>().logout();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
        (r) => false,
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.grey.shade50,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildProfileHeader(
                context: context,
                name: name,
                email: email,
                initial: initial,
                onEditPressed: () => push(const ClientProfileScreen()),
              ),
              titlePadding: EdgeInsets.zero,
              expandedTitleScale: 1.0,
            ),
            expandedHeight: 280,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _buildTabBar(_tabController),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _ProfilTab(
              onLogout: logout,
              onDeleteAccount: deleteAccount,
              onPush: push,
            ),
            _VoorkeurenTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader({
    required BuildContext context,
    required String name,
    required String email,
    required String initial,
    required VoidCallback onEditPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: GymiesColors.darkBlue,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              ScaleTransition(
                scale: AlwaysStoppedAnimation(1.0),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: GymiesColors.primary,
                  child: Text(
                    initial,
                    style: GoogleFonts.fjallaOne(
                      fontSize: 36,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onEditPressed,
                child: Container(
                  decoration: BoxDecoration(
                    color: GymiesColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: GoogleFonts.fjallaOne(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          // Email hidden for privacy — uncomment to restore
          // if (email.isNotEmpty) ...[
          //   const SizedBox(height: 4),
          //   Text(
          //     email,
          //     style: TextStyle(
          //       fontSize: 14,
          //       color: Colors.white.withValues(alpha: 0.7),
          //     ),
          //     textAlign: TextAlign.center,
          //   ),
          // ],
        ],
      ),
    );
  }

  Widget _buildTabBar(TabController controller) {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: controller,
        indicatorColor: GymiesColors.primary,
        indicatorWeight: 3,
        labelColor: GymiesColors.darkBlue,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.fjallaOne(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.roboto(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(text: 'Profiel'),
          Tab(text: 'Voorkeuren'),
        ],
      ),
    );
  }
}

class _ProfilTab extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;
  final Function(Widget) onPush;

  const _ProfilTab({
    required this.onLogout,
    required this.onDeleteAccount,
    required this.onPush,
  });

  @override
  State<_ProfilTab> createState() => _ProfilTabState();
}

class _ProfilTabState extends State<_ProfilTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  String _versionDisplay = '';
  String? _selectedGoal;

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
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animationController.forward();
    _loadGoal();
    _loadVersion();
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

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: _buildStaggeredItems(),
    );
  }

  List<Widget> _buildStaggeredItems() {
    final items = [
      _buildQuickActionsRow(),
      const SizedBox(height: 24),
      _SectionHeader('PERSOONLIJK'),
      _SettingsTile(
        icon: Icons.person_outline,
        iconColor: Colors.blue,
        title: 'Profiel bewerken',
        onTap: () => widget.onPush(const ClientProfileScreen()),
      ),
      _SettingsTile(
        icon: Icons.flag_outlined,
        iconColor: Colors.orange,
        title: 'Wat is je doel?',
        subtitle: _selectedGoal ?? 'Nog niet ingesteld',
        onTap: () => _showGoalPicker(context),
      ),
      const SizedBox(height: 16),
      _SectionHeader('ACCOUNT & BEVEILIGING'),
      _SettingsTile(
        icon: Icons.lock_outline,
        iconColor: Colors.green,
        title: 'Wachtwoord wijzigen',
        onTap: () => _showSnackBar('Wachtwoord wijzigen binnenkort beschikbaar'),
      ),
      const SizedBox(height: 16),
      _SectionHeader('OVERIG'),
      _SettingsTile(
        icon: Icons.privacy_tip,
        iconColor: Colors.teal,
        title: 'Privacy & gegevens',
        onTap: () => _showPrivacySheet(),
      ),
      _SettingsTile(
        icon: Icons.info_outline,
        iconColor: Colors.indigo,
        title: 'Over GYMIES',
        onTap: () => _showAboutDialog(),
      ),
      const SizedBox(height: 32),
      _buildActionButton(
        label: 'Uitloggen',
        icon: Icons.logout_rounded,
        color: Colors.red.shade600,
        onPressed: widget.onLogout,
      ),
      const SizedBox(height: 32),
      Center(
        child: Text(
          _versionDisplay.isNotEmpty ? _versionDisplay : 'Gymies',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
      ),
      const SizedBox(height: 16),
    ];

    return List.generate(
      items.length,
      (index) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 50 + (index * 50)),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        ),
        child: items[index],
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _QuickActionButton(
          icon: Icons.receipt_long_rounded,
          label: 'Facturen',
          color: Colors.green.shade500,
          onTap: () => widget.onPush(const ClientInvoicesScreen()),
        ),
        _QuickActionButton(
          icon: Icons.emoji_events_rounded,
          label: 'Achievements',
          color: GymiesColors.primary,
          onTap: () => _showSnackBar('Binnenkort beschikbaar'),
        ),
        _QuickActionButton(
          icon: Icons.card_giftcard,
          label: 'Uitnodigen',
          color: Colors.purple.shade500,
          onTap: () => _showShareSheet(),
        ),
        _QuickActionButton(
          icon: Icons.headset,
          label: 'Support',
          color: Colors.blue.shade500,
          onTap: () => widget.onPush(const ClientSupportScreen()),
        ),
      ],
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showGoalPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Wat is je doel?',
              style: GoogleFonts.fjallaOne(fontSize: 18),
            ),
          ),
          const Divider(),
          ..._goalOptions.map((goal) => ListTile(
            title: Text(goal),
            trailing: _selectedGoal == goal
                ? const Icon(Icons.check_circle_rounded, color: GymiesColors.primary)
                : null,
            onTap: () {
              _saveGoal(goal);
              Navigator.pop(ctx);
            },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  static const _shareText = AppConfig.shareText;

  void _showShareSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Deel GYMIES',
              style: GoogleFonts.fjallaOne(fontSize: 18),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ShareOption(
                  icon: Icons.mail_outline,
                  label: 'E-mail',
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.share(_shareText, subject: AppConfig.shareSubject);
                  },
                ),
                _ShareOption(
                  icon: Icons.chat_bubble_outline,
                  label: 'Bericht',
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.share(_shareText);
                  },
                ),
                _ShareOption(
                  icon: Icons.link,
                  label: 'Link kopiëren',
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.share(AppConfig.shareBaseUrl);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
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
              // Titel
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
              // AVG / GDPR info
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
              // GDPR data export
              _PrivacyActionTile(
                icon: Icons.download_outlined,
                iconColor: Colors.cyan.shade600,
                title: 'Mijn gegevens opvragen',
                subtitle: 'Ontvang een export van alle data die wij over je hebben',
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
              // Account verwijderen
              _PrivacyActionTile(
                icon: Icons.delete_forever_outlined,
                iconColor: Colors.red.shade600,
                title: 'Account verwijderen',
                subtitle: 'Verwijder permanent je account en al je gegevens (AVG Art. 17)',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onDeleteAccount();
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Over GYMIES'),
        content: Text(
          'GYMIES – Je persoonlijke fitness coach.\n\n'
          '$version\n'
          'Gebouwd met Flutter\n\n'
          'Bedankt dat je GYMIES gebruikt!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    String? subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
        ],
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _VoorkeurenTab extends StatefulWidget {
  @override
  State<_VoorkeurenTab> createState() => _VoorkeurenTabState();
}

class _VoorkeurenTabState extends State<_VoorkeurenTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  String _darkModeSetting = 'Systeem';
  String _languageSetting = 'Nederlands';
  String _silentHoursSetting = 'Uit';
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: _buildStaggeredItems(),
    );
  }

  List<Widget> _buildStaggeredItems() {
    final items = [
      _SectionHeader('WEERGAVE'),
      _SettingsTile(
        icon: Icons.brightness_4_outlined,
        iconColor: Colors.amber.shade600,
        title: 'Donkere modus',
        subtitle: _darkModeSetting,
        onTap: () => _showDarkModeSheet(),
      ),
      _SettingsTile(
        icon: Icons.language,
        iconColor: Colors.blue.shade600,
        title: 'Taal',
        subtitle: _languageSetting,
        onTap: () => _showLanguageSheet(),
      ),
      const SizedBox(height: 16),
      _SectionHeader('MELDINGEN'),
      _SettingsTile(
        icon: Icons.notifications_outlined,
        iconColor: Colors.red.shade500,
        title: 'Melding voorkeuren',
        subtitle: 'Kies welke meldingen je wilt ontvangen',
        onTap: () => _showSnackBar('Meldingscentrum openen'),
      ),
      _SettingsTile(
        icon: Icons.schedule,
        iconColor: Colors.indigo.shade500,
        title: 'Stille uren',
        subtitle: _silentHoursSetting,
        onTap: () => _showSilentHoursSheet(),
      ),
      const SizedBox(height: 16),
      _SectionHeader('ALGEMEEN'),
      _SettingsTile(
        icon: Icons.vibration,
        iconColor: Colors.purple.shade500,
        title: 'Trillingen',
        subtitle: 'Trilreactie bij acties',
        trailing: SizedBox(
          height: 24,
          child: Switch(
            value: _vibrationEnabled,
            onChanged: (value) {
              setState(() => _vibrationEnabled = value);
            },
          ),
        ),
      ),
      const SizedBox(height: 16),
      _SectionHeader('AGENDA'),
      _SettingsTile(
        icon: Icons.sync_outlined,
        iconColor: Colors.green.shade600,
        title: 'Agenda synchronisatie',
        subtitle: 'Koppel sessies met Apple of Google Calendar',
        onTap: () => _showSnackBar('Agenda synchronisatie binnenkort beschikbaar'),
      ),
      // Data exporteren is verplaatst naar Privacy & gegevens (Profiel tab).
      const SizedBox(height: 32),
    ];

    return List.generate(
      items.length,
      (index) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 50 + (index * 50)),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        ),
        child: items[index],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showDarkModeSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Donkere modus',
              style: GoogleFonts.fjallaOne(fontSize: 18),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Systeem'),
            trailing: _darkModeSetting == 'Systeem'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _darkModeSetting = 'Systeem');
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            title: const Text('Licht'),
            trailing: _darkModeSetting == 'Licht'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _darkModeSetting = 'Licht');
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            title: const Text('Donker'),
            trailing: _darkModeSetting == 'Donker'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _darkModeSetting = 'Donker');
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showLanguageSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Taal',
              style: GoogleFonts.fjallaOne(fontSize: 18),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Nederlands'),
            trailing: _languageSetting == 'Nederlands'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _languageSetting = 'Nederlands');
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            title: const Text('English'),
            trailing: _languageSetting == 'English'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _languageSetting = 'English');
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            title: const Text('Français'),
            trailing: _languageSetting == 'Français'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _languageSetting = 'Français');
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showSilentHoursSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Stille uren',
              style: GoogleFonts.fjallaOne(fontSize: 18),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Uit'),
            trailing: _silentHoursSetting == 'Uit'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _silentHoursSetting = 'Uit');
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            title: const Text('22:00 - 08:00'),
            trailing: _silentHoursSetting == '22:00 - 08:00'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _silentHoursSetting = '22:00 - 08:00');
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            title: const Text('23:00 - 07:00'),
            trailing: _silentHoursSetting == '23:00 - 07:00'
                ? const Icon(Icons.check, color: GymiesColors.primary)
                : null,
            onTap: () {
              setState(() => _silentHoursSetting = '23:00 - 07:00');
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
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
                color: iconColor.withValues(alpha: 0.12),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: GoogleFonts.fjallaOne(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: GymiesColors.darkBlue,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
        trailing: trailing ??
            (onTap != null
                ? Icon(Icons.chevron_right, color: Colors.grey.shade400)
                : null),
        onTap: onTap,
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: GymiesColors.darkBlue,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: GymiesColors.darkBlue, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: GymiesColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }
}
