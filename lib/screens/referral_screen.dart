import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';

/// Referral / Vrienden uitnodigen scherm.
///
/// Werkt voor zowel clients als trainers. Toont:
/// - Persoonlijke referral link & QR code
/// - Deel-opties (WhatsApp, E-mail, Bericht, Link kopiëren)
/// - Statistieken (uitnodigingen, geaccepteerd, beloningen)
/// - "Hoe werkt het?" stappen
///
/// De backend referral-endpoints bestaan mogelijk nog niet — het scherm
/// degradeert graceful met placeholders als de API 404 teruggeeft.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String _referralCode = '';
  int _invitesSent = 0;
  int _invitesAccepted = 0;
  String _rewardLabel = 'Gratis sessie';
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _load();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<GymiesApi>();
      final data = await api.getMyReferralProgram();
      if (!mounted) return;
      setState(() {
        _referralCode = (data['code'] ??
                data['referral_code'] ??
                data['referralCode'] ??
                '')
            .toString();
        _invitesSent = _parseInt(data['invites_sent'] ??
            data['sent'] ??
            data['total_invites'] ??
            0);
        _invitesAccepted = _parseInt(data['invites_accepted'] ??
            data['accepted'] ??
            data['conversions'] ??
            0);
        _rewardLabel = (data['reward_label'] ??
                data['reward'] ??
                data['incentive'] ??
                'Gratis sessie')
            .toString();
        _loading = false;
      });
    } on ApiException {
      // Backend referral routes bestaan nog niet — graceful fallback.
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
    _animController.forward();
  }

  int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String get _referralLink {
    final user = context.read<AuthService>().user;
    final userId = (user?['id'] ?? user?['user_id'] ?? '').toString().trim();
    // Gebruik referral code als die er is, anders user ID
    final ref = _referralCode.isNotEmpty ? _referralCode : userId;
    if (ref.isNotEmpty) {
      return '${AppConfig.shareBaseUrl}/?ref=$ref';
    }
    return AppConfig.shareBaseUrl;
  }

  String get _shareText {
    return 'Ik train met GYMIES en vind het top! '
        'Meld je aan via mijn persoonlijke link en '
        'we krijgen allebei een beloning 💪\n\n'
        '$_referralLink';
  }

  void _copyLink() {
    Haptics.light();
    Clipboard.setData(ClipboardData(text: _referralLink));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link gekopieerd!'),
        backgroundColor: GymiesColors.darkBlue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareVia(String method) {
    Haptics.selection();
    switch (method) {
      case 'email':
        Share.share(_shareText, subject: 'Probeer GYMIES — mijn tip!');
        break;
      case 'whatsapp':
        Share.share(_shareText);
        break;
      case 'message':
        Share.share(_shareText);
        break;
      default:
        Share.share(_shareText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Vrienden uitnodigen'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
              opacity: _fadeAnim,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeroCard(),
                  const SizedBox(height: 16),
                  _buildShareButtons(),
                  const SizedBox(height: 16),
                  _buildStatsRow(),
                  const SizedBox(height: 16),
                  _buildReferralLinkCard(),
                  const SizedBox(height: 16),
                  _buildQrCard(),
                  const SizedBox(height: 24),
                  _buildHowItWorks(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  /// ── Hero card met value proposition ──
  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [GymiesColors.darkBlue, Color(0xFF1A3A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: GymiesColors.darkBlue.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              color: GymiesColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Deel de kracht van fitness',
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Nodig vrienden uit voor GYMIES en ontvang '
            'allebei een beloning wanneer zij starten!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: GymiesColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded,
                    color: GymiesColors.darkBlue, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Beloning: $_rewardLabel',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ── Deel-knoppen ──
  Widget _buildShareButtons() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            Text(
              'Deel via',
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ShareCircle(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _shareVia('whatsapp'),
                ),
                _ShareCircle(
                  icon: Icons.mail_rounded,
                  label: 'E-mail',
                  color: Colors.blue.shade600,
                  onTap: () => _shareVia('email'),
                ),
                _ShareCircle(
                  icon: Icons.message_rounded,
                  label: 'Bericht',
                  color: Colors.orange.shade600,
                  onTap: () => _shareVia('message'),
                ),
                _ShareCircle(
                  icon: Icons.link_rounded,
                  label: 'Kopiëren',
                  color: Colors.grey.shade700,
                  onTap: _copyLink,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ── Statistieken rij ──
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.send_rounded,
            value: _invitesSent.toString(),
            label: 'Verstuurd',
            color: Colors.blue.shade600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.person_add_rounded,
            value: _invitesAccepted.toString(),
            label: 'Geaccepteerd',
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.emoji_events_rounded,
            value: _invitesAccepted > 0
                ? '$_invitesAccepted×'
                : '—',
            label: 'Beloningen',
            color: GymiesColors.primary,
            valueColor: GymiesColors.darkBlue,
          ),
        ),
      ],
    );
  }

  /// ── Referral link kaart ──
  Widget _buildReferralLinkCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link_rounded,
                    color: GymiesColors.darkBlue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Jouw persoonlijke link',
                  style: GoogleFonts.sora(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _referralLink,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: GymiesColors.darkBlue.withValues(alpha: 0.8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Haptics.light();
                      _copyLink();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.copy_rounded,
                          size: 18, color: GymiesColors.darkBlue),
                    ),
                  ),
                ],
              ),
            ),
            if (_referralCode.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.confirmation_number_outlined,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Referral code: $_referralCode',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ── QR Code kaart ──
  Widget _buildQrCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'Of deel via QR',
              style: GoogleFonts.sora(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Laat vrienden deze QR-code scannen',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: QrImageView(
                data: _referralLink,
                version: QrVersions.auto,
                size: 180,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: GymiesColors.darkBlue,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: GymiesColors.darkBlue,
                ),
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ── Hoe werkt het? ──
  Widget _buildHowItWorks() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hoe werkt het?',
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 16),
            _HowItWorksStep(
              step: '1',
              title: 'Deel je link',
              description:
                  'Stuur je persoonlijke link naar vrienden via WhatsApp, e-mail of deel de QR-code.',
              icon: Icons.share_rounded,
              color: Colors.blue.shade600,
            ),
            const SizedBox(height: 14),
            _HowItWorksStep(
              step: '2',
              title: 'Vriend meldt zich aan',
              description:
                  'Je vriend maakt een account aan via jouw link en boekt een sessie.',
              icon: Icons.person_add_alt_1_rounded,
              color: Colors.green.shade600,
            ),
            const SizedBox(height: 14),
            _HowItWorksStep(
              step: '3',
              title: 'Jullie worden beloond',
              description:
                  'Jullie krijgen allebei een beloning zodra de eerste sessie voltooid is!',
              icon: Icons.celebration_rounded,
              color: Colors.orange.shade600,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ShareCircle extends StatelessWidget {
  const _ShareCircle({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.valueColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.sora(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: valueColor ?? color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({
    required this.step,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String step;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
