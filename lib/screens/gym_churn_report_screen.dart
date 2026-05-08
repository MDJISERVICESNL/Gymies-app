import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';

class GymChurnReportScreen extends StatefulWidget {
  final String gymId;
  final String gymName;

  const GymChurnReportScreen({
    Key? key,
    required this.gymId,
    required this.gymName,
  }) : super(key: key);

  @override
  State<GymChurnReportScreen> createState() => _GymChurnReportScreenState();
}

class _GymChurnReportScreenState extends State<GymChurnReportScreen> {
  late Future<Map<String, dynamic>> _churnDataFuture;
  final Set<String> _expandedMembers = {};
  bool _isRecalculating = false;

  @override
  void initState() {
    super.initState();
    _loadChurnData();
  }

  void _loadChurnData() {
    if (mounted) {
      final api = context.read<GymiesApi>();
      setState(() {
        _churnDataFuture = api.getGymChurnReport(widget.gymId);
      });
    }
  }

  Future<void> _recalculateChurn() async {
    Haptics.lightImpact();
    final api = context.read<GymiesApi>();
    setState(() => _isRecalculating = true);

    try {
      await api.getGymChurnReport(widget.gymId, recalculate: true);

      if (mounted) {
        _loadChurnData();
        setState(() => _isRecalculating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Churn gegevens herberekend'),
            backgroundColor: GymiesColors.primary,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isRecalculating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fout bij herberekenen: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: '${widget.gymName} - Churn Analyse',
        centerTitle: false,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _churnDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(GymiesColors.primary),
              ),
            );
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            String errorMessage = 'Er is een fout opgetreden';
            if (error is ApiException) {
              errorMessage = error.message;
            }

            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: GymiesColors.accent,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage,
                    textAlign: TextAlign.center,
                    style: GymiesTextStyles.bodyMedium.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _loadChurnData());
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Opnieuw laden'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: Text('Geen gegevens beschikbaar'),
            );
          }

          final data = snapshot.data!;
          final summary = data['summary'] as Map<String, dynamic>;
          final members = (data['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .toList();

          // Sort by score descending (highest risk first)
          members.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));

          return RefreshIndicator(
            onRefresh: () async {
              _loadChurnData();
              await _churnDataFuture;
            },
            color: GymiesColors.primary,
            backgroundColor: Colors.white,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Summary Cards
                _buildSummarySection(summary),
                const SizedBox(height: 24),

                // Recalculate Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isRecalculating ? null : _recalculateChurn,
                    icon: _isRecalculating
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _isRecalculating ? Colors.grey : GymiesColors.darkBlue,
                              ),
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      _isRecalculating ? 'Bezig met herberekenen...' : 'Herbereken',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Member List Header
                Text(
                  'Leden (${members.length})',
                  style: GymiesTextStyles.headlineSmall.copyWith(
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 12),

                // Member List
                ...members.map((member) {
                  final isExpanded = _expandedMembers.contains(member['user_id']);
                  return _buildMemberCard(member, isExpanded);
                }),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummarySection(Map<String, dynamic> summary) {
    final highRiskCount = summary['high_risk_count'] as int;
    final mediumRiskCount = summary['medium_risk_count'] as int;
    final lowRiskCount = summary['low_risk_count'] as int;
    final avgScore = (summary['avg_score'] as num).toDouble();

    return Column(
      children: [
        // Risk Count Cards
        Row(
          children: [
            Expanded(
              child: _buildRiskCard(
                label: 'Hoog risico',
                count: highRiskCount,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildRiskCard(
                label: 'Gemiddeld risico',
                count: mediumRiskCount,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildRiskCard(
                label: 'Laag risico',
                count: lowRiskCount,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Average Score Gauge
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                'Gemiddelde Churn Score',
                style: GymiesTextStyles.bodyMedium.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                avgScore.toStringAsFixed(1),
                style: GymiesTextStyles.headlineLarge.copyWith(
                  color: GymiesColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: avgScore / 100,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getRiskColor(avgScore.toInt()),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '0 — 100',
                style: GymiesTextStyles.bodySmall.copyWith(
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRiskCard({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$count',
                style: GymiesTextStyles.titleMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GymiesTextStyles.bodySmall.copyWith(
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member, bool isExpanded) {
    final userId = member['user_id'] as String;
    final name = member['name'] as String;
    final score = (member['score'] as num).toInt();
    final riskLevel = member['risk_level'] as String;
    final lastBooking = member['last_booking'] as String?;
    final signals = member['signals'] as Map<String, dynamic>;

    final topSignal = _getTopSignal(signals);

    return GestureDetector(
      onTap: () {
        Haptics.lightImpact();
        setState(() {
          if (_expandedMembers.contains(userId)) {
            _expandedMembers.remove(userId);
          } else {
            _expandedMembers.add(userId);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
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
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: GymiesTextStyles.titleMedium.copyWith(
                            color: GymiesColors.darkBlue,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildScoreBadge(score),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        lastBooking ?? 'Geen boeking',
                        style: GymiesTextStyles.bodySmall.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  if (topSignal.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: GymiesColors.accentLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Top signaal: $topSignal',
                        style: GymiesTextStyles.bodySmall.copyWith(
                          color: GymiesColors.accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isExpanded) ...[
              Container(
                height: 1,
                color: Colors.grey.shade200,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildSignalsDetail(signals),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: GymiesColors.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBadge(int score) {
    final color = _getRiskColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        '$score',
        style: GymiesTextStyles.titleSmall.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSignalsDetail(Map<String, dynamic> signals) {
    final signalsList = [
      ('Frequentie daling', signals['frequency_drop'] as num?),
      ('Dagen inactief', signals['days_inactive'] as num?),
      ('Consistentie', signals['consistency'] as num?),
      ('Contract einde', signals['contract_end'] as num?),
      ('Annuleringspercentage', signals['cancellation_rate'] as num?),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Risicosignalen',
          style: GymiesTextStyles.titleSmall.copyWith(
            color: GymiesColors.darkBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...signalsList.map((signal) {
          final label = signal.$1;
          final value = signal.$2;
          final score = value != null ? (value as num).toInt() : 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: GymiesTextStyles.bodySmall.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      '$score',
                      style: GymiesTextStyles.bodySmall.copyWith(
                        color: GymiesColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getRiskColor(score),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _getRiskColor(int score) {
    if (score >= 60) {
      return Colors.red;
    } else if (score >= 30) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  String _getTopSignal(Map<String, dynamic> signals) {
    final entries = [
      ('Frequentie daling', signals['frequency_drop'] as num?),
      ('Dagen inactief', signals['days_inactive'] as num?),
      ('Consistentie', signals['consistency'] as num?),
      ('Contract einde', signals['contract_end'] as num?),
      ('Annuleringspercentage', signals['cancellation_rate'] as num?),
    ];

    String topLabel = '';
    num topValue = -1;

    for (final entry in entries) {
      final value = entry.$2 ?? 0;
      if (value > topValue) {
        topValue = value;
        topLabel = entry.$1;
      }
    }

    return topLabel;
  }
}
