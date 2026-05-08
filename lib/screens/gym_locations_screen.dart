import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';

class GymLocationsScreen extends StatefulWidget {
  final String orgId;
  final String orgName;

  const GymLocationsScreen({
    Key? key,
    required this.orgId,
    required this.orgName,
  }) : super(key: key);

  @override
  State<GymLocationsScreen> createState() => _GymLocationsScreenState();
}

class _GymLocationsScreenState extends State<GymLocationsScreen> {
  late GymiesApi _api;
  List<dynamic> _locations = [];
  Map<String, dynamic> _locationsStats = {};
  bool _loading = true;
  String? _error;
  Map<String, bool> _expandedLocations = {};

  @override
  void initState() {
    super.initState();
    _api = context.read<GymiesApi>();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final locations = await _api.getGymLocations(widget.orgId);
      if (!mounted) return;

      // Load stats for all locations
      final stats = <String, dynamic>{};
      for (final location in locations) {
        try {
          final locStats = await _api.getGymLocationStats(widget.orgId, location['id']);
          if (mounted) {
            stats[location['id']] = locStats;
          }
        } catch (e) {
          // Skip stats loading error for individual locations
        }
      }

      if (mounted) {
        setState(() {
          _locations = locations;
          _locationsStats = stats;
          _loading = false;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Er is een fout opgetreden';
          _loading = false;
        });
      }
    }
  }

  void _toggleExpanded(String locationId) {
    Haptics.lightImpact();
    setState(() {
      _expandedLocations[locationId] = !(_expandedLocations[locationId] ?? false);
    });
  }

  void _showTransferTrainerSheet(String locationId, String locationName) {
    Haptics.lightImpact();
    showModalBottomSheet(
      context: context,
      builder: (context) => _TransferTrainerBottomSheet(
        orgId: widget.orgId,
        currentLocationId: locationId,
        currentLocationName: locationName,
        allLocations: _locations,
      ),
    );
  }

  void _showDuplicateSessionSheet(String locationId, String locationName) {
    Haptics.lightImpact();
    showModalBottomSheet(
      context: context,
      builder: (context) => _DuplicateSessionBottomSheet(
        orgId: widget.orgId,
        currentLocationId: locationId,
        currentLocationName: locationName,
        allLocations: _locations,
      ),
    );
  }

  int get _totalCapacity {
    int total = 0;
    for (final loc in _locations) {
      total += (loc['capacity'] as int?) ?? 0;
    }
    return total;
  }

  int get _totalMembers {
    int total = 0;
    for (final loc in _locations) {
      total += (loc['member_count'] as int?) ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Vestigingen - ${widget.orgName}',
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: GymiesTextStyles.body1.copyWith(
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadLocations,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                        ),
                        child: Text(
                          'Opnieuw laden',
                          style: GymiesTextStyles.button.copyWith(
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLocations,
                  child: _locations.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: GymiesColors.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    Icons.location_city_rounded,
                                    size: 32,
                                    color: GymiesColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Geen vestigingen gevonden',
                                  style: GymiesTextStyles.h3.copyWith(
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Voeg vestigingen toe om ze hier te zien',
                                  style: GymiesTextStyles.body2.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            children: [
                              // Overview bar
                              _buildOverviewBar(),
                              const SizedBox(height: 16),
                              // Location cards
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  children: [
                                    for (int i = 0; i < _locations.length; i++)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: _buildLocationCard(_locations[i]),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                ),
        ),
    );
  }

  Widget _buildOverviewBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GymiesColors.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: GymiesColors.darkBlue.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildOverviewItem(
            label: 'Vestigingen',
            value: _locations.length.toString(),
          ),
          _buildOverviewItem(
            label: 'Totale capaciteit',
            value: _totalCapacity.toString(),
          ),
          _buildOverviewItem(
            label: 'Leden',
            value: _totalMembers.toString(),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem({required String label, required String value}) {
    return Column(
      children: [
        Text(
          value,
          style: GymiesTextStyles.h3.copyWith(
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GymiesTextStyles.caption.copyWith(
            color: GymiesColors.darkBlue.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard(Map<String, dynamic> location) {
    final locationId = location['id'] as String;
    final isExpanded = _expandedLocations[locationId] ?? false;
    final stats = _locationsStats[locationId];

    return GestureDetector(
      onTap: () => _toggleExpanded(locationId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: GymiesColors.darkBlue.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location['name'] ?? '',
                              style: GymiesTextStyles.h3.copyWith(
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              location['address'] ?? '',
                              style: GymiesTextStyles.body2.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (location['city'] != null)
                              Text(
                                location['city'],
                                style: GymiesTextStyles.caption.copyWith(
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: isExpanded ? 'Inklappen' : 'Uitvouwen',
                        child: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: GymiesColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildLocationInfo(
                        icon: Icons.people,
                        label: 'Capaciteit',
                        value: (location['capacity'] as int?)?.toString() ?? '–',
                      ),
                      _buildLocationInfo(
                        icon: Icons.person_add,
                        label: 'Trainers',
                        value: (location['trainer_count'] as int?)?.toString() ?? '–',
                      ),
                      _buildLocationInfo(
                        icon: Icons.group,
                        label: 'Leden',
                        value: (location['member_count'] as int?)?.toString() ?? '–',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isExpanded) ...[
              Divider(
                height: 1,
                color: Colors.grey.shade200,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stats != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Statistieken',
                            style: GymiesTextStyles.heading4.copyWith(
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildStatRow(
                            'Bezettingsgraad',
                            '${((stats['occupancy_rate'] as num?)?.toStringAsFixed(1) ?? '–')}%',
                          ),
                          const SizedBox(height: 8),
                          _buildStatRow(
                            'Boekingen vandaag',
                            (stats['bookings_today'] as int?)?.toString() ?? '–',
                          ),
                          const SizedBox(height: 8),
                          _buildStatRow(
                            'Boekingen deze week',
                            (stats['bookings_week'] as int?)?.toString() ?? '–',
                          ),
                          const SizedBox(height: 8),
                          _buildStatRow(
                            'Opbrengst MTD',
                            '€ ${((stats['revenue_mtd'] as num?)?.toStringAsFixed(2) ?? '–')}',
                          ),
                          const SizedBox(height: 8),
                          if (stats['popular_hours'] != null)
                            _buildStatRow(
                              'Populaire uren',
                              stats['popular_hours'].toString(),
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                _showTransferTrainerSheet(locationId, location['name']),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: GymiesColors.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Trainer overboeking',
                              style: GymiesTextStyles.button.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                _showDuplicateSessionSheet(locationId, location['name']),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: GymiesColors.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Dupliceer les',
                              style: GymiesTextStyles.button.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInfo({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: GymiesColors.primary, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GymiesTextStyles.heading4.copyWith(
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GymiesTextStyles.caption.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GymiesTextStyles.body2.copyWith(
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: GymiesTextStyles.body2.copyWith(
            color: GymiesColors.darkBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TransferTrainerBottomSheet extends StatefulWidget {
  final String orgId;
  final String currentLocationId;
  final String currentLocationName;
  final List<dynamic> allLocations;

  const _TransferTrainerBottomSheet({
    required this.orgId,
    required this.currentLocationId,
    required this.currentLocationName,
    required this.allLocations,
  });

  @override
  State<_TransferTrainerBottomSheet> createState() =>
      _TransferTrainerBottomSheetState();
}

class _TransferTrainerBottomSheetState extends State<_TransferTrainerBottomSheet> {
  late GymiesApi _api;
  String? _selectedTrainerId;
  String? _selectedTargetLocationId;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = context.read<GymiesApi>();
  }

  Future<void> _transferTrainer() async {
    if (_selectedTrainerId == null || _selectedTargetLocationId == null) {
      setState(() => _error = 'Selecteer een trainer en doellocatie');
      return;
    }

    Haptics.mediumImpact();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _api.transferTrainer(
        widget.orgId,
        _selectedTrainerId!,
        {'target_location_id': _selectedTargetLocationId},
      );

      if (mounted) {
        Haptics.successImpact();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trainer overgeboeking gelukt',
                style: GymiesTextStyles.body2.copyWith(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Er is een fout opgetreden');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetLocations =
        widget.allLocations.where((loc) => loc['id'] != widget.currentLocationId).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trainer overboeking',
                style: GymiesTextStyles.h3.copyWith(
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Van ${widget.currentLocationName}',
                style: GymiesTextStyles.body2.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Selecteer trainer',
                style: GymiesTextStyles.body1.copyWith(
                  color: GymiesColors.darkBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              // Placeholder: In a real app, this would list trainers from API
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedTrainerId ?? 'Kies een trainer...',
                  style: GymiesTextStyles.body1.copyWith(
                    color: _selectedTrainerId != null ? GymiesColors.darkBlue : Colors.grey.shade500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Doellocatie',
                style: GymiesTextStyles.body1.copyWith(
                  color: GymiesColors.darkBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (targetLocations.isEmpty)
                Text(
                  'Geen andere vestigingen beschikbaar',
                  style: GymiesTextStyles.body2.copyWith(
                    color: Colors.grey.shade600,
                  ),
                )
              else
                Column(
                  children: targetLocations.map((loc) {
                    final isSelected = _selectedTargetLocationId == loc['id'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTargetLocationId = loc['id']),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? GymiesColors.accentLight : Colors.grey.shade50,
                            border: Border.all(
                              color: isSelected ? GymiesColors.accent : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                loc['name'] ?? '',
                                style: GymiesTextStyles.body1.copyWith(
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const Spacer(),
                              if (isSelected)
                                Icon(Icons.check_circle,
                                    color: GymiesColors.accent, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: GymiesTextStyles.body2.copyWith(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _transferTrainer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(GymiesColors.darkBlue),
                          ),
                        )
                      : Text(
                          'Overboeking voltooien',
                          style: GymiesTextStyles.button.copyWith(
                            color: GymiesColors.darkBlue,
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
}

class _DuplicateSessionBottomSheet extends StatefulWidget {
  final String orgId;
  final String currentLocationId;
  final String currentLocationName;
  final List<dynamic> allLocations;

  const _DuplicateSessionBottomSheet({
    required this.orgId,
    required this.currentLocationId,
    required this.currentLocationName,
    required this.allLocations,
  });

  @override
  State<_DuplicateSessionBottomSheet> createState() =>
      _DuplicateSessionBottomSheetState();
}

class _DuplicateSessionBottomSheetState extends State<_DuplicateSessionBottomSheet> {
  late GymiesApi _api;
  String? _selectedSessionId;
  String? _selectedTargetLocationId;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = context.read<GymiesApi>();
  }

  Future<void> _duplicateSession() async {
    if (_selectedSessionId == null || _selectedTargetLocationId == null) {
      setState(() => _error = 'Selecteer een les en doellocatie');
      return;
    }

    Haptics.mediumImpact();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _api.duplicateGroupSession(
        widget.orgId,
        _selectedSessionId!,
        {'target_location_id': _selectedTargetLocationId},
      );

      if (mounted) {
        Haptics.successImpact();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Les gedupliceerd',
                style: GymiesTextStyles.body2.copyWith(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Er is een fout opgetreden');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetLocations =
        widget.allLocations.where((loc) => loc['id'] != widget.currentLocationId).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dupliceer les',
                style: GymiesTextStyles.h3.copyWith(
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Van ${widget.currentLocationName}',
                style: GymiesTextStyles.body2.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Selecteer les',
                style: GymiesTextStyles.body1.copyWith(
                  color: GymiesColors.darkBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              // Placeholder: In a real app, this would list sessions from API
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedSessionId ?? 'Kies een les...',
                  style: GymiesTextStyles.body1.copyWith(
                    color: _selectedSessionId != null ? GymiesColors.darkBlue : Colors.grey.shade500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Doellocatie',
                style: GymiesTextStyles.body1.copyWith(
                  color: GymiesColors.darkBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (targetLocations.isEmpty)
                Text(
                  'Geen andere vestigingen beschikbaar',
                  style: GymiesTextStyles.body2.copyWith(
                    color: Colors.grey.shade600,
                  ),
                )
              else
                Column(
                  children: targetLocations.map((loc) {
                    final isSelected = _selectedTargetLocationId == loc['id'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTargetLocationId = loc['id']),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? GymiesColors.accentLight : Colors.grey.shade50,
                            border: Border.all(
                              color: isSelected ? GymiesColors.accent : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                loc['name'] ?? '',
                                style: GymiesTextStyles.body1.copyWith(
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const Spacer(),
                              if (isSelected)
                                Icon(Icons.check_circle,
                                    color: GymiesColors.accent, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: GymiesTextStyles.body2.copyWith(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _duplicateSession,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(GymiesColors.darkBlue),
                          ),
                        )
                      : Text(
                          'Les dupliceren',
                          style: GymiesTextStyles.button.copyWith(
                            color: GymiesColors.darkBlue,
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
}
