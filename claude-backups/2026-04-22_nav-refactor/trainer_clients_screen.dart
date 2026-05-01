import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'trainer_client_dossier_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class TrainerClientsScreen extends StatefulWidget {
  const TrainerClientsScreen({
    super.key,
    this.onAvatarTap,
    this.avatarLabel,
  });

  final VoidCallback? onAvatarTap;
  final String? avatarLabel;

  @override
  State<TrainerClientsScreen> createState() => _TrainerClientsScreenState();
}

class _TrainerClientsScreenState extends State<TrainerClientsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<GymiesApi>().getTrainerSleepingClients();
      if (!mounted) return;
      setState(() {
        _clients = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon klantenoverzicht niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _openClient(Map<String, dynamic> client) async {
    final clientId = mapStr(client, ['client_user_id', 'clientUserId', 'id']);
    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Klant-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final name = mapStr(client, ['name', 'full_name']).isNotEmpty
        ? mapStr(client, ['name', 'full_name'])
        : 'Klant';
    final email = mapStr(client, ['email', 'email_address']);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainerClientDossierScreen(
          clientUserId: clientId,
          clientName: name,
          clientEmail: email,
        ),
      ),
    );
  }

  Future<void> _bulkMessage() async {
    if (_clients.isEmpty) return;
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var sending = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Bulk bericht'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 4,
                  enabled: !sending,
                  decoration: const InputDecoration(labelText: 'Bericht'),
                ),
                if (sending) ...[
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Versturen…'),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        if (controller.text.trim().isEmpty) return;
                        final ids = _clients
                            .map((e) => mapStr(e, ['client_user_id', 'clientUserId', 'id']))
                            .where((e) => e.isNotEmpty)
                            .toList();
                        if (ids.isEmpty) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Geen geldige klant-IDs gevonden. Vernieuw de lijst en probeer opnieuw.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        setDialogState(() => sending = true);
                        try {
                          await context.read<GymiesApi>().sendTrainerBulkMessage(
                            clientUserIds: ids,
                            body: controller.text.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bulk bericht verstuurd'),
                              backgroundColor: GymiesColors.darkBlue,
                            ),
                          );
                        } on ApiException catch (e) {
                          if (ctx.mounted) setDialogState(() => sending = false);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.message),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } catch (e) {
                          if (ctx.mounted) setDialogState(() => sending = false);
                          debugPrint('[TrainerClients] Bulk bericht fout: $e');
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Kon bericht niet versturen. Probeer opnieuw.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                ),
                child: Text(sending ? 'Bezig…' : 'Versturen'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Klanten / CRM',
        onAvatarTap: widget.onAvatarTap,
        avatarLabel: widget.avatarLabel,
      ),
      floatingActionButton: context.watch<SubscriptionEntitlementsService>().hasFeature('bulk_message')
          ? FloatingActionButton.extended(
              onPressed: _bulkMessage,
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Bulk bericht'),
            )
          : null,
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _clients.isEmpty
                  ? ListView(
                      padding: EdgeInsets.zero,
                      children: const [
                        TrainerEmptyState(
                          icon: Icons.people_alt_outlined,
                          title: 'Geen sleeping clients',
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _clients.length,
                      itemBuilder: (_, i) {
                        final c = _clients[i];
                        final name = mapStr(c, ['name', 'full_name']).isNotEmpty
                            ? mapStr(c, ['name', 'full_name'])
                            : 'Klant';
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(name[0].toUpperCase()),
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.fjallaOne(
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            subtitle: Text(mapStr(c, ['email', 'email_address'])),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openClient(c),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

}
