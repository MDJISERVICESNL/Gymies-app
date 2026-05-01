import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/gymies_theme.dart';
import 'client_invoices_screen.dart';
import 'client_profile_screen.dart';
import 'client_support_screen.dart';

/// Instellingen-scherm voor klanten — modern iOS-grouped-tiles design.
class ClientSettingsScreen extends StatelessWidget {
  const ClientSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          // ── Compacte navy header ──
          SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: GymiesColors.darkBlue,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: GymiesColors.primary,
              onPressed: () => Navigator.of(context).pop(),
            ),
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
                        'Instellingen',
                        style: GoogleFonts.fjallaOne(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: GymiesColors.primary,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Beheer je profiel en voorkeuren',
                        style: GoogleFonts.roboto(
                          fontSize: 13,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Tiles ──
          SliverToBoxAdapter(
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
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.roboto(
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
            color: Colors.black.withValues(alpha:0.05),
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
                  onTap: t.onTap,
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
                                style: GoogleFonts.roboto(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                t.subtitle,
                                style: GoogleFonts.roboto(
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
