import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'gym_locations_screen.dart';
import 'gym_churn_report_screen.dart';
import 'gym_finance_screen.dart';
import 'login_register_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/trainer_state_views.dart';
import '../l10n/generated/app_localizations.dart';

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
        _error = S.of(context).konInstellingenNietLaden;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await GymiesDialog.destructive(
      context,
      title: S.of(context).uitloggen,
      message: S.of(context).logoutConfirmMessage,
      icon: Icons.logout_rounded,
      confirmLabel: S.of(context).uitloggen,
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
        SnackBar(
          content: Text(S.of(context).instellingenOpgeslagen),
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

  Future<void> _removeLocation(int index) async {
    final confirmed = await GymiesDialog.destructive(
      context,
      title: S.of(context).locatieVerwijderen,
      message: S.of(context).wetJeZekerDatJeDezeLocatieWiltVerwijderen,
      icon: Icons.delete_outline_rounded,
      confirmLabel: S.of(context).verwijderen,
    );
    if (confirmed != true || !mounted) return;
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
      title: location == null ? S.of(context).locatieToevoegen : S.of(context).locatieBewerken,
      icon: Icons.location_on_rounded,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: InputDecoration(
                labelText: S.of(context).naam,
                hintText: S.of(context).bijvCentrumNoordZuid,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressC,
              decoration: InputDecoration(
                labelText: S.of(context).adres,
                hintText: S.of(context).straatEnHuisnummer,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: postalC,
                    decoration: InputDecoration(
                      labelText: S.of(context).postcode,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: cityC,
                    decoration: InputDecoration(
                      labelText: S.of(context).stad,
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
          label: S.of(context).annuleren,
          returnValue: null,
        ),
        GymiesDialogAction(
          label: S.of(context).opslaan,
          isPrimary: true,
          onPressed: () {
            if (nameC.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context).naamIsVerplichtVoorEenLocatie),
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

  void _showInviteMemberDialog() {
    Haptics.selection();
    final emailC = TextEditingController();
    String selectedRole = 'member';

    GymiesDialog.custom<void>(
      context,
      title: S.of(context).teamlidUitnodigen,
      icon: Icons.group_add_rounded,
      content: StatefulBuilder(
        builder: (context, setSheetState) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailC,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: S.of(context).emailadres,
                    hintText: 'naam@voorbeeld.nl',
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  S.of(context).rol,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                _RoleOption(
                  title: S.of(context).medewerker,
                  subtitle: S.of(context).kanBoekingen,
                  icon: Icons.person_outline_rounded,
                  selected: selectedRole == 'member',
                  onTap: () => setSheetState(() => selectedRole = 'member'),
                ),
                const SizedBox(height: 8),
                _RoleOption(
                  title: S.of(context).beheerder,
                  subtitle: S.of(context).volledigeToegang,
                  icon: Icons.admin_panel_settings_outlined,
                  selected: selectedRole == 'admin',
                  onTap: () => setSheetState(() => selectedRole = 'admin'),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        GymiesDialogAction(
          label: S.of(context).annuleren,
          returnValue: null,
        ),
        GymiesDialogAction(
          label: S.of(context).uitnodigen,
          isPrimary: true,
          onPressed: () async {
            final email = emailC.text.trim();
            if (email.isEmpty || !email.contains('@')) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context).voerEenGeldigEmailadresIn),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            Navigator.pop(context);
            try {
              await context.read<GymiesApi>().inviteGymMember(
                email: email,
                role: selectedRole,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context).uitnodigingVerstuurdNaar(email)),
                  backgroundColor: GymiesColors.darkBlue,
                ),
              );
            } on ApiException catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.message), backgroundColor: Colors.red),
              );
            }
          },
        ),
      ],
    ).then((_) {
      emailC.dispose();
    });
  }

  String? _orgId() {
    final user = context.read<AuthService>().user ?? {};
    final orgId = user['organisation_id']?.toString();
    return (orgId != null && orgId.isNotEmpty && orgId != 'null') ? orgId : null;
  }

  void _openLocations() {
    final orgId = _orgId();
    if (orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).geenOrganisatieGevonden),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GymLocationsScreen(
        orgId: orgId,
        orgName: _nameController.text.trim(),
      ),
    ));
  }

  void _openChurnReport() {
    final orgId = _orgId();
    if (orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).geenOrganisatieGevonden),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GymChurnReportScreen(
        gymId: orgId,
        gymName: _nameController.text.trim(),
      ),
    ));
  }

  void _openFinance() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const GymFinanceScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(title: S.of(context).gyminstellingen),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: GymiesListBody(
            loading: _loading,
            error: _error,
            onRefresh: _load,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Gym naam ──────────────────────────────────
                  _SectionHeader(
                    title: S.of(context).gymGegevens,
                    icon: Icons.business_rounded,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: S.of(context).gymnaam,
                      prefixIcon: const Icon(Icons.fitness_center_rounded, size: 20),
                    ),
                  ),

                  // ── Locaties ──────────────────────────────────
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(
                        title: S.of(context).locaties,
                        icon: Icons.location_on_rounded,
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Haptics.selection();
                          _showAddLocation();
                        },
                        icon: const Icon(Icons.add, size: 20),
                        label: Text(S.of(context).toevoegen),
                        style: TextButton.styleFrom(
                          foregroundColor: GymiesColors.darkBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_locations.isEmpty)
                    _EmptyCard(
                      icon: Icons.location_on_outlined,
                      title: S.of(context).nogGeenLocaties,
                      subtitle: S.of(context).voegVestigingenToeWaarJeGymActiefIs,
                    )
                  else
                    ..._locations.asMap().entries.map((e) {
                      final i = e.key;
                      final loc = e.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: GymiesColors.primary.withOpacity(0.2),
                            child: const Icon(
                              Icons.location_on,
                              color: GymiesColors.darkBlue,
                              size: 22,
                            ),
                          ),
                          title: Text(
                            loc.name.isNotEmpty ? loc.name : '${S.of(context).locatie} ${i + 1}',
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
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    const Icon(Icons.edit_outlined, size: 20),
                                    const SizedBox(width: 8),
                                    Text(S.of(context).bewerken),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Text(S.of(context).verwijderen, style: const TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  // ── Opslaan knop ──────────────────────────────
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : () {
                      Haptics.light();
                      _save();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      _saving ? S.of(context).opslaan2 : S.of(context).opslaan,
                      style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                    ),
                  ),

                  // ── Team beheer ───────────────────────────────
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: S.of(context).teamBeheer,
                    icon: Icons.group_rounded,
                  ),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.person_add_rounded,
                    title: S.of(context).teamlidUitnodigen,
                    subtitle: S.of(context).nodigMedewerkersOfBeheerdersUit,
                    onTap: _showInviteMemberDialog,
                  ),

                  // ── Geavanceerd ───────────────────────────────
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: S.of(context).geavanceerd,
                    icon: Icons.insights_rounded,
                  ),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.location_city_rounded,
                    title: S.of(context).locatieBeheer,
                    subtitle: S.of(context).statistiekenTransfersEnDupliceren,
                    onTap: _openLocations,
                  ),
                  const SizedBox(height: 10),
                  _ActionTile(
                    icon: Icons.trending_down_rounded,
                    title: S.of(context).churnRapport,
                    subtitle: S.of(context).risicoscoresEnVerloopanalyse,
                    onTap: _openChurnReport,
                    accentColor: Colors.red.shade400,
                  ),

                  // ── Financiën ───────────────────────────────────
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: 'Financiën',
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.payment_rounded,
                    title: 'Financiën & Mollie',
                    subtitle: 'Uitbetalingen, facturen en Mollie-koppeling',
                    onTap: _openFinance,
                  ),

                  // ── Uitloggen ─────────────────────────────────
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout_rounded, color: Colors.red),
                      label: Text(
                        S.of(context).uitloggen,
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Haptics.heavy();
                        _logout();
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: GymiesColors.darkBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: GymiesColors.darkBlue,
          ),
        ),
      ],
    );
  }
}

// ── Action tile ─────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? GymiesColors.darkBlue;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
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
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Role option (team invite dialog) ─────────────────────────────────
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? GymiesColors.darkBlue : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected ? GymiesColors.darkBlue.withOpacity(0.04) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? GymiesColors.darkBlue : Colors.grey.shade500, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? GymiesColors.darkBlue : Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: GymiesColors.darkBlue, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Empty card ──────────────────────────────────────────────────────
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
