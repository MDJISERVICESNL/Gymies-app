import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/gymies_theme.dart';

/// Prefix dat de server gebruikt voor interactieve kaarten in chat-berichten.
const _cardPrefix = '__GYMIES_CARD__:';

/// Widget die een verplaatsingsverzoek-kaart toont in de chat.
///
/// Herkent berichten die beginnen met `__GYMIES_CARD__:` en type `reschedule`.
/// Toont de huidige en voorgestelde datum/tijd + accept/reject knoppen.
class RescheduleCardWidget extends StatelessWidget {
  const RescheduleCardWidget._({
    required this.bookingId,
    required this.state,
    required this.scheduledAt,
    required this.proposedScheduledAt,
    required this.durationMinutes,
    required this.busy,
    required this.isMine,
    this.onAccept,
    this.onReject,
    this.onCounterPropose,
  });

  final String bookingId;
  final String state; // 'pending', 'accepted', 'rejected'
  final DateTime? scheduledAt;
  final DateTime? proposedScheduledAt;
  final int durationMinutes;
  final bool busy;
  final bool isMine; // true = huidige gebruiker heeft het verzoek gestuurd
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCounterPropose;

  // ── Factory: parse een chatbericht ──────────────────────────────

  /// Parse een chatbericht naar een [RescheduleCardWidget], of `null` als het
  /// geen GYMIES_CARD reschedule bericht is.
  static RescheduleCardWidget? fromMessage(
    Map<String, dynamic> message, {
    bool busy = false,
    bool isMine = false,
    VoidCallback? onAccept,
    VoidCallback? onReject,
    VoidCallback? onCounterPropose,
  }) {
    final json = _parseCardJson(message);
    if (json == null) return null;
    if ((json['type'] ?? '') != 'reschedule') return null;

    return RescheduleCardWidget._(
      bookingId: (json['booking_id'] ?? '').toString(),
      state: (json['state'] ?? 'pending').toString(),
      scheduledAt: DateTime.tryParse((json['scheduled_at'] ?? '').toString()),
      proposedScheduledAt:
          DateTime.tryParse((json['proposed_scheduled_at'] ?? '').toString()),
      durationMinutes:
          int.tryParse((json['duration_minutes'] ?? '60').toString()) ?? 60,
      busy: busy,
      isMine: isMine,
      onAccept: onAccept,
      onReject: onReject,
      onCounterPropose: onCounterPropose,
    );
  }

  /// Controleert of een (reeds geparsede) JSON-map een reschedule-kaart is.
  /// Wordt gebruikt door trainer_chat_screen waar de body al is geparsed.
  static bool isRescheduleCard(Map<String, dynamic> json) {
    // Controleer of het een GYMIES_CARD bericht is (raw body) of al geparsed JSON met type
    final body = (json['body'] ?? json['message'] ?? json['text'] ?? '').toString();
    if (body.startsWith(_cardPrefix)) {
      final parsed = _parseCardJson(json);
      return parsed != null && (parsed['type'] ?? '') == 'reschedule';
    }
    // Al geparsed JSON (trainer_chat_screen parseert zelf)
    return (json['type'] ?? '') == 'reschedule';
  }

  /// Haal booking_id uit een chatbericht (voor busy-tracking).
  static String getBookingIdFromMessage(Map<String, dynamic> message) {
    final json = _parseCardJson(message);
    if (json == null) return '';
    return (json['booking_id'] ?? '').toString();
  }

  static Map<String, dynamic>? _parseCardJson(Map<String, dynamic> message) {
    final body =
        (message['body'] ?? message['message'] ?? message['text'] ?? '')
            .toString();

    // Variant 1: raw chatbericht met prefix
    if (body.startsWith(_cardPrefix)) {
      final raw = body.substring(_cardPrefix.length);
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (e) {
        // Fail-open: Card parsing failed, return null
        if (kDebugMode) debugPrint('[RescheduleCard] Parse card data failed: $e');
      }
      return null;
    }

    // Variant 2: al geparsede JSON (trainer_chat_screen parseert zelf)
    if (message.containsKey('type') && message['type'] == 'reschedule') {
      return message;
    }

    return null;
  }

  // ── UI ──────────────────────────────────────────────────────────

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '–';
    try {
      return DateFormat('EEEE d MMMM', 'nl_NL').format(dt);
    } catch (_) {
      return DateFormat('EEEE d MMMM').format(dt);
    }
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  bool get _isPending => state == 'pending';
  bool get _isAccepted => state == 'accepted';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.85,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isPending
              ? GymiesColors.primary.withOpacity(0.4)
              : _isAccepted
                  ? Colors.green.withOpacity(0.4)
                  : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _isPending
                  ? GymiesColors.primary.withOpacity(0.08)
                  : _isAccepted
                      ? Colors.green.withOpacity(0.08)
                      : Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  _isPending
                      ? Icons.swap_horiz_rounded
                      : _isAccepted
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                  size: 20,
                  color: _isPending
                      ? GymiesColors.primary
                      : _isAccepted
                          ? Colors.green
                          : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _isPending
                      ? S.of(context).verplaatsingsverzoek
                      : _isAccepted
                          ? S.of(context).sessieVerplaatst
                          : S.of(context).verzoekAfgewezen,
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
          ),

          // ── Datum info ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (scheduledAt != null) ...[
                  _DateRow(
                    label: 'Huidig',
                    date: _fmtDate(scheduledAt),
                    time: _fmtTime(scheduledAt),
                    isOld: true,
                  ),
                  const SizedBox(height: 8),
                ],
                _DateRow(
                  label: 'Nieuw',
                  date: _fmtDate(proposedScheduledAt),
                  time: _fmtTime(proposedScheduledAt),
                  isOld: false,
                ),
                const SizedBox(height: 4),
                Text(
                  '$durationMinutes minuten',
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),

          // ── Status badge (als niet pending) ──
          if (!_isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isAccepted
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isAccepted
                          ? Icons.check_rounded
                          : Icons.close_rounded,
                      size: 16,
                      color: _isAccepted ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isAccepted ? 'Geaccepteerd' : 'Afgewezen',
                      style: GoogleFonts.sora(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isAccepted
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Acties (alleen bij pending) ──
          if (_isPending && isMine)
            // Afzender ziet "wacht op reactie"
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(
                    S.of(context).waitingForTrainerReply,
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          if (_isPending && !isMine)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: busy
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: GymiesColors.primary,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _CardButton(
                            label: 'Afwijzen',
                            icon: Icons.close_rounded,
                            color: Colors.red,
                            onTap: onReject,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CardButton(
                            label: 'Accepteren',
                            icon: Icons.check_rounded,
                            color: Colors.green,
                            filled: true,
                            onTap: onAccept,
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.date,
    required this.time,
    required this.isOld,
  });

  final String label;
  final String date;
  final String time;
  final bool isOld;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 50,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isOld
                ? Colors.grey.shade100
                : GymiesColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isOld ? Colors.grey.shade500 : GymiesColors.darkBlue,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            date,
            style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: isOld ? FontWeight.w400 : FontWeight.w600,
              color: isOld ? Colors.grey.shade500 : GymiesColors.darkBlue,
              decoration: isOld ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        Text(
          time,
          style: GoogleFonts.sora(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isOld ? Colors.grey.shade400 : GymiesColors.darkBlue,
          ),
        ),
      ],
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.icon,
    required this.color,
    this.filled = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border:
                filled ? null : Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: filled ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
