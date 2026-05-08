import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/gymies_api.dart';
import '../../theme/gymies_theme.dart';
import '../../utils/haptics.dart';

/// Bottom sheet die verschijnt als een klant probeert te boeken in een niet-open regio.
///
/// Drie varianten op basis van state:
/// - Variant 1 (waitlist): progress bar + "Houd me op de hoogte"
/// - Variant 2 (invite_only): invite code prominent + notify optie
/// - Variant 3 (already on list): bevestiging + invite code veld
///
/// [onCodeActivated] wordt aangeroepen als de klant een geldige invite code invult
/// en direct mag boeken. De parent screen kan dan de boekingsflow hervatten.
class LaunchGateBottomSheet extends StatefulWidget {
  final String regionSlug;
  final String regionName;
  final String regionStatus; // 'waitlist' | 'invite_only'
  final bool alreadyOnNotifyList;
  final Map<String, dynamic> progress; // progress_level, progress_pct, message
  final String trainerUserId;
  final VoidCallback? onCodeActivated;

  const LaunchGateBottomSheet({
    super.key,
    required this.regionSlug,
    required this.regionName,
    required this.regionStatus,
    required this.alreadyOnNotifyList,
    required this.progress,
    required this.trainerUserId,
    this.onCodeActivated,
  });

  /// Toont de bottom sheet. Returned true als de code is geactiveerd en de klant mag boeken.
  static Future<bool> show(
    BuildContext context, {
    required Map<String, dynamic> gateData,
    required String trainerUserId,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LaunchGateBottomSheet(
        regionSlug: (gateData['region_slug'] ?? '') as String,
        regionName: (gateData['region_name'] ?? 'Onbekend') as String,
        regionStatus: (gateData['region_status'] ?? 'waitlist') as String,
        alreadyOnNotifyList: gateData['already_on_notify_list'] == true,
        progress: (gateData['progress'] as Map<String, dynamic>?) ?? {},
        trainerUserId: trainerUserId,
      ),
    );
    return result == true;
  }

  @override
  State<LaunchGateBottomSheet> createState() => _LaunchGateBottomSheetState();
}

class _LaunchGateBottomSheetState extends State<LaunchGateBottomSheet> {
  final _codeCtrl = TextEditingController();
  bool _notifying = false;
  bool _activatingCode = false;
  bool _justNotified = false;
  String? _codeError;
  String? _notifyMessage;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── "Houd me op de hoogte" ──
  Future<void> _notifyMe() async {
    if (_notifying) return;
    setState(() { _notifying = true; _notifyMessage = null; });
    try {
      final api = context.read<GymiesApi>();
      final res = await api.launchGateNotifyMe(
        widget.regionSlug,
        trainerUserId: widget.trainerUserId,
      );
      if (!mounted) return;
      Haptics.success();
      setState(() {
        _justNotified = true;
        _notifyMessage = (res['message'] as String?) ?? 'We laten het je weten!';
        _notifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notifyMessage = 'Er ging iets mis. Probeer het opnieuw.';
        _notifying = false;
      });
    }
  }

  // ── Invite code activeren ──
  Future<void> _activateCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _codeError = 'Voer een invite code in');
      return;
    }
    setState(() { _activatingCode = true; _codeError = null; });
    try {
      final api = context.read<GymiesApi>();
      final res = await api.launchGateActivateCode(
        code,
        regionSlug: widget.regionSlug,
      );
      if (!mounted) return;
      if (res['ok'] == true) {
        Haptics.success();
        Navigator.of(context).pop(true); // Return true → parent herstart booking
        if (widget.onCodeActivated != null) widget.onCodeActivated!();
      } else {
        setState(() {
          _codeError = (res['message'] as String?) ?? 'Ongeldige code';
          _activatingCode = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _codeError = 'Fout bij activatie. Probeer het opnieuw.';
        _activatingCode = false;
      });
    }
  }

  bool get _showNotifyButton =>
      !widget.alreadyOnNotifyList && !_justNotified;

  @override
  Widget build(BuildContext context) {
    final progressPct = ((widget.progress['progress_pct'] as num?)?.toDouble() ?? 0).clamp(0.0, 100.0);
    final progressMessage = (widget.progress['message'] as String?) ?? 'We werken aan jouw regio';
    final progressLevel = (widget.progress['progress_level'] as String?) ?? 'early';
    final isInviteOnly = widget.regionStatus == 'invite_only';

    Color progressColor;
    switch (progressLevel) {
      case 'nearly_ready':
        progressColor = Colors.green;
        break;
      case 'almost':
        progressColor = Colors.lightGreen;
        break;
      case 'growing':
        progressColor = GymiesColors.primary;
        break;
      default:
        progressColor = Colors.blue;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Region header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: progressColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isInviteOnly ? Icons.lock_open_rounded : Icons.hourglass_top_rounded,
                    color: progressColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.regionName,
                        style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        progressMessage,
                        style: GoogleFonts.sora(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progressPct / 100,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 20),

            // Uitleg tekst
            Text(
              isInviteOnly
                  ? '${widget.regionName} is bijna open! Met een invite code van een trainer kun je nu al boeken.'
                  : 'We bouwen ${widget.regionName} op. Zodra er genoeg trainers klaar zijn, kun je boeken.',
              style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue, height: 1.5),
            ),
            const SizedBox(height: 20),

            // ── Invite code sectie (prominent bij invite_only) ──
            if (isInviteOnly) ...[
              _buildInviteCodeSection(),
              const SizedBox(height: 16),
              if (_showNotifyButton) ...[
                Center(
                  child: TextButton(
                    onPressed: _notifying ? null : _notifyMe,
                    child: Text(
                      'Ik heb geen code — houd me op de hoogte',
                      style: GoogleFonts.sora(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ),
                ),
              ],
            ] else ...[
              // ── Waitlist variant: notify knop eerst, code eronder ──
              if (_showNotifyButton)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _notifying ? null : _notifyMe,
                    icon: _notifying
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.notifications_active_outlined, size: 18),
                    label: Text(
                      'Houd me op de hoogte',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _buildInviteCodeSection(),
            ],

            // Notify success/already on list message
            if (_justNotified || widget.alreadyOnNotifyList) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _notifyMessage ?? 'Je staat op de lijst! We sturen je een bericht zodra ${widget.regionName} opengaat.',
                        style: GoogleFonts.sora(fontSize: 13, color: Colors.green[800]),
                      ),
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

  Widget _buildInviteCodeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Heb je een invite code?',
            style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
          ),
          const SizedBox(height: 4),
          Text(
            'Vul de code in en boek direct.',
            style: GoogleFonts.sora(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'GYM-XXXXXX',
                    hintStyle: GoogleFonts.sora(color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.vpn_key_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: GymiesColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    isDense: true,
                  ),
                  style: GoogleFonts.sora(fontSize: 15, letterSpacing: 1.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _activatingCode ? null : _activateCode,
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _activatingCode
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Activeer', style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
          if (_codeError != null) ...[
            const SizedBox(height: 8),
            Text(_codeError!, style: GoogleFonts.sora(fontSize: 12, color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
