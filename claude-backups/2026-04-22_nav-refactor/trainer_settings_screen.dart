import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import 'login_register_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'action_history_screen.dart';
import 'trainer_documents_screen.dart';
import 'trainer_dossier_builder_screen.dart';
import 'trainer_profile_screen.dart';
import 'trainer_pro_hub_screen.dart';
import 'trainer_promo_codes_screen.dart';
import 'trainer_studio_screen.dart';
import 'trainer_subscription_screen.dart';

/// Instellingen-scherm met geconsolideerde menu-items.
class TrainerSettingsScreen extends StatelessWidget {
  const TrainerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ent = context.watch<SubscriptionEntitlementsService>();
    final hasDossier = ent.coachToolsEnabled;
    final hasProHub = ent.proHubEnabled;
    final hasSuite = ent.suiteEnabled;
    final tierLabel = ent.tier != null && ent.tier!.isNotEmpty
        ? ent.tier![0].toUpperCase() + ent.tier!.substring(1)
        : 'Pro';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Instellingen'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SettingsTile(
            icon: Icons.person_outline_rounded,
            label: 'Mijn profiel',
            onTap: () => _navigate(context, const TrainerProfileScreen()),
          ),
          _SettingsTile(
            icon: Icons.folder_outlined,
            label: 'Documenten',
            onTap: () => _navigate(context, const TrainerDocumentsScreen()),
          ),
          if (hasDossier)
            _SettingsTile(
              icon: Icons.folder_shared_outlined,
              label: 'Dossier opstellen',
              onTap: () =>
                  _navigate(context, const TrainerDossierBuilderScreen()),
            ),
          _SettingsTile(
            icon: Icons.workspace_premium_outlined,
            label: 'Abonnement ($tierLabel)',
            onTap: () => _navigate(context, const TrainerSubscriptionScreen()),
          ),
          if (hasProHub)
            _SettingsTile(
              icon: Icons.auto_graph_rounded,
              label: 'Pro Hub',
              onTap: () => _navigate(context, const TrainerProHubScreen()),
            ),
          if (hasSuite) ...[
            _SettingsTile(
              icon: Icons.local_offer_outlined,
              label: 'Promocodes',
              onTap: () => _navigate(context, const TrainerPromoCodesScreen()),
            ),
            _SettingsTile(
              icon: Icons.hub_outlined,
              label: 'Studio & onboarding',
              onTap: () => _navigate(context, const TrainerStudioScreen()),
            ),
          ],
          if (kDebugMode)
            _SettingsTile(
              icon: Icons.history_rounded,
              label: 'Actiegeschiedenis',
              onTap: () => _navigate(context, const ActionHistoryScreen()),
            ),
          const Divider(height: 24),
          _SettingsTile(
            icon: Icons.privacy_tip_rounded,
            label: 'Privacy & gegevens',
            onTap: () => _showPrivacySheet(context),
          ),
        ],
      ),
    );
  }

  void _showPrivacySheet(BuildContext context) {
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
              _PrivacyTile(
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
              _PrivacyTile(
                icon: Icons.delete_forever_outlined,
                iconColor: Colors.red.shade600,
                title: 'Account verwijderen',
                subtitle: 'Verwijder permanent je account en al je gegevens (AVG Art. 17)',
                danger: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Account verwijderen'),
                      content: const Text(
                        'Dit verwijdert je account en alle bijbehorende gegevens permanent. '
                        'Deze actie kan niet ongedaan worden gemaakt.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(d).pop(false),
                          child: const Text('Annuleren'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(d).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Verwijderen'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Account verwijderaanvraag ingediend'),
                      ),
                    );
                    await context.read<AuthService>().logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const LoginRegisterScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    // Geen pop() vóór push: de gebruiker kan via de back-knop terugkeren naar Instellingen.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile({
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

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: GymiesColors.darkBlue),
      title: Text(
        label,
        style: GoogleFonts.fjallaOne(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: GymiesColors.darkBlue,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: GymiesColors.darkBlue),
      onTap: onTap,
    );
  }
}
