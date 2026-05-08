import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';

class AmbassadorDashboardScreen extends StatefulWidget {
  const AmbassadorDashboardScreen({Key? key}) : super(key: key);

  @override
  State<AmbassadorDashboardScreen> createState() =>
      _AmbassadorDashboardScreenState();
}

class _AmbassadorDashboardScreenState extends State<AmbassadorDashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _loadingPayouts = false;
  String? _error;

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _referrals = [];
  List<Map<String, dynamic>> _payouts = [];

  late TabController _tabController;
  String _referralsFilter = 'all'; // all, trainers, sporters

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _referralsFilter = ['all', 'trainers', 'sporters'][_tabController.index];
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<GymiesApi>();

      final statsResult = await api.getAmbassadorStats();
      if (!mounted) return;

      List<Map<String, dynamic>> referralsResult = [];
      try {
        final referralsData = await api.getAmbassadorReferrals();
        referralsResult = List<Map<String, dynamic>>.from(referralsData['referrals'] ?? []);
      } catch (e) {
        // Referrals might not be available
      }

      if (!mounted) return;

      List<Map<String, dynamic>> payoutsResult = [];
      try {
        final payoutsData = await api.getAmbassadorPayouts();
        payoutsResult = List<Map<String, dynamic>>.from(payoutsData['payouts'] ?? []);
      } catch (e) {
        // Payouts might not be available
      }

      if (!mounted) return;

      setState(() {
        _stats = statsResult;
        _referrals = referralsResult;
        _payouts = payoutsResult;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Er is een fout opgetreden';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Onverwachte fout: $e';
        _loading = false;
      });
    }
  }

  Future<void> _requestPayout() async {
    await Haptics.tap();
    if (!mounted) return;
    final api = context.read<GymiesApi>();

    setState(() => _loadingPayouts = true);

    try {
      await api.requestAmbassadorPayout();

      if (!mounted) return;
      await Haptics.success();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Uitbetalingsverzoek ingediend'),
          backgroundColor: GymiesColors.primary,
          duration: const Duration(seconds: 3),
        ),
      );

      await _loadData();
    } on ApiException catch (e) {
      if (!mounted) return;
      await Haptics.error();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Fout bij uitbetalingsverzoek'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await Haptics.error();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Onverwachte fout'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingPayouts = false);
      }
    }
  }

  String _getTierColor(String? tier) {
    switch (tier?.toLowerCase()) {
      case 'elite':
        return '#FFD700'; // Gold
      case 'active':
        return '#C0C0C0'; // Silver
      case 'starter':
      default:
        return '#CD7F32'; // Bronze
    }
  }

  String _getTierLabel(String? tier) {
    switch (tier?.toLowerCase()) {
      case 'elite':
        return 'Elite';
      case 'active':
        return 'Actief';
      case 'starter':
      default:
        return 'Starter';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(
        title: 'Ambassadeur Dashboard',
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: GymiesColors.primary,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: GymiesColors.primary,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GymiesTextStyles.body1.copyWith(
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
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

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with tier badge
            _buildHeader(),
            const SizedBox(height: 24),

            // Stats cards
            _buildStatsCards(),
            const SizedBox(height: 24),

            // Earnings breakdown
            _buildEarningsBreakdown(),
            const SizedBox(height: 24),

            // Referrals section
            _buildReferralsSection(),
            const SizedBox(height: 24),

            // Payouts section
            _buildPayoutsSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final tier = _stats?['tier'] as String? ?? 'Starter';
    final tierColor = _getTierColor(tier);
    final tierLabel = _getTierLabel(tier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welkom terug!',
              style: GymiesTextStyles.heading2.copyWith(
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Je ambassadeur status',
              style: GymiesTextStyles.body2.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Color(int.parse('0xFF${tierColor.replaceFirst('#', '')}')),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            tierLabel,
            style: GymiesTextStyles.body2.copyWith(
              color: GymiesColors.darkBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    final totalEarnings = _stats?['total_earnings'] as num? ?? 0;
    final pendingPayout = _stats?['pending_payout'] as num? ?? 0;
    final totalReferrals = _stats?['total_referrals'] as num? ?? 0;
    final conversionRate = _stats?['conversion_rate'] as num? ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                label: 'Totale inkomsten',
                value: '€${totalEarnings.toStringAsFixed(2)}',
                icon: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                label: 'In afwachting',
                value: '€${pendingPayout.toStringAsFixed(2)}',
                icon: Icons.schedule,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                label: 'Totale referrals',
                value: totalReferrals.toString(),
                icon: Icons.people,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                label: 'Conversiepercentage',
                value: '${conversionRate.toStringAsFixed(1)}%',
                icon: Icons.percent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: GymiesColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GymiesTextStyles.body2.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GymiesTextStyles.heading3.copyWith(
              color: GymiesColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsBreakdown() {
    final trainerSignups = _stats?['trainer_signups'] as num? ?? 0;
    final sporterBookings = _stats?['sporter_bookings'] as num? ?? 0;

    final trainerEarnings = trainerSignups * 25;
    final sporterEarnings = sporterBookings * 3;
    final totalEarnings = trainerEarnings + sporterEarnings;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inkomstenafbraak',
            style: GymiesTextStyles.heading3.copyWith(
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 16),
          // Trainer signups
          _buildEarningsRow(
            label: 'Trainer aanmeldingen',
            count: trainerSignups.toInt(),
            amount: trainerEarnings,
            perUnit: 25,
            color: GymiesColors.primary,
          ),
          const SizedBox(height: 12),
          // Sporter bookings
          _buildEarningsRow(
            label: 'Sporter boekingen',
            count: sporterBookings.toInt(),
            amount: sporterEarnings,
            perUnit: 3,
            color: GymiesColors.accent,
          ),
          const SizedBox(height: 16),
          // Progress bar
          if (totalEarnings > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Totaal',
                      style: GymiesTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    Text(
                      '€${totalEarnings.toStringAsFixed(2)}',
                      style: GymiesTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          height: 8,
                          width: (trainerEarnings / totalEarnings) * 200,
                          decoration: BoxDecoration(
                            color: GymiesColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          height: 8,
                          width: (sporterEarnings / totalEarnings) * 200,
                          decoration: BoxDecoration(
                            color: GymiesColors.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEarningsRow({
    required String label,
    required int count,
    required num amount,
    required int perUnit,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GymiesTextStyles.body2.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
              Text(
                '$count × €$perUnit',
                style: GymiesTextStyles.body3.copyWith(
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        Text(
          '€${amount.toStringAsFixed(2)}',
          style: GymiesTextStyles.body1.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildReferralsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Jouw referrals',
          style: GymiesTextStyles.heading3.copyWith(
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                labelColor: GymiesColors.primary,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: GymiesColors.primary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'Alles'),
                  Tab(text: 'Trainers'),
                  Tab(text: 'Sporters'),
                ],
              ),
              const SizedBox(height: 8),
              _buildReferralsList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReferralsList() {
    List<Map<String, dynamic>> filteredReferrals = _referrals;

    if (_referralsFilter == 'trainers') {
      filteredReferrals = _referrals.where((r) => r['type'] == 'trainer').toList();
    } else if (_referralsFilter == 'sporters') {
      filteredReferrals = _referrals.where((r) => r['type'] == 'sporter').toList();
    }

    if (filteredReferrals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'Geen referrals',
              style: GymiesTextStyles.body1.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredReferrals.length,
      separatorBuilder: (_, __) => Divider(
        color: Colors.grey.shade200,
        height: 1,
      ),
      itemBuilder: (context, index) {
        final referral = filteredReferrals[index];
        return _buildReferralItem(referral);
      },
    );
  }

  Widget _buildReferralItem(Map<String, dynamic> referral) {
    final name = referral['name'] as String? ?? 'Onbekend';
    final type = referral['type'] as String? ?? 'sporter';
    final status = referral['status'] as String? ?? 'pending';
    final earnedAmount = referral['earned_amount'] as num? ?? 0;

    String statusLabel = 'In behandeling';
    Color statusColor = Colors.orange;

    if (status == 'active') {
      statusLabel = 'Actief';
      statusColor = Colors.green;
    } else if (status == 'completed') {
      statusLabel = 'Voltooid';
      statusColor = Colors.blue;
    }

    String typeLabel = type == 'trainer' ? 'Trainer' : 'Sporter';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: GymiesColors.accentLight,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GymiesTextStyles.body1.copyWith(
                  color: GymiesColors.darkBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GymiesTextStyles.body1.copyWith(
                    color: GymiesColors.darkBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeLabel,
                        style: GymiesTextStyles.body3.copyWith(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: GymiesTextStyles.body3.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '€${earnedAmount.toStringAsFixed(2)}',
                style: GymiesTextStyles.body1.copyWith(
                  color: GymiesColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'verdiend',
                style: GymiesTextStyles.body3.copyWith(
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutsSection() {
    final pendingPayout = _stats?['pending_payout'] as num? ?? 0;
    final canRequestPayout = pendingPayout > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Uitbetalingen',
          style: GymiesTextStyles.heading3.copyWith(
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 12),
        if (canRequestPayout)
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: GymiesColors.accentLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: GymiesColors.primary,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Klaar om uit te betalen',
                      style: GymiesTextStyles.body2.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '€${pendingPayout.toStringAsFixed(2)}',
                      style: GymiesTextStyles.heading2.copyWith(
                        color: GymiesColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _loadingPayouts ? null : _requestPayout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _loadingPayouts
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: GymiesColors.darkBlue,
                                ),
                              )
                            : const Text('Uitbetaling aanvragen'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        if (_payouts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                'Geen uitbetalingen nog',
                style: GymiesTextStyles.body1.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _payouts.length,
              separatorBuilder: (_, __) => Divider(
                color: Colors.grey.shade200,
                height: 1,
              ),
              itemBuilder: (context, index) {
                final payout = _payouts[index];
                return _buildPayoutItem(payout);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPayoutItem(Map<String, dynamic> payout) {
    final amount = payout['amount'] as num? ?? 0;
    final status = payout['status'] as String? ?? 'pending';
    final requestedAt = payout['requested_at'] as String?;
    final paidAt = payout['paid_at'] as String?;

    String statusLabel = 'In behandeling';
    Color statusColor = Colors.orange;

    if (status == 'paid') {
      statusLabel = 'Uitbetaald';
      statusColor = Colors.green;
    } else if (status == 'failed') {
      statusLabel = 'Mislukt';
      statusColor = Colors.red;
    }

    String dateLabel = 'Aangevraagd';
    String? dateValue = requestedAt;

    if (status == 'paid' && paidAt != null) {
      dateLabel = 'Uitbetaald';
      dateValue = paidAt;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: Icon(
                status == 'paid'
                    ? Icons.check_circle
                    : status == 'failed'
                        ? Icons.error
                        : Icons.schedule,
                color: statusColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: GymiesTextStyles.body1.copyWith(
                    color: GymiesColors.darkBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (dateValue != null)
                  Text(
                    '$dateLabel: ${_formatDate(dateValue)}',
                    style: GymiesTextStyles.body3.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '€${amount.toStringAsFixed(2)}',
            style: GymiesTextStyles.body1.copyWith(
              color: GymiesColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}
