import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/biometric_auth_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'client_invoices_screen.dart';
import 'client_profile_screen.dart';
import 'client_support_screen.dart';

/// Instellingen-scherm voor klanten — modern iOS-grouped-tiles design.
class ClientSettingsScreen extends StatefulWidget {
  const ClientSettingsScreen({super.key});

  @override
  State<ClientSettingsScreen> createState() => _ClientSettingsScreenState();
}

class _ClientSettingsScreenState extends State<ClientSettingsScreen> {
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricLabel = 'Biometrie';
  bool _biometricLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final bio = BiometricAuthService.instance;
    final available = await bio.isAvailable;
    final enabled = await bio.isEnabled;
    final label = await bio.biometricLabel;
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _biometricLabel = label;
      _biometricLoading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    Haptics.light();
    final bio = BiometricAuthService.instance;

    if (value) {
      // Inschakelen: verifieer eerst met biometric
      final verified = await bio.authenticate(
        reason: 'Bevestig $_biometricLabel om het in te schakelen',
      );
      if (!verified) return; // Gebruiker geannuleerd of mislukt
      await bio.setEnabled(true);
      await bio.markAsked();
    } else {
      // Uitschakelen: verifieer eerst (voorkomt ongeautoriseerd uitschakelen)
      final verified = await bio.authenticate(
        reason: 'Bevestig $_biometricLabel om het uit te schakelen',
      );
      if (!verified) return;
      await bio.setEnabled(false);
    }

    if (!mounted) return;
    setState(() => _biometricEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          // ── Dark Blue Header ──
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
                      child: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Instellingen',
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

          // ── Tiles ──
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('ACCOUNT'),
                  _GroupedTilesCard(
                    tiles: [
                      _TileData(
                        icon: Icons.person_outline_rounded,
                        iconColor: const Color(0xFF1565C0),
                        iconBg: const Color(0xFFE3F2FD),
                        label: 'Mijn profiel',
                        subtitle: 'Naam, e-mail, noodcontact',
                        onTap: () => _navigate(context, const ClientProfileScreen()),
                      ),
                      _TileData(
                        icon: Icons.receipt_long_rounded,
                        iconColor: const Color(0xFF2E7D32),
                        iconBg: const Color(0xFFE8F5E9),
                        label: 'Facturen',
                        subtitle: 'Bekijk en download',
                        onTap: () => _navigate(context, const ClientInvoicesScreen()),
                      ),
                    ],
                  ),

                  // ── Beveiliging (alleen tonen als biometric beschikbaar) ──
                  if (!_biometricLoading && _biometricAvailable) ...[
                    const SizedBox(height: 24),
                    _sectionLabel('BEVEILIGING'),
                    _BiometricToggleCard(
                      label: _biometricLabel,
                      enabled: _biometricEnabled,
                      onChanged: _toggleBiometric,
                    ),
                  ],

                  const SizedBox(height: 24),
                  _sectionLabel('HULP'),
                  _GroupedTilesCard(
                    tiles: [
                      _TileData(
                        icon: Icons.headset_mic_rounded,
                        iconColor: const Color(0xFF6A1B9A),
                        iconBg: const Color(0xFFF3E5F5),
                        label: 'Support',
                        subtitle: 'FAQ en contactformulier',
                        onTap: () => _navigate(context, const ClientSupportScreen()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.sora(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// BIOMETRIC TOGGLE CARD
// ═══════════════════════════════════════════════════════════════════

class _BiometricToggleCard extends StatelessWidget {
  const _BiometricToggleCard({
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icoon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                label == 'Face ID'
                    ? Icons.face
                    : label == 'Touch ID'
                        ? Icons.fingerprint
                        : Icons.lock_outline_rounded,
                size: 20,
                color: const Color(0xFFE65100),
              ),
            ),
            const SizedBox(width: 14),
            // Label + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    enabled
                        ? 'Ingeschakeld — log snel in'
                        : 'Schakel in voor snelle toegang',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            // Toggle
            Switch.adaptive(
              value: enabled,
              onChanged: onChanged,
              activeColor: GymiesColors.primary,
              activeTrackColor: GymiesColors.darkBlue,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// GROUPED TILES CARD (iOS-stijl)
// ═══════════════════════════════════════════════════════════════════

class _TileData {
  const _TileData({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
}

class _GroupedTilesCard extends StatelessWidget {
  const _GroupedTilesCard({required this.tiles});
  final List<_TileData> tiles;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(tiles.length, (i) {
          final t = tiles[i];
          final isLast = i == tiles.length - 1;
          return Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Haptics.selection();
                    t.onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        // Icoon
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: t.iconBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(t.icon, size: 20, color: t.iconColor),
                        ),
                        const SizedBox(width: 14),
                        // Label + subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.label,
                                style: GoogleFonts.sora(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                t.subtitle,
                                style: GoogleFonts.sora(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 70,
                  color: Colors.grey.shade200,
                ),
            ],
          );
        }),
      ),
    );
  }
}
