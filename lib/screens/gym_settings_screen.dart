import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'login_register_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/trainer_state_views.dart';

/// Een gym-locatie (naam, adres, stad, postcode).
class GymLocation {
  GymLocation({
    this.name = '',
    this.address = '',
    this.city = '',
    this.postalCode = '',
  });

  factory GymLocation.fromJson(Map<String, dynamic> json) {
    return GymLocation(
      name: (json['name'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      postalCode: (json['postal_code'] ?? json['postalCode'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'city': city,
        'postal_code': postalCode,
      };

  String name;
  String address;
  String city;
  String postalCode;

  String get displayAddress {
    final parts = [address, postalCode, city].where((s) => s.trim().isNotEmpty);
    return parts.join(', ');
  }
}

class GymSettingsScreen extends StatefulWidget {
  const GymSettingsScreen({super.key});

  @override
  State<GymSettingsScreen> createState() => _GymSettingsScreenState();
}

class _GymSettingsScreenState extends State<GymSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _nameController = TextEditingController();
  List<GymLocation> _locations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await context.read<GymiesApi>().getGymSettings();
      if (!mounted) return;
      _nameController.text = mapStr(s, ['name', 'gym_name', 'display_name']);
      final raw = s['locations'];
      if (raw is List) {
        _locations = raw
            .map((e) => GymLocation.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } else {
        _locations = [];
      }
      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon instellingen niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await GymiesDialog.destructive(
      context,
      title: 'Uitloggen',
      message: 'Weet je zeker dat je wilt uitloggen?',
      icon: Icons.logout_rounded,
      confirmLabel: 'Uitloggen',
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthService>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
      (r) => false,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<GymiesApi>().updateGymSettings({
        'name': _nameController.text.trim(),
        'locations': _locations.map((l) => l.toJson()).toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Instellingen opgeslagen'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAddLocation() {
    _showLocationDialog(
      location: null,
      onSave: (loc) {
        setState(() => _locations = [..._locations, loc]);
      },
    );
  }

  void _showEditLocation(int index) {
    _showLocationDialog(
      location: _locations[index],
      onSave: (loc) {
        setState(() {
          _locations = List.from(_locations)..[index] = loc;
        });
      },
    );
  }

  void _removeLocation(int index) {
    setState(() => _locations = List.from(_locations)..removeAt(index));
  }

  void _showLocationDialog({
    GymLocation? location,
    required void Function(GymLocation) onSave,
  }) {
    final nameC = TextEditingController(text: location?.name ?? '');
    final addressC = TextEditingController(text: location?.address ?? '');
    final cityC = TextEditingController(text: location?.city ?? '');
    final postalC = TextEditingController(text: location?.postalCode ?? '');

    GymiesDialog.custom<void>(
      context,
      title: location == null ? 'Locatie toevoegen' : 'Locatie bewerken',
      icon: Icons.location_on_rounded,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                labelText: 'Naam *',
                hintText: 'bijv. Centrum, Noord, Zuid',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressC,
              decoration: const InputDecoration(
                labelText: 'Adres',
                hintText: 'Straat en huisnummer',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: postalC,
                    decoration: const InputDecoration(
                      labelText: 'Postcode',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: cityC,
                    decoration: const InputDecoration(
                      labelText: 'Stad',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        GymiesDialogAction(
          label: 'Annuleren',
          returnValue: null,
        ),
        GymiesDialogAction(
          label: 'Opslaan',
          isPrimary: true,
          onPressed: () {
            if (nameC.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Naam is verplicht voor een locatie.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            final loc = GymLocation(
              name: nameC.text.trim(),
              address: addressC.text.trim(),
              city: cityC.text.trim(),
              postalCode: postalC.text.trim(),
            );
            Navigator.pop(context);
            onSave(loc);
          },
        ),
      ],
    ).then((_) {
      nameC.dispose();
      addressC.dispose();
      cityC.dispose();
      postalC.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Gym-instellingen'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Gym-naam',
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Locaties',
                            style: GoogleFonts.sora(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Haptics.selection();
                              _showAddLocation();
                            },
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Locatie toevoegen'),
                            style: TextButton.styleFrom(
                              foregroundColor: GymiesColors.darkBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_locations.isEmpty)
                        Card(
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Nog geen locaties',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Voeg vestigingen toe waar je gym actief is.',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._locations.asMap().entries.map((e) {
                          final i = e.key;
                          final loc = e.value;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Colors.white,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
                                child: Icon(
                                  Icons.location_on,
                                  color: GymiesColors.darkBlue,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                loc.name.isNotEmpty ? loc.name : 'Locatie ${i + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              subtitle: loc.displayAddress.isNotEmpty
                                  ? Text(
                                      loc.displayAddress,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 13,
                                      ),
                                    )
                                  : null,
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  Haptics.selection();
                                  if (v == 'edit') _showEditLocation(i);
                                  if (v == 'delete') {
                                    Haptics.heavy();
                                    _removeLocation(i);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined, size: 20),
                                        SizedBox(width: 8),
                                        Text('Bewerken'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Verwijderen', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _saving ? null : () {
                          Haptics.light();
                          _save();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(_saving ? 'Opslaan...' : 'Opslaan'),
                      ),
                      const SizedBox(height: 32),
                      const Divider(),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.logout_rounded, color: Colors.red),
                          label: const Text(
                            'Uitloggen',
                            style: TextStyle(color: Colors.red),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            Haptics.heavy();
                            _logout();
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
        ),
      ),
    );
  }
}
