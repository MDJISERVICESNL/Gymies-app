import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gymies_app/services/gymies_api.dart';
import '../l10n/generated/app_localizations.dart';

class AdminPayoutsScreen extends StatefulWidget {
  const AdminPayoutsScreen({super.key});

  @override
  State<AdminPayoutsScreen> createState() => _AdminPayoutsScreenState();
}

class _AdminPayoutsScreenState extends State<AdminPayoutsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Map<String, dynamic>? _stats;
  bool _statsLoading = true;
  bool _pendingLoading = true;
  bool _historyLoading = true;
  List<dynamic> _pendingPayouts = [];
  List<dynamic> _historyPayouts = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final api = context.read<GymiesApi>();
    try {
      final stats = await api.getAdminPayoutsStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _statsLoading = false;
      });
    } catch (e) {
      setState(() => _statsLoading = false);
      _showError('Fout bij laden stats: $e');
    }

    _loadPending();
    _loadHistory();
  }

  Future<void> _loadPending() async {
    final api = context.read<GymiesApi>();
    try {
      final payouts = await api.getAdminPayoutsPending(search: _searchQuery);
      if (!mounted) return;
      setState(() {
        _pendingPayouts = payouts;
        _pendingLoading = false;
      });
    } catch (e) {
      setState(() => _pendingLoading = false);
      _showError('Fout bij laden openstaande: $e');
    }
  }

  Future<void> _loadHistory() async {
    final api = context.read<GymiesApi>();
    try {
      final payouts = await api.getAdminPayoutsHistory();
      if (!mounted) return;
      setState(() {
        _historyPayouts = payouts;
        _historyLoading = false;
      });
    } catch (e) {
      setState(() => _historyLoading = false);
      _showError('Fout bij laden geschiedenis: $e');
    }
  }

  Future<void> _markPaidConfirm(String payoutId, String trainerName,
      String amount) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.of(context).betalingBevestigen),
        content: Text('Mark payout €$amount for $trainerName as paid?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(S.of(context).annuleer),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _markPaid(payoutId);
            },
            child: const Text(S.of(context).jaBetaald),
          ),
        ],
      ),
    );
  }

  Future<void> _markPaid(String payoutId) async {
    final api = context.read<GymiesApi>();
    try {
      await api.markPayoutPaid(payoutId);
      _loadPending();
      _loadData();
      _showSuccess('Betaling gemarkeerd als betaald');
    } catch (e) {
      _showError('Fout: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = query);
        _loadPending();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).trainerUitbetalingen),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildStatsSection(),
          _buildSearchBar(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPendingTab(),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    if (_statsLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      );
    }

    if (_stats == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(S.of(context).foutBijLadenStatistieken),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StatCard(
              title: 'Openstaand',
              value: '€${_stats!['pending_amount'] ?? '0,00'}',
              subtitle:
                  '${_stats!['pending_count'] ?? 0} verzoeken',
              color: Colors.orange,
            ),
            const SizedBox(width: 12),
            _StatCard(
              title: S.of(context).dezeWeek,
              value: '€${_stats!['paid_this_week'] ?? '0,00'}',
              subtitle: S.of(context).betaald,
              color: Colors.green,
            ),
            const SizedBox(width: 12),
            _StatCard(
              title: S.of(context).dezeMaand,
              value: '€${_stats!['paid_this_month'] ?? '0,00'}',
              subtitle: S.of(context).betaald,
              color: Colors.blue,
            ),
            const SizedBox(width: 12),
            _StatCard(
              title: S.of(context).vergoedingen,
              value: '€${_stats!['fees_earned'] ?? '0,00'}',
              subtitle: 'Verdiend',
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: S.of(context).zoekenOpTrainernaam,
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: 'Openstaand'),
        Tab(text: 'Geschiedenis'),
      ],
    );
  }

  Widget _buildPendingTab() {
    if (_pendingLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pendingPayouts.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty
              ? S.of(context).geenOpenstaandeUitbetalingen
              : S.of(context).geenResultatenGevonden,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPending,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingPayouts.length,
        itemBuilder: (ctx, idx) {
          final payout = _pendingPayouts[idx];
          return _PayoutCard(
            trainerName: payout[S.of(context).trainername] ?? 'Unknown',
            amount: payout['amount'] ?? '0,00',
            iban: payout['iban'] ?? 'N/A',
            frequency: payout['frequency'] ?? 'weekly',
            createdAt: payout['created_at'] ?? '',
            status: 'pending',
            onAction: () => _markPaidConfirm(
              payout['id'],
              payout[S.of(context).trainername] ?? S.of(context).trainer,
              payout['amount'] ?? '0,00',
            ),
            actionLabel: 'Markeer betaald',
            actionColor: Colors.green,
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_historyPayouts.isEmpty) {
      return const Center(child: Text(S.of(context).geenUitbetalingsgeschiedenis));
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _historyPayouts.length,
        itemBuilder: (ctx, idx) {
          final payout = _historyPayouts[idx];
          return _PayoutCard(
            trainerName: payout[S.of(context).trainername] ?? 'Unknown',
            amount: payout['amount'] ?? '0,00',
            iban: payout['iban'] ?? 'N/A',
            frequency: payout['frequency'] ?? 'weekly',
            createdAt: payout['paid_at'] ?? payout['created_at'] ?? '',
            status: payout['status'] ?? 'completed',
            onAction: null,
            actionLabel: '',
            actionColor: Colors.grey,
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutCard extends StatelessWidget {
  final String trainerName;
  final String amount;
  final String iban;
  final String frequency;
  final String createdAt;
  final String status;
  final VoidCallback? onAction;
  final String actionLabel;
  final Color actionColor;

  const _PayoutCard({
    required this.trainerName,
    required this.amount,
    required this.iban,
    required this.frequency,
    required this.createdAt,
    required this.status,
    this.onAction,
    required this.actionLabel,
    required this.actionColor,
  });

  Color _getStatusColor() {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'paid':
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel() {
    switch (status) {
      case 'pending':
        return 'Openstaand';
      case 'paid':
      case 'completed':
        return S.of(context).betaald;
      case 'cancelled':
        return S.of(context).geannuleerd;
      default:
        return status;
    }
  }

  String _getFrequencyLabel() {
    switch (frequency) {
      case 'weekly':
        return 'Wekelijks';
      case 'monthly':
        return 'Maandelijks';
      case 'daily':
        return 'Dagelijks';
      default:
        return frequency;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trainerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'IBAN: $iban',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                Text(
                  '€$amount',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Chip(
                  label: Text(_getFrequencyLabel()),
                  backgroundColor: Colors.blue.withOpacity(0.1),
                  labelStyle: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(_getStatusLabel()),
                  backgroundColor: _getStatusColor().withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: _getStatusColor(),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  createdAt,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                if (onAction != null)
                  ElevatedButton(
                    onPressed: onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: actionColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      actionLabel,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
