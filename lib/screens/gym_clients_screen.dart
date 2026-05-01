import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class GymClientsScreen extends StatefulWidget {
  const GymClientsScreen({super.key});

  @override
  State<GymClientsScreen> createState() => _GymClientsScreenState();
}

class _GymClientsScreenState extends State<GymClientsScreen> {
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
      final list = await context.read<GymiesApi>().getGymClients();
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
        _error = 'Kon klanten niet laden.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Klanten'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _clients.isEmpty
            ? ListView(
                children: [
                  TrainerEmptyState(
                    icon: Icons.person_outline_rounded,
                    title: 'Geen klanten',
                    subtitle: 'Er zijn nog geen klanten gekoppeld aan deze gym.',
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _clients.length,
                itemBuilder: (_, i) {
                  final c = _clients[i];
                  return GestureDetector(
                    onTap: () => Haptics.selection(),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: GymiesColors.primary.withValues(alpha: 0.3),
                          child: Text(
                            (mapStr(c, ['name', 'display_name']).isNotEmpty
                                    ? mapStr(c, ['name', 'display_name'])[0]
                                    : '?')
                                .toUpperCase(),
                          ),
                        ),
                        title: Text(
                          mapStr(c, ['name', 'display_name', 'email']),
                          style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(mapStr(c, ['email'])),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
