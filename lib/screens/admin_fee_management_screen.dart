import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/trainer_state_views.dart';

/// Admin scherm voor het beheren van platform service fees.
/// Bereikbaar vanuit Vault-Console.
class AdminFeeManagementScreen extends StatefulWidget {
  const AdminFeeManagementScreen({super.key});

  @override
  State<AdminFeeManagementScreen> createState() =>
      _AdminFeeManagementScreenState();
}

class _AdminFeeManagementScreenState extends State<AdminFeeManagementScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _defaults = [];
  List<Map<String, dynamic>> _overrides = [];
  Map<String, dynamic> _envFallback = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final data = await api.getAdminFees();
      if (!mounted) return;
      setState(() {
        _defaults = List<Map<String, dynamic>>.from(data['defaults'] ?? []);
        _overrides = List<Map<String, dynamic>>.from(data['overrides'] ?? []);
        _envFallback = Map<String, dynamic>.from(data['env_fallback'] ?? {});
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
        _error = 'Kon fees niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _deleteFee(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Verwijderen', style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
        content: Text('Weet je zeker dat je deze fee setting wilt verwijderen?',
            style: GoogleFonts.sora()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuleren', style: GoogleFonts.sora()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Verwijderen',
                style: GoogleFonts.sora(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<GymiesApi>().deleteAdminFee(id);
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    }
  }

  Future<void> _showCreateDialog({bool isOverride = false}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeeFormSheet(isOverride: isOverride),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<GymiesApi>().createAdminFee(
            trainerUserId: result['trainer_user_id'] as int?,
            planSlug: result['plan_slug'] as String?,
            feeType: result['fee_type'] as String,
            feeValue: result['fee_value'] as int,
            clientPays: result['client_pays'] as bool,
          );
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> fee) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeeFormSheet(
        isOverride: fee['trainer_user_id'] != null,
        existing: fee,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<GymiesApi>().updateAdminFee(
            fee['id'] as int,
            feeType: result['fee_type'] as String?,
            feeValue: result['fee_value'] as int?,
            clientPays: result['client_pays'] as bool?,
          );
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.sora()),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          // ── Header ──
          Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context).pop();
                      },
                      child: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Fee-beheer',
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Body ──
          Expanded(
            child: GymiesListBody(
              loading: _loading,
              error: _error,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Env fallback info
                  if (_envFallback.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: GymiesColors.darkBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Fallback: ${_envFallback['fee_cents'] ?? 49}ct (env)',
                              style: GoogleFonts.sora(
                                fontSize: 13,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Platform Defaults ──
                  _SectionHeader(
                    title: 'Platform defaults',
                    subtitle: 'Per abonnements-plan',
                    onAdd: () => _showCreateDialog(isOverride: false),
                  ),
                  const SizedBox(height: 8),
                  if (_defaults.isEmpty)
                    _EmptyCard(label: 'Geen plan defaults ingesteld')
                  else
                    ..._defaults.map((f) => _FeeCard(
                          fee: f,
                          onEdit: () => _showEditDialog(f),
                          onDelete: () => _deleteFee(f['id'] as int),
                        )),

                  const SizedBox(height: 24),

                  // ── Trainer Overrides ──
                  _SectionHeader(
                    title: 'Trainer overrides',
                    subtitle: 'Per trainer een custom fee',
                    onAdd: () => _showCreateDialog(isOverride: true),
                  ),
                  const SizedBox(height: 8),
                  if (_overrides.isEmpty)
                    _EmptyCard(label: 'Geen trainer overrides')
                  else
                    ..._overrides.map((f) => _FeeCard(
                          fee: f,
                          onEdit: () => _showEditDialog(f),
                          onDelete: () => _deleteFee(f['id'] as int),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sub widgets ──────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.onAdd,
  });
  final String title;
  final String subtitle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: GoogleFonts.sora(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.sora(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            Haptics.selection();
            onAdd();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: GymiesColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, size: 16, color: GymiesColors.darkBlue),
                const SizedBox(width: 4),
                Text(
                  'Toevoegen',
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({
    required this.fee,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> fee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isOverride = fee['trainer_user_id'] != null;
    final name = isOverride
        ? (fee['trainer_name'] ?? 'Trainer #${fee['trainer_user_id']}')
        : _planLabel(fee['plan_slug'] as String?);
    final feeDisplay = fee['fee_display'] ?? '?';
    final clientPays = fee['client_pays'] == true;
    final isActive = fee['is_active'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: isActive
              ? null
              : Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: GoogleFonts.sora(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? GymiesColors.darkBlue
                                  : Colors.grey.shade400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Inactief',
                              style: GoogleFonts.sora(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOverride
                          ? '${_planLabel(fee['plan_slug'] as String?)} plan — ${clientPays ? 'client' : 'trainer'} betaalt'
                          : '${clientPays ? 'Client' : 'Trainer'} betaalt',
                      style: GoogleFonts.sora(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOverride
                      ? GymiesColors.darkBlue.withValues(alpha: 0.1)
                      : GymiesColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  feeDisplay.toString(),
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    size: 20, color: Colors.grey.shade400),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Bewerken', style: GoogleFonts.sora(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Verwijderen',
                        style: GoogleFonts.sora(fontSize: 14, color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _planLabel(String? slug) {
    switch (slug) {
      case 'starter':
        return 'Starter';
      case 'pro':
        return 'Pro';
      case 'studio':
        return 'Studio';
      default:
        return 'Alle plans';
    }
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade400),
        ),
      ),
    );
  }
}

// ─── Create / Edit bottom sheet ──────────────────────────

class _FeeFormSheet extends StatefulWidget {
  const _FeeFormSheet({
    required this.isOverride,
    this.existing,
  });
  final bool isOverride;
  final Map<String, dynamic>? existing;

  @override
  State<_FeeFormSheet> createState() => _FeeFormSheetState();
}

class _FeeFormSheetState extends State<_FeeFormSheet> {
  late String _feeType;
  late int _feeValue;
  late bool _clientPays;
  String? _planSlug;
  final _trainerIdController = TextEditingController();
  final _feeValueController = TextEditingController();

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _feeType = (e?['fee_type'] ?? 'fixed') as String;
    _feeValue = (e?['fee_value'] ?? 49) as int;
    _clientPays = (e?['client_pays'] ?? true) as bool;
    _planSlug = e?['plan_slug'] as String?;
    if (e?['trainer_user_id'] != null) {
      _trainerIdController.text = e!['trainer_user_id'].toString();
    }
    _feeValueController.text = _feeValue.toString();
  }

  @override
  void dispose() {
    _trainerIdController.dispose();
    _feeValueController.dispose();
    super.dispose();
  }

  void _submit() {
    final val = int.tryParse(_feeValueController.text.trim()) ?? 0;
    if (val <= 0) return;

    final result = <String, dynamic>{
      'fee_type': _feeType,
      'fee_value': val,
      'client_pays': _clientPays,
    };
    if (!_isEdit) {
      if (widget.isOverride) {
        final tid = int.tryParse(_trainerIdController.text.trim());
        if (tid == null || tid <= 0) return;
        result['trainer_user_id'] = tid;
      }
      result['plan_slug'] = _planSlug;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: GymiesColors.darkBlue,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isEdit
                            ? 'Fee bewerken'
                            : widget.isOverride
                                ? 'Trainer override'
                                : 'Plan default',
                        style: GoogleFonts.sora(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Form ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Trainer ID (alleen bij override + nieuw)
                  if (widget.isOverride && !_isEdit) ...[
                    Text('Trainer user ID',
                        style: GoogleFonts.sora(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _trainerIdController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.sora(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Bijv. 42',
                        hintStyle: GoogleFonts.sora(
                            fontSize: 14, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Plan selectie (alleen bij default + nieuw)
                  if (!widget.isOverride && !_isEdit) ...[
                    Text('Plan',
                        style: GoogleFonts.sora(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      value: _planSlug,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: null, child: Text('Alle plans')),
                        DropdownMenuItem(
                            value: 'starter', child: Text('Starter')),
                        DropdownMenuItem(value: 'pro', child: Text('Pro')),
                        DropdownMenuItem(
                            value: 'studio', child: Text('Studio')),
                      ],
                      onChanged: (v) => setState(() => _planSlug = v),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Fee type toggle
                  Text('Fee type',
                      style: GoogleFonts.sora(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _ToggleChip(
                        label: 'Vast (centen)',
                        isSelected: _feeType == 'fixed',
                        onTap: () => setState(() => _feeType = 'fixed'),
                      ),
                      const SizedBox(width: 8),
                      _ToggleChip(
                        label: 'Percentage',
                        isSelected: _feeType == 'percent',
                        onTap: () => setState(() => _feeType = 'percent'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Fee waarde
                  Text(
                    _feeType == 'fixed'
                        ? 'Bedrag (centen)'
                        : 'Basispunten (250 = 2,5%)',
                    style: GoogleFonts.sora(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _feeValueController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.sora(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _feeType == 'fixed' ? 'Bijv. 49' : 'Bijv. 250',
                      hintStyle: GoogleFonts.sora(
                          fontSize: 14, color: Colors.grey.shade400),
                      suffixText:
                          _feeType == 'fixed' ? 'ct' : 'bp',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Wie betaalt
                  Text('Wie betaalt de fee?',
                      style: GoogleFonts.sora(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _ToggleChip(
                        label: 'Client betaalt',
                        isSelected: _clientPays,
                        onTap: () => setState(() => _clientPays = true),
                      ),
                      const SizedBox(width: 8),
                      _ToggleChip(
                        label: 'Trainer betaalt',
                        isSelected: !_clientPays,
                        onTap: () => setState(() => _clientPays = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Submit
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GymiesColors.primary,
                        foregroundColor: GymiesColors.darkBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(_isEdit ? 'Opslaan' : 'Aanmaken'),
                    ),
                  ),
                  SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? GymiesColors.darkBlue
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
