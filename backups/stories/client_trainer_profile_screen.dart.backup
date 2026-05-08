import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/booking.dart';
import '../models/trainer.dart';
import '../services/api_client.dart';
import '../services/calendar_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../config/app_config.dart';
import '../config/timing_constants.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import '../utils/safe_url_launcher.dart';
import '../utils/trainer_badges.dart';
import 'client_messages_screen.dart';
import 'client_trainer_reviews_screen.dart';
import 'widgets/gymies_dialog.dart';

class _AvailabilityDayView {
  const _AvailabilityDayView({required this.date, required this.windows});

  final DateTime date;
  final List<String> windows;
}

/// Robuuste avatar widget die nooit infiniet laadt.
/// Gebruikt Image.network i.p.v. CachedNetworkImage om stale 404-cache
/// te vermijden. Toont initials als fallback bij laden of fout.
class _GymiesAvatar extends StatelessWidget {
  const _GymiesAvatar({
    required this.url,
    required this.fallbackName,
    required this.size,
    this.fontSize,
    this.bgColor = const Color(0xFF2A4A6F),
    this.textColor = Colors.white,
  });

  final String? url;
  final String fallbackName;
  final double size;
  final double? fontSize;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final initials = fallbackName.isNotEmpty ? fallbackName[0].toUpperCase() : '?';
    final fs = fontSize ?? (size * 0.38).clamp(10.0, 32.0);
    final initialsWidget = Container(
      width: size, height: size,
      color: bgColor,
      child: Center(
        child: Text(initials, style: GoogleFonts.sora(color: textColor, fontWeight: FontWeight.w700, fontSize: fs)),
      ),
    );
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return initialsWidget;
    return Image.network(
      trimmed,
      width: size, height: size,
      fit: BoxFit.cover,
      headers: const {'User-Agent': 'Gymies/1.0'},
      loadingBuilder: (_, child, progress) => progress == null ? child : initialsWidget,
      errorBuilder: (_, __, ___) => initialsWidget,
    );
  }
}

DateTime _startOfWeek(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

int _weekdayFromSlot(Map<String, dynamic> slot) {
  final raw =
      (slot['weekday'] ??
              slot['day_of_week'] ??
              slot['dayOfWeek'] ??
              slot['iso_weekday'] ??
              slot['day'] ??
              slot['date'] ??
              slot['scheduled_at'] ??
              slot['scheduledAt'])
          ?.toString()
          .trim()
          .toLowerCase();
  if (raw == null || raw.isEmpty) return 0;
  final numeric = int.tryParse(raw);
  if (numeric != null && numeric >= 1 && numeric <= 7) return numeric;
  final parsedDate = DateTime.tryParse(raw);
  if (parsedDate != null) return parsedDate.weekday;
  const map = <String, int>{
    'maandag': 1,
    'monday': 1,
    'dinsdag': 2,
    'tuesday': 2,
    'woensdag': 3,
    'wednesday': 3,
    'donderdag': 4,
    'thursday': 4,
    'vrijdag': 5,
    'friday': 5,
    'zaterdag': 6,
    'saturday': 6,
    'zondag': 7,
    'sunday': 7,
  };
  return map[raw] ?? 0;
}

/// Strip seconden uit tijdstring: "08:00:00" → "08:00"
String _fmtTime(String raw) {
  final parts = raw.split(':');
  if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
  return raw;
}

List<_AvailabilityDayView> _availabilityForWeek(
  List<Map<String, dynamic>> availability, {
  required int weekOffset,
}) {
  final base = _startOfWeek(DateTime.now()).add(Duration(days: weekOffset * 7));
  final days = List<DateTime>.generate(7, (i) => base.add(Duration(days: i)));
  return days.map((date) {
    final windows =
        availability
            .where((slot) => _weekdayFromSlot(slot) == date.weekday)
            .map((slot) {
              final start = (slot['start_time'] ?? slot['startTime'] ?? '')
                  .toString();
              final end = (slot['end_time'] ?? slot['endTime'] ?? '')
                  .toString();
              if (start.isEmpty || end.isEmpty) return '';
              return '${_fmtTime(start)} - ${_fmtTime(end)}';
            })
            .where((window) => window.isNotEmpty)
            .toList()
          ..sort();
    return _AvailabilityDayView(date: date, windows: windows);
  }).toList();
}

class ClientTrainerProfileScreen extends StatefulWidget {
  ClientTrainerProfileScreen({
    super.key,
    this.trainer,
    this.trainerSlug,
    this.trainerId,
    this.buddyBookingId,
    this.focusBookingForm = false,
    this.showFullProfileOnly = false,
    this.isFromMyTrainers = false,
    this.onRemoveFromMyTrainers,
  }) : assert(
             trainer != null ||
                 (trainerSlug != null && trainerSlug.trim().isNotEmpty) ||
                 (trainerId != null && trainerId.trim().isNotEmpty),
             'trainer, trainerSlug of trainerId vereist');

  final Trainer? trainer;
  final String? trainerSlug;
  final String? trainerId;
  final String? buddyBookingId;
  final bool focusBookingForm;
  final bool showFullProfileOnly;
  final bool isFromMyTrainers;
  final VoidCallback? onRemoveFromMyTrainers;

  @override
  State<ClientTrainerProfileScreen> createState() =>
      _ClientTrainerProfileScreenState();
}

class _ClientTrainerProfileScreenState
    extends State<ClientTrainerProfileScreen> {
  bool _loading = true;
  bool _booking = false;
  bool _openingChat = false;
  String? _error;

  Trainer? _trainer;
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _availability = [];
  List<Map<String, dynamic>> _mediaGallery = [];
  List<Map<String, dynamic>> _storyMedia = [];
  List<Map<String, dynamic>> _reviews = [];

  String? _selectedPackageId;
  bool _usePackage = false; // false = losse sessie, true = pakket
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _selectedSlot;
  Map<String, dynamic>? _activeSlotHold;
  DateTime? _slotHoldUntil;
  Timer? _slotHoldTicker;
  final _noteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _bookingCardKey = GlobalKey();

  // Cached API reference — set in didChangeDependencies to avoid
  // context.read after async gaps (prevents _dependents.isEmpty).
  late GymiesApi _api;
  bool _didFirstLoad = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusBookingForm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBookingForm();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<GymiesApi>();
    if (!_didFirstLoad) {
      _didFirstLoad = true;
      _load();
    }
  }

  @override
  void dispose() {
    _slotHoldTicker?.cancel();
    _noteController.dispose();
    _scrollController.dispose();
    // Release held slot als gebruiker wegnavigeert zonder te boeken
    final holdId = (_activeSlotHold?['id'] ?? _activeSlotHold?['hold_id'])?.toString();
    if (holdId != null && holdId.isNotEmpty) {
      _api.releaseSlotHold(holdId);
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    Trainer? baseTrainer = widget.trainer;
    try {
      final api = _api;
      if (baseTrainer == null && widget.trainerId != null) {
        baseTrainer = await api.getTrainerById(widget.trainerId!);
      }
      if (baseTrainer == null && widget.trainerSlug != null) {
        baseTrainer = await api.getTrainerBySlug(widget.trainerSlug!);
        if (baseTrainer == null || !mounted) {
          if (mounted) {
            setState(() {
              _error = 'Trainer niet gevonden';
              _loading = false;
            });
          }
          return;
        }
      }
      if (baseTrainer == null) {
        setState(() => _loading = false);
        return;
      }
      // ── Detail, packages, availability, media, reviews parallel laden ──
      // Elke call mag onafhankelijk falen zodat het profiel altijd toont.
      final results = await Future.wait([
        // 0: detail
        api.getTrainerById(baseTrainer.userId).catchError((_) => null),
        // 1: packages
        api.getTrainerPublicPackages(baseTrainer.userId)
            .catchError((_) => <Map<String, dynamic>>[]),
        // 2: availability
        api.getTrainerPublicAvailability(baseTrainer.userId)
            .catchError((_) => <Map<String, dynamic>>[]),
        // 3: media
        api.getTrainerPublicMedia(baseTrainer.userId)
            .catchError((_) => <String, dynamic>{}),
        // 4: reviews
        api.getTrainerReviews(baseTrainer.userId)
            .catchError((_) => <String, dynamic>{}),
      ]);

      final detail = results[0] as Trainer?;
      final packages = results[1] as List<Map<String, dynamic>>;
      final availability = results[2] as List<Map<String, dynamic>>;
      final mediaRes = results[3] as Map<String, dynamic>;
      final revRes = results[4] as Map<String, dynamic>;

      // Parse media
      List<Map<String, dynamic>> mediaGallery = [];
      List<Map<String, dynamic>> storyMedia = [];
      final rawGallery = mediaRes['media_gallery'] ?? mediaRes['mediaGallery'] ?? mediaRes['gallery'];
      final rawStory = mediaRes['story_media'] ?? mediaRes['storyMedia'] ?? mediaRes['story'] ?? mediaRes['stories'];
      if (rawGallery is List) {
        mediaGallery = rawGallery.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
      }
      if (rawStory is List) {
        storyMedia = rawStory.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
      }
      final rawItems = mediaRes['data'] ?? mediaRes['items'];
      if (rawItems is List && mediaGallery.isEmpty && storyMedia.isEmpty) {
        for (final e in rawItems) {
          final m = e is Map<String, dynamic> ? e : <String, dynamic>{};
          final usage = (m['usage'] ?? m['usage_type'] ?? 'gallery').toString().toLowerCase();
          if (usage == 'story') {
            storyMedia.add(m);
          } else {
            mediaGallery.add(m);
          }
        }
      }

      // Parse reviews
      List<Map<String, dynamic>> reviews = [];
      final rawReviews = revRes['data'];
      if (rawReviews is List) {
        reviews = rawReviews.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
      }

      if (!mounted) return;
      setState(() {
        _trainer = detail ?? baseTrainer;
        _packages = packages;
        _availability = availability;
        _mediaGallery = mediaGallery;
        _storyMedia = storyMedia;
        _reviews = reviews;
        _usePackage = _packages.isNotEmpty;
        _selectedPackageId = _usePackage
            ? mapStr(_packages.first, ['id', 'package_id', 'packageId'])
            : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      // Alleen als de basis-trainer niet geladen kon worden
      if (!mounted) return;
      setState(() {
        _trainer = baseTrainer;
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _trainer = baseTrainer;
        _error = 'Kon trainerprofiel niet laden.';
        _loading = false;
      });
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int? _priceCents(Map<String, dynamic> map) {
    // Probeer eerst _cents velden — die zijn al in centen.
    for (final key in ['price_cents', 'amount_cents']) {
      final v = map[key];
      if (v != null) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        final parsed = int.tryParse(v.toString());
        if (parsed != null) return parsed;
      }
    }
    // Fallback: price/amount in euro's — vermenigvuldig met 100.
    for (final key in ['price', 'amount']) {
      final v = map[key];
      if (v != null) {
        if (v is int) return v * 100;
        if (v is num) return (v.toDouble() * 100).round();
        final parsed = double.tryParse(v.toString());
        if (parsed != null) return (parsed * 100).round();
      }
    }
    return null;
  }

  String _formatPrice(int? cents) {
    if (cents == null) return 'Prijs op aanvraag';
    return '€${(cents / 100).toStringAsFixed(2)}';
  }

  Map<String, dynamic>? _selectedPackageMap() {
    final id = _selectedPackageId;
    if (id == null || id.isEmpty) return null;
    for (final p in _packages) {
      final packageId = mapStr(p, ['id', 'package_id', 'packageId']);
      if (packageId == id) return p;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(TimingConstants.twoYearRange),
    );
    if (date == null) return;
    if (!mounted) return;
    setState(() {
      _selectedDate = date;
      _selectedSlot = null;
    });
  }

  String _slotStart(Map<String, dynamic> slot) {
    return _formatTime((slot['start_time'] ?? slot['startTime'] ?? '').toString().trim());
  }

  String _slotEnd(Map<String, dynamic> slot) {
    return _formatTime((slot['end_time'] ?? slot['endTime'] ?? '').toString().trim());
  }

  /// Strip seconden: "08:00:00" → "08:00"
  String _formatTime(String raw) {
    if (raw.isEmpty) return raw;
    final parts = raw.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return raw;
  }

  (int, int) _parseHM(String raw) {
    final parts = raw.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return (h, m);
  }

  String? _slotId(Map<String, dynamic> slot) {
    final raw = (slot['id'] ?? slot['slot_id'] ?? slot['slotId'])
        ?.toString()
        .trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  DateTime _slotDateTime(Map<String, dynamic> slot, DateTime selectedDate) {
    final start = _slotStart(slot);
    final (hh, mm) = _parseHM(start);
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      hh,
      mm,
    );
  }

  /// Splitst brede beschikbaarheidsvensters (bijv. 08:00-18:00) in
  /// blokken van 1 uur. Retourneert synthetische slot-maps.
  List<Map<String, dynamic>> _slotsForSelectedDate() {
    final selectedDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final rawSlots = _availability.where((slot) {
      final exactDate = (slot['date'] ?? slot['slot_date'] ?? '')
          .toString()
          .trim();
      if (exactDate.isNotEmpty) {
        final parsed = DateTime.tryParse(exactDate);
        if (parsed != null) {
          final day = DateTime(parsed.year, parsed.month, parsed.day);
          if (day != selectedDay) return false;
        }
      } else {
        if (_weekdayFromSlot(slot) != selectedDay.weekday) return false;
      }
      final availableRaw =
          (slot['available'] ?? slot['is_available'] ?? slot['bookable'])
              ?.toString()
              .toLowerCase();
      if (availableRaw == 'false' || availableRaw == '0') return false;
      final startRaw = (slot['start_time'] ?? slot['startTime'] ?? '').toString().trim();
      return startRaw.isNotEmpty;
    }).toList();

    final blocks = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (final slot in rawSlots) {
      final startRaw = (slot['start_time'] ?? slot['startTime'] ?? '').toString().trim();
      final endRaw = (slot['end_time'] ?? slot['endTime'] ?? '').toString().trim();
      final (startH, startM) = _parseHM(startRaw);
      final (endH, _) = endRaw.isNotEmpty ? _parseHM(endRaw) : (startH + 1, 0);

      // Venster ≤ 1 uur → is al een blok
      if (endH - startH <= 1) {
        final slotDt = DateTime(selectedDay.year, selectedDay.month, selectedDay.day, startH, startM);
        if (slotDt.isAfter(now)) {
          blocks.add({
            ...slot,
            'start_time': '${startH.toString().padLeft(2, '0')}:${startM.toString().padLeft(2, '0')}',
            'end_time': '${endH.toString().padLeft(2, '0')}:00',
          });
        }
        continue;
      }

      // Splits in uurblokken
      for (int h = startH; h < endH; h++) {
        final slotDt = DateTime(selectedDay.year, selectedDay.month, selectedDay.day, h, 0);
        if (slotDt.isAfter(now)) {
          blocks.add({
            ...slot,
            'start_time': '${h.toString().padLeft(2, '0')}:00',
            'end_time': '${(h + 1).toString().padLeft(2, '0')}:00',
          });
        }
      }
    }

    blocks.sort((a, b) => _slotStart(a).compareTo(_slotStart(b)));
    return blocks;
  }

  void _startHoldTicker(DateTime holdUntil) {
    _slotHoldTicker?.cancel();
    _slotHoldTicker = Timer.periodic(TimingConstants.slotHoldTickerInterval, (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(holdUntil)) {
        _slotHoldTicker?.cancel();
        setState(() {
          _activeSlotHold = null;
          _slotHoldUntil = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  String? _holdCountdownLabel() {
    final until = _slotHoldUntil;
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    if (remaining.inSeconds <= 0) return null;
    final m = remaining.inMinutes;
    final s = remaining.inSeconds % 60;
    return 'Slot op hold: ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _selectSlot(Map<String, dynamic> slot) async {
    final trainer = _trainer;
    if (trainer == null || trainer.userId.isEmpty) return;
    setState(() {
      _selectedSlot = slot;
      _activeSlotHold = null;
      _slotHoldUntil = null;
    });
    final scheduledAt = _slotDateTime(slot, _selectedDate);
    try {
      final hold = await _api.holdTrainerPublicSlot(
        trainerUserId: trainer.userId,
        scheduledAt: scheduledAt,
        availabilitySlotId: _slotId(slot),
      );
      final untilRaw =
          (hold['hold_until'] ??
                  hold['expires_at'] ??
                  hold['hold_expires_at'] ??
                  '')
              .toString()
              .trim();
      final until = DateTime.tryParse(untilRaw);
      if (!mounted) return;
      setState(() {
        _activeSlotHold = hold;
        _slotHoldUntil = until;
      });
      if (until != null) _startHoldTicker(until);
    } on ApiException catch (_) {
      // Fallback: UI blijft bruikbaar zonder hold als endpoint nog niet live is.
    }
  }

  Future<void> _bookSession() async {
    if (_booking) return;
    final trainer = _trainer;
    if (trainer == null || trainer.userId.isEmpty) {
      _showError('Trainer-ID ontbreekt.');
      return;
    }
    final slot = _selectedSlot;
    if (slot == null) {
      _showError('Kies eerst een beschikbaar tijdslot.');
      return;
    }

    // ── Stap 1: Bereken prijs voor bevestigingsscherm ──
    final pkg = _selectedPackageMap();
    final priceCents = pkg != null
        ? _priceCents(pkg)
        : trainer.hourlyRateCents;
    final priceLabel = _formatPrice(priceCents);
    final dt = _slotDateTime(slot, _selectedDate);
    final dayLabel = [
      'Maandag', 'Dinsdag', 'Woensdag', 'Donderdag',
      'Vrijdag', 'Zaterdag', 'Zondag',
    ][dt.weekday - 1];
    final timeLabel =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final dateLabel =
        '${dt.day}-${dt.month}-${dt.year}';

    // ── Stap 2: Bevestigingsdialog met prijs + betaalmethode ──
    String selectedPaymentMethod = 'mollie';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => GymiesDialog(
          title: 'Boeking bevestigen',
          headerIcon: Icons.event_available_rounded,
          maxContentHeight: 500,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sessie-info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trainer.displayName,
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 14),
                        const SizedBox(width: 6),
                        Text('$dayLabel $dateLabel', style: GoogleFonts.sora(fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 14),
                        const SizedBox(width: 6),
                        Text(timeLabel, style: GoogleFonts.sora(fontSize: 14)),
                      ],
                    ),
                    if (pkg != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              mapStr(pkg, ['name', 'title']).isNotEmpty
                                  ? mapStr(pkg, ['name', 'title'])
                                  : 'Pakket',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Prijs
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: GymiesColors.darkBlue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GymiesColors.darkBlue.withValues(alpha: 0.12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Totaal', style: GoogleFonts.sora(fontSize: 15)),
                    Text(
                      priceLabel,
                      style: GoogleFonts.sora(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Betaalmethode keuze — gestylede kaarten
              Text(
                'Betaalmethode',
                style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              // ── Online betalen kaart ──
              GestureDetector(
                onTap: () => setDialogState(() => selectedPaymentMethod = 'mollie'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selectedPaymentMethod == 'mollie'
                        ? GymiesColors.primary.withValues(alpha: 0.12)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selectedPaymentMethod == 'mollie'
                          ? GymiesColors.primary
                          : Colors.grey.shade200,
                      width: selectedPaymentMethod == 'mollie' ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Check / radio icoon
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selectedPaymentMethod == 'mollie'
                                  ? GymiesColors.darkBlue
                                  : Colors.transparent,
                              border: Border.all(
                                color: selectedPaymentMethod == 'mollie'
                                    ? GymiesColors.darkBlue
                                    : Colors.grey.shade400,
                                width: 1.5,
                              ),
                            ),
                            child: selectedPaymentMethod == 'mollie'
                                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          // Icoon container
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: GymiesColors.darkBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.credit_card_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Online betalen',
                                  style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14, color: GymiesColors.darkBlue),
                                ),
                                Text(
                                  'iDEAL, creditcard, Apple Pay',
                                  style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (selectedPaymentMethod == 'mollie') ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                          decoration: BoxDecoration(
                            color: GymiesColors.darkBlue.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_rounded, size: 12, color: GymiesColors.darkBlue.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Text(
                                'Beveiligd via Mollie — directe bevestiging',
                                style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // ── Cash betalen kaart ──
              GestureDetector(
                onTap: () => setDialogState(() => selectedPaymentMethod = 'cash'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selectedPaymentMethod == 'cash'
                        ? GymiesColors.primary.withValues(alpha: 0.12)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selectedPaymentMethod == 'cash'
                          ? GymiesColors.primary
                          : Colors.grey.shade200,
                      width: selectedPaymentMethod == 'cash' ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Check / radio icoon
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selectedPaymentMethod == 'cash'
                              ? GymiesColors.darkBlue
                              : Colors.transparent,
                          border: Border.all(
                            color: selectedPaymentMethod == 'cash'
                                ? GymiesColors.darkBlue
                                : Colors.grey.shade400,
                            width: 1.5,
                          ),
                        ),
                        child: selectedPaymentMethod == 'cash'
                            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      // Icoon container
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.payments_outlined, color: Colors.grey.shade700, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cash bij trainer',
                              style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14, color: GymiesColors.darkBlue),
                            ),
                            Text(
                              'Betaal contant op de dag zelf',
                              style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            GymiesDialogAction(
              label: 'Annuleren',
              returnValue: false,
            ),
            GymiesDialogAction(
              label: selectedPaymentMethod == 'cash'
                  ? 'Bevestig boeking'
                  : 'Ga naar betaling',
              isPrimary: true,
              returnValue: true,
              icon: selectedPaymentMethod == 'cash'
                  ? Icons.check_rounded
                  : Icons.lock_rounded,
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // ── Stap 2b: Hercontroleer beschikbaarheid (voorkom stale data) ──
    try {
      final freshSlots = await _api.getTrainerPublicAvailability(trainer.userId);
      if (!mounted) return;
      final slotStillExists = freshSlots.any((s) {
        final sDate = _slotDateTime(s, _selectedDate);
        return sDate.isAtSameMomentAs(dt);
      });
      if (!slotStillExists) {
        _showError('Dit tijdslot is helaas niet meer beschikbaar. Kies een ander moment.');
        // Refresh de slots in de UI
        _load();
        return;
      }
    } catch (_) {
      // Bij netwerk-error: ga door met de boeking (backend valideert ook)
    }

    // ── Stap 3: Boeking aanmaken (reserved) ──
    setState(() => _booking = true);
    try {
      final holdId =
          (_activeSlotHold?['id'] ??
                  _activeSlotHold?['hold_id'] ??
                  _activeSlotHold?['holdId'])
              ?.toString();
      final holdToken =
          (_activeSlotHold?['token'] ??
                  _activeSlotHold?['hold_token'] ??
                  _activeSlotHold?['holdToken'])
              ?.toString();
      final bookingData = await _api.createDirectBooking(
        trainerUserId: trainer.userId,
        scheduledAt: dt,
        packageId: _selectedPackageId,
        note: _noteController.text.trim(),
        availabilitySlotId: _slotId(slot),
        holdId: holdId,
        holdToken: holdToken,
      );
      if (!mounted) return;

      final bookingId = (bookingData['id'] ?? bookingData['booking_id'] ?? '').toString();
      if (bookingId.isEmpty) {
        _showError('Boeking aangemaakt maar geen ID ontvangen.');
        return;
      }

      // ── Stap 4: Betaling starten ──
      // Aparte try/catch: als betaling faalt mag de boeking NIET verloren gaan.
      // Gebruiker wordt doorgestuurd naar Mijn Sessies waar ze opnieuw kunnen betalen.
      try {
        final api = _api;
        final paymentData = await api.startBookingPayment(
          bookingId: bookingId,
          paymentMethod: selectedPaymentMethod,
        );
        if (!mounted) return;

        if (selectedPaymentMethod == 'cash') {
          // Cash: boeking is klaar, geen Mollie redirect nodig
          Haptics.success();
          // ── Auto-sync naar agenda als ingeschakeld ──
          _autoSyncToCalendar(bookingData, trainer, dt);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Boeking bevestigd! Betaal cash bij je trainer.'),
              backgroundColor: GymiesColors.darkBlue,
            ),
          );
          Navigator.of(context).pop(true);
          return;
        }

        // ── Stap 5: Mollie checkout openen ──
        final paymentUrl = (paymentData['payment_url']
                ?? paymentData['redirect_url']
                ?? paymentData['url']
                ?? '')
            .toString();

        if (paymentUrl.isEmpty) {
          // Boeking is aangemaakt maar betaallink ophalen mislukt
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Boeking aangemaakt! Open "Mijn Sessies" om te betalen.'),
              backgroundColor: GymiesColors.darkBlue,
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.of(context).pop(true);
          return;
        }

        // ── Auto-sync naar agenda als ingeschakeld ──
        _autoSyncToCalendar(bookingData, trainer, dt);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Je wordt doorgestuurd naar de betaalpagina...'),
            backgroundColor: GymiesColors.darkBlue,
            duration: Duration(seconds: 2),
          ),
        );

        if (mounted) {
          await SafeUrlLauncher.launchPaymentUrl(context, paymentUrl);
        }
        // Na terugkeer: klant ziet de betaalstatus in Mijn Sessies
        if (mounted) Navigator.of(context).pop(true);
      } catch (paymentError) {
        // Boeking IS aangemaakt maar betaling starten is mislukt.
        // Gebruiker kan alsnog betalen via Mijn Sessies.
        if (mounted) {
          Haptics.medium();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Boeking aangemaakt maar betaling kon niet worden gestart. '
                'Ga naar "Mijn Sessies" om alsnog te betalen.',
              ),
              backgroundColor: GymiesColors.darkBlue,
              duration: Duration(seconds: 5),
            ),
          );
          Navigator.of(context).pop(true);
        }
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Boeking mislukt. Probeer opnieuw.');
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  /// Auto-sync: voeg de nieuwe boeking toe aan de device-kalender als
  /// de gebruiker auto-sync heeft ingeschakeld in Voorkeuren.
  Future<void> _autoSyncToCalendar(
    Map<String, dynamic> bookingData,
    Trainer trainer,
    DateTime scheduledAt,
  ) async {
    try {
      final enabled = await CalendarService.instance.isAutoSyncEnabled();
      if (!enabled) return;

      // Bouw een Booking object van de API response
      final booking = Booking(
        id: (bookingData['id'] ?? bookingData['booking_id'] ?? '').toString(),
        trainerName: trainer.displayName,
        scheduledAt: scheduledAt,
        durationMinutes: int.tryParse(
              (bookingData['duration_minutes'] ?? '60').toString(),
            ) ??
            60,
        status: (bookingData['status'] ?? 'confirmed').toString(),
        trainerUserId: trainer.userId,
        packageName: bookingData['package_name']?.toString(),
      );

      await CalendarService.instance.addBookingToCalendar(booking);
    } catch (e) {
      if (kDebugMode) debugPrint('[CalendarAutoSync] Fout: $e');
      // Geen error tonen — auto-sync mag niet de boekingflow verstoren
    }
  }

  Future<void> _joinWaitlist() async {
    if (_booking) return;
    final trainer = _trainer;
    if (trainer == null || trainer.userId.isEmpty) {
      _showError('Trainer-ID ontbreekt.');
      return;
    }
    setState(() => _booking = true);
    try {
      final preferredAt = _selectedSlot != null
          ? _slotDateTime(_selectedSlot!, _selectedDate)
          : DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              12,
              0,
            );
      await _api.joinTrainerWaitlist(
        trainerUserId: trainer.userId,
        preferredAt: preferredAt,
        note: _noteController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Je staat nu op de standby-lijst voor deze trainer'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Standby-aanmelding mislukt. Probeer opnieuw.');
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _openChat() async {
    if (_openingChat) return;
    final trainer = _trainer;
    if (trainer == null || trainer.userId.isEmpty) {
      _showError('Trainer-ID ontbreekt.');
      return;
    }
    setState(() => _openingChat = true);
    try {
      final c = await _api.ensureClientConversation(
        trainerUserId: trainer.userId,
      );
      if (!mounted) return;
      final conversationId = mapStr(c, [
        'id',
        'conversation_id',
        'conversationId',
      ]);
      if (conversationId.isEmpty) {
        _showError('Kon geen gesprek openen.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientChatScreen(
            conversationId: conversationId,
            title: trainer.nameOrEmail,
          ),
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _scrollToBookingForm() async {
    final ctx = _bookingCardKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      alignment: 0.04,
    );
  }

  Future<void> _openFullPublicProfile(Trainer trainer) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ClientPublicTrainerProfileScreen(
          trainer: trainer,
          packages: _packages,
          availability: _availability,
          mediaGallery: _mediaGallery,
          storyMedia: _storyMedia,
          reviews: _reviews,
          onChatTap: _openChat,
          onBookTap: _scrollToBookingForm,
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'chat') {
      _openChat();
    } else if (result == 'book') {
      _scrollToBookingForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainer = _trainer ?? widget.trainer;
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text('Trainer', style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (trainer == null) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text('Trainer', style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_off_rounded, size: 48, color: Colors.grey.shade600),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Trainer niet gevonden',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(color: Colors.grey.shade800),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Terug'),
                  style: FilledButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    foregroundColor: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (widget.showFullProfileOnly) {
      return ClientPublicTrainerProfileScreen(
        trainer: trainer,
        packages: _packages,
        availability: _availability,
        mediaGallery: _mediaGallery,
        storyMedia: _storyMedia,
        reviews: _reviews,
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // ── Premium gradient header met trainer info ──
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: GymiesColors.darkBlue,
            foregroundColor: Colors.white,
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1E3A5F),
                      Color(0xFF2A4F7A),
                      Color(0xFF1E3A5F),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── Avatar met gouden ring ──
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: GymiesColors.primary, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: GymiesColors.primary.withValues(alpha: 0.3),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(19),
                            child: _GymiesAvatar(
                                      url: trainer.avatarUrl,
                                      fallbackName: trainer.nameOrEmail,
                                      size: 88,
                                      fontSize: 32,
                                      bgColor: GymiesColors.primary.withValues(alpha: 0.2),
                                    ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // ── Trainer info ──
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trainer.nameOrEmail,
                                style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (trainer.specialty != null && trainer.specialty!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: trainer.specialty!
                                      .split(RegExp(r'[,،;]+'))
                                      .map((s) => s.trim())
                                      .where((s) => s.isNotEmpty)
                                      .map((tag) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: GymiesColors.primary.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              tag,
                                              style: GoogleFonts.sora(fontSize: 11, color: GymiesColors.primary, fontWeight: FontWeight.w600),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (trainer.rating != null) ...[
                                    Icon(Icons.star_rounded, size: 18, color: GymiesColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      trainer.rating!.toStringAsFixed(1),
                                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                                    if (trainer.reviewCount != null && trainer.reviewCount! > 0)
                                      Text(
                                        ' (${trainer.reviewCount})',
                                        style: GoogleFonts.sora(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                                      ),
                                    const SizedBox(width: 12),
                                  ],
                                  if (trainer.region != null && trainer.region!.isNotEmpty) ...[
                                    Icon(Icons.location_on_rounded, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        trainer.region!,
                                        style: GoogleFonts.sora(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              // ── Prijs badge ──
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: GymiesColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  trainer.hourlyRateCents != null
                                      ? '€${(trainer.hourlyRateCents! / 100).toStringAsFixed(0)} / sessie'
                                      : 'Prijs op aanvraag',
                                  style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: GymiesColors.darkBlue),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.isFromMyTrainers)
                          GestureDetector(
                            onTap: () => _openFullPublicProfile(trainer),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.open_in_new_rounded, size: 20, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: RefreshIndicator(
              onRefresh: _load,
              color: GymiesColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!, style: GoogleFonts.sora(color: Colors.red.shade700, fontSize: 13))),
                        ],
                      ),
                    ),
                  if (widget.isFromMyTrainers) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onRemoveFromMyTrainers,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          side: BorderSide(color: Colors.red.shade200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.person_remove_outlined, size: 18),
                        label: Text('Verwijder uit mijn trainers', style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!widget.focusBookingForm && !widget.isFromMyTrainers) ...[
                    // ── Profiel bekijken CTA ──
                    GestureDetector(
                      onTap: () => _openFullPublicProfile(trainer),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              GymiesColors.darkBlue.withValues(alpha: 0.06),
                              GymiesColors.primary.withValues(alpha: 0.06),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: GymiesColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: GymiesColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.person_search_rounded, size: 20, color: GymiesColors.darkBlue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Bekijk volledig profiel', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                                  Text('Reviews, galerij, pakketten en meer', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // ── BOOKING FORM ──
                  Container(
                    key: _bookingCardKey,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: GymiesColors.primary.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: GymiesColors.primary.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Compact booking section ──
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          // ── Segmented toggle: Losse sessie / Pakket ──
                          if (_packages.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _usePackage = false;
                                        _selectedPackageId = null;
                                      }),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: !_usePackage ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: !_usePackage
                                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                                              : null,
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              'Losse sessie',
                                              style: GoogleFonts.sora(
                                                fontSize: 12,
                                                fontWeight: !_usePackage ? FontWeight.w600 : FontWeight.w400,
                                                color: !_usePackage ? GymiesColors.darkBlue : Colors.grey.shade500,
                                              ),
                                            ),
                                            Text(
                                              trainer.hourlyRateCents != null ? _formatPrice(trainer.hourlyRateCents) : '–',
                                              style: GoogleFonts.sora(
                                                fontSize: 11,
                                                color: !_usePackage ? GymiesColors.primary : Colors.grey.shade400,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _usePackage = true;
                                        _selectedPackageId = _packages.isNotEmpty
                                            ? mapStr(_packages.first, ['id', 'package_id', 'packageId'])
                                            : null;
                                      }),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: _usePackage ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: _usePackage
                                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                                              : null,
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              'Pakket',
                                              style: GoogleFonts.sora(
                                                fontSize: 12,
                                                fontWeight: _usePackage ? FontWeight.w600 : FontWeight.w400,
                                                color: _usePackage ? GymiesColors.darkBlue : Colors.grey.shade500,
                                              ),
                                            ),
                                            Text(
                                              _selectedPackageMap() != null
                                                  ? _formatPrice(_priceCents(_selectedPackageMap()!))
                                                  : _formatPrice(_priceCents(_packages.first)),
                                              style: GoogleFonts.sora(
                                                fontSize: 11,
                                                color: _usePackage ? GymiesColors.primary : Colors.grey.shade400,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // ── Pakket keuze ──
                          if (_usePackage && _packages.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () {
                                // Toon dropdown via bottom sheet of modal
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                  ),
                                  builder: (ctx) => SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                                          const SizedBox(height: 16),
                                          Text('Kies een pakket', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                                          const SizedBox(height: 12),
                                          ..._packages.map((p) {
                                            final id = mapStr(p, ['id', 'package_id', 'packageId']);
                                            final name = mapStr(p, ['name', 'title']).isNotEmpty ? mapStr(p, ['name', 'title']) : 'Pakket';
                                            final selected = _selectedPackageId == id;
                                            return ListTile(
                                              title: Text(name, style: GoogleFonts.sora(fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: GymiesColors.darkBlue)),
                                              trailing: Text(_formatPrice(_priceCents(p)), style: GoogleFonts.sora(fontWeight: FontWeight.w600, color: GymiesColors.primary)),
                                              selected: selected,
                                              selectedTileColor: GymiesColors.primary.withValues(alpha: 0.08),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              onTap: () {
                                                setState(() => _selectedPackageId = id);
                                                Navigator.pop(ctx);
                                              },
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('GEKOZEN PAKKET', style: GoogleFonts.sora(fontSize: 9, color: Colors.grey.shade500, letterSpacing: 0.5, fontWeight: FontWeight.w500)),
                                          const SizedBox(height: 2),
                                          Text(
                                            mapStr(_selectedPackageMap() ?? _packages.first, ['name', 'title']).isNotEmpty
                                                ? mapStr(_selectedPackageMap() ?? _packages.first, ['name', 'title'])
                                                : 'Pakket',
                                            style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _formatPrice(_priceCents(_selectedPackageMap() ?? _packages.first)),
                                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.primary),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade400),
                                  ],
                                ),
                              ),
                            ),
                            // Pakket info
                            Builder(
                              builder: (_) {
                                final selected = _selectedPackageMap();
                                final sessions = _toInt(
                                  selected == null ? null : mapPick(selected, ['sessions_count', 'sessions', 'lessons_count']),
                                );
                                if (sessions == null || sessions <= 0) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6, left: 2),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline_rounded, size: 13, color: Colors.blue.shade400),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$sessions ${sessions == 1 ? 'sessie' : 'sessies'} in dit pakket',
                                        style: GoogleFonts.sora(fontSize: 11, color: Colors.blue.shade400),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                          ],

                          // ── Datum: horizontale weekstrip ──
                          Text('KIES EEN DATUM', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue, letterSpacing: 0.5)),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (_) {
                              const dayNames = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
                              const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
                              // Genereer 7 dagen vanaf vandaag
                              final today = DateTime.now();
                              final days = List.generate(7, (i) => today.add(Duration(days: i)));

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: days.map((day) {
                                      final isSelected = day.year == _selectedDate.year &&
                                          day.month == _selectedDate.month &&
                                          day.day == _selectedDate.day;
                                      // Check of er slots zijn voor deze dag
                                      final dayOfWeek = day.weekday; // 1=ma, 7=zo
                                      final hasSlots = _availability.any((a) {
                                        final aDow = a['day_of_week'] ?? a['dayOfWeek'];
                                        return aDow == dayOfWeek;
                                      });
                                      return Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            Haptics.selection();
                                            setState(() {
                                              _selectedDate = day;
                                              _selectedSlot = null;
                                            });
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 2),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isSelected ? GymiesColors.darkBlue : Colors.transparent,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  dayNames[(day.weekday - 1) % 7],
                                                  style: GoogleFonts.sora(
                                                    fontSize: 9,
                                                    color: isSelected ? Colors.white.withValues(alpha: 0.6) : Colors.grey.shade500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${day.day}',
                                                  style: GoogleFonts.sora(
                                                    fontSize: 14,
                                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                                    color: isSelected ? Colors.white : (hasSlots ? GymiesColors.darkBlue : Colors.grey.shade300),
                                                  ),
                                                ),
                                                if (hasSlots && !isSelected)
                                                  Container(
                                                    margin: const EdgeInsets.only(top: 3),
                                                    width: 4,
                                                    height: 4,
                                                    decoration: BoxDecoration(
                                                      color: GymiesColors.primary,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  )
                                                else
                                                  const SizedBox(height: 7),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${months[_selectedDate.month - 1]} ${_selectedDate.year}',
                                          style: GoogleFonts.sora(fontSize: 10, color: Colors.grey.shade500),
                                        ),
                                        GestureDetector(
                                          onTap: _pickDate,
                                          child: Row(
                                            children: [
                                              Icon(Icons.calendar_month_rounded, size: 14, color: GymiesColors.primary),
                                              const SizedBox(width: 3),
                                              Text('Meer data', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),

                          // ── Tijdslots met ochtend/middag groepering ──
                          Builder(
                            builder: (_) {
                              final daySlots = _slotsForSelectedDate();
                              final noSlots = daySlots.isEmpty;

                              if (noSlots) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.orange.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.event_busy_rounded, size: 18, color: Colors.orange.shade700),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _availability.isEmpty
                                                  ? 'Nog geen beschikbaarheid ingesteld'
                                                  : 'Geen slots beschikbaar op deze dag',
                                              style: GoogleFonts.sora(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _booking ? null : _joinWaitlist,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: GymiesColors.darkBlue,
                                          side: const BorderSide(color: GymiesColors.darkBlue),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: const Icon(Icons.notifications_active_outlined, size: 16),
                                        label: Text('Op standby-lijst', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              // Groepeer slots in ochtend (<12:00) en middag (>=12:00)
                              final morning = daySlots.where((s) {
                                final h = int.tryParse(_slotStart(s).split(':').first) ?? 0;
                                return h < 12;
                              }).toList();
                              final afternoon = daySlots.where((s) {
                                final h = int.tryParse(_slotStart(s).split(':').first) ?? 0;
                                return h >= 12;
                              }).toList();

                              Widget buildSlotGrid(List<Map<String, dynamic>> slots) {
                                return Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: slots.map((slot) {
                                    final start = _slotStart(slot);
                                    final selected = identical(_selectedSlot, slot) ||
                                        (_slotStart(_selectedSlot ?? {}) == _slotStart(slot) &&
                                            _slotEnd(_selectedSlot ?? {}) == _slotEnd(slot));
                                    return GestureDetector(
                                      onTap: () => _selectSlot(slot),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: selected ? GymiesColors.darkBlue.withValues(alpha: 0.08) : Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: selected ? GymiesColors.darkBlue : Colors.grey.shade200,
                                            width: selected ? 2 : 1,
                                          ),
                                        ),
                                        child: Text(
                                          start,
                                          style: GoogleFonts.sora(
                                            fontSize: 13,
                                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                            color: selected ? GymiesColors.darkBlue : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('KIES EEN TIJDSTIP', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue, letterSpacing: 0.5)),
                                  const SizedBox(height: 8),
                                  if (morning.isNotEmpty) ...[
                                    Text('Ochtend', style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500)),
                                    const SizedBox(height: 6),
                                    buildSlotGrid(morning),
                                    const SizedBox(height: 10),
                                  ],
                                  if (afternoon.isNotEmpty) ...[
                                    Text('Middag', style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500)),
                                    const SizedBox(height: 6),
                                    buildSlotGrid(afternoon),
                                  ],
                                ],
                              );
                            },
                          ),

                          if (_holdCountdownLabel() != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _holdCountdownLabel()!,
                                style: GoogleFonts.sora(color: Colors.green.shade800, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],

                          // ── Notitie (compact) ──
                          const SizedBox(height: 12),
                          TextField(
                            controller: _noteController,
                            minLines: 1,
                            maxLines: 3,
                            style: GoogleFonts.sora(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Notitie voor trainer toevoegen...',
                              hintStyle: GoogleFonts.sora(color: Colors.grey.shade400, fontSize: 12),
                              prefixIcon: Icon(Icons.edit_note_rounded, size: 18, color: Colors.grey.shade400),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: GymiesColors.primary, width: 1.5),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                          ),

                          // ── Bevestig boeking knop met samenvatting ──
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: (_booking || _slotsForSelectedDate().isEmpty)
                                  ? null
                                  : _bookSession,
                              style: FilledButton.styleFrom(
                                backgroundColor: GymiesColors.primary,
                                foregroundColor: GymiesColors.darkBlue,
                                disabledBackgroundColor: Colors.grey.shade200,
                                disabledForegroundColor: Colors.grey.shade400,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _booking
                                  ? Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: GymiesColors.darkBlue)),
                                        const SizedBox(width: 8),
                                        Text('Bezig met boeken...', style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 15)),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        Text('Bevestig boeking', style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 15)),
                                        if (_selectedSlot != null)
                                          Builder(
                                            builder: (_) {
                                              const dayNames = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
                                              const monthNames = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
                                              final dn = dayNames[(_selectedDate.weekday - 1) % 7];
                                              final mn = monthNames[_selectedDate.month - 1];
                                              final pkg = _selectedPackageMap();
                                              final priceCents = _usePackage && pkg != null ? _priceCents(pkg) : trainer.hourlyRateCents;
                                              return Text(
                                                '$dn ${_selectedDate.day} $mn \u2022 ${_slotStart(_selectedSlot!)} - ${_slotEnd(_selectedSlot!)} \u2022 ${_formatPrice(priceCents)}',
                                                style: GoogleFonts.sora(fontSize: 10, color: GymiesColors.darkBlue.withValues(alpha: 0.5)),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
                  // Chat-knop is nu in de sticky bottom bar
                  if (_availability.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: GymiesColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.calendar_month_rounded, size: 20, color: GymiesColors.primary),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Beschikbaarheid',
                                  style: GoogleFonts.sora(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Deze week',
                              style: GoogleFonts.sora(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._availabilityForWeek(_availability, weekOffset: 0)
                                .where((d) => d.windows.isNotEmpty)
                                .take(7)
                                .map(
                                  (day) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            color: GymiesColors.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${day.date.day.toString().padLeft(2, '0')}/${day.date.month.toString().padLeft(2, '0')}',
                                              style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            day.windows.join(' · '),
                                            style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade700),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            const SizedBox(height: 10),
                            Text(
                              'Volgende week',
                              style: GoogleFonts.sora(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._availabilityForWeek(_availability, weekOffset: 1)
                                .where((d) => d.windows.isNotEmpty)
                                .take(7)
                                .map(
                                  (day) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            color: GymiesColors.darkBlue.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${day.date.day.toString().padLeft(2, '0')}/${day.date.month.toString().padLeft(2, '0')}',
                                              style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            day.windows.join(' · '),
                                            style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade700),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
      ),
      // ── Sticky bottom bar ──
      bottomNavigationBar: (!widget.showFullProfileOnly && !widget.isFromMyTrainers)
          ? Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: GymiesColors.darkBlue.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _openingChat ? null : _openChat,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GymiesColors.darkBlue,
                        side: const BorderSide(color: GymiesColors.darkBlue, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: Icon(_openingChat ? Icons.hourglass_top_rounded : Icons.chat_bubble_outline_rounded, size: 18),
                      label: Text(_openingChat ? 'Bezig...' : 'Bericht', style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: (_booking || _slotsForSelectedDate().isEmpty) ? null : _scrollToBookingForm,
                      style: FilledButton.styleFrom(
                        backgroundColor: GymiesColors.primary,
                        foregroundColor: GymiesColors.darkBlue,
                        disabledBackgroundColor: GymiesColors.primary.withValues(alpha: 0.4),
                        disabledForegroundColor: GymiesColors.darkBlue.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: Text('Boek sessie', style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class ClientPublicTrainerProfileScreen extends StatefulWidget {
  const ClientPublicTrainerProfileScreen({
    super.key,
    required this.trainer,
    this.packages,
    this.availability,
    this.mediaGallery,
    this.storyMedia,
    this.reviews,
    this.onChatTap,
    this.onBookTap,
  });

  final Trainer trainer;
  final List<Map<String, dynamic>>? packages;
  final List<Map<String, dynamic>>? availability;
  final List<Map<String, dynamic>>? mediaGallery;
  final List<Map<String, dynamic>>? storyMedia;
  final List<Map<String, dynamic>>? reviews;
  final VoidCallback? onChatTap;
  final VoidCallback? onBookTap;

  @override
  State<ClientPublicTrainerProfileScreen> createState() =>
      _ClientPublicTrainerProfileScreenState();
}

class _ClientPublicTrainerProfileScreenState
    extends State<ClientPublicTrainerProfileScreen> {
  final ScrollController _scrollController = ScrollController();
  late GymiesApi _api;

  Trainer get trainer => widget.trainer;

  // ── Async-loaded data ──
  bool _dataLoading = true;
  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> _availability = const [];
  List<Map<String, dynamic>> _mediaGallery = const [];
  List<Map<String, dynamic>> _storyMedia = const [];
  List<Map<String, dynamic>> _reviews = const [];

  List<Map<String, dynamic>> get packages => _packages;
  List<Map<String, dynamic>> get availability => _availability;
  List<Map<String, dynamic>> get mediaGallery => _mediaGallery;
  List<Map<String, dynamic>> get storyMedia => _storyMedia;
  List<Map<String, dynamic>> get reviews => _reviews;

  bool _didFirstLoad = false;

  @override
  void initState() {
    super.initState();
    // Verwijder eventuele stale cache voor trainer avatar
    if (trainer.avatarUrl != null && trainer.avatarUrl!.trim().isNotEmpty) {
      CachedNetworkImage.evictFromCache(trainer.avatarUrl!.trim());
    }
    // Gebruik meegegeven data als die er is
    if (widget.packages != null && widget.availability != null) {
      _packages = widget.packages!;
      _availability = widget.availability!;
      _mediaGallery = widget.mediaGallery ?? const [];
      _storyMedia = widget.storyMedia ?? const [];
      _reviews = widget.reviews ?? const [];
      _dataLoading = false;
      _didFirstLoad = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<GymiesApi>();
    if (!_didFirstLoad) {
      _didFirstLoad = true;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      final api = _api;
      final id = trainer.userId;

      final results = await Future.wait<dynamic>([
        api.getTrainerPublicPackages(id),
        api.getTrainerPublicAvailability(id),
        Future<Map<String, List<Map<String, dynamic>>>>(() async {
          try {
            final mediaRes = await api.getTrainerPublicMedia(id);
            List<Map<String, dynamic>> gallery = [];
            List<Map<String, dynamic>> story = [];
            final rawGallery = mediaRes['media_gallery'] ?? mediaRes['mediaGallery'] ?? mediaRes['gallery'];
            final rawStory = mediaRes['story_media'] ?? mediaRes['storyMedia'] ?? mediaRes['story'] ?? mediaRes['stories'];
            if (rawGallery is List) {
              gallery = rawGallery.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
            }
            if (rawStory is List) {
              story = rawStory.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
            }
            if (gallery.isEmpty && story.isEmpty) {
              final rawItems = mediaRes['data'] ?? mediaRes['items'];
              if (rawItems is List) {
                for (final e in rawItems) {
                  final m = e is Map<String, dynamic> ? e : <String, dynamic>{};
                  final usage = (m['usage'] ?? m['usage_type'] ?? 'gallery').toString().toLowerCase();
                  if (usage == 'story') { story.add(m); } else { gallery.add(m); }
                }
              }
            }
            return {'gallery': gallery, 'story': story};
          } catch (_) {
            return {'gallery': <Map<String, dynamic>>[], 'story': <Map<String, dynamic>>[]};
          }
        }),
        Future<List<Map<String, dynamic>>>(() async {
          try {
            final revRes = await api.getTrainerReviews(id);
            final raw = revRes['data'];
            if (raw is List) {
              return raw.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
            }
            return <Map<String, dynamic>>[];
          } catch (_) { return <Map<String, dynamic>>[]; }
        }),
      ]);

      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<Map<String, dynamic>>;
        _availability = results[1] as List<Map<String, dynamic>>;
        final mediaResult = results[2] as Map<String, List<Map<String, dynamic>>>;
        _mediaGallery = mediaResult['gallery'] ?? const [];
        _storyMedia = mediaResult['story'] ?? const [];
        _reviews = results[3] as List<Map<String, dynamic>>;
        _dataLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _dataLoading = false);
    }
  }

  bool _isVideo(Map<String, dynamic> m) {
    final t = (m['type'] ?? m['media_type'] ?? '').toString().toLowerCase();
    final url = (_mediaUrl(m)).toLowerCase();
    return t == 'video' || url.contains('.mp4') || url.contains('video');
  }

  String _mediaUrl(Map<String, dynamic> m) =>
      (m['url'] ?? m['thumbnail_url'] ?? m['media_url'] ?? '').toString();

  Widget _mediaPlaceholder(bool isVideo) => Container(
        color: Colors.grey.shade300,
        child: Center(
          child: Icon(
            isVideo ? Icons.videocam : Icons.photo,
            size: 48,
            color: Colors.grey.shade600,
          ),
        ),
      );

  void _openStoryViewer() {
    if (storyMedia.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StoryViewerScreen(
          trainer: trainer,
          items: storyMedia,
          urlOf: _mediaUrl,
          isVideo: _isVideo,
          initialIndex: 0,
        ),
      ),
    );
  }

  void _openGalleryViewer(int initialIndex) {
    if (mediaGallery.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StoryViewerScreen(
          trainer: trainer,
          items: mediaGallery,
          urlOf: _mediaUrl,
          isVideo: _isVideo,
          initialIndex: initialIndex.clamp(0, mediaGallery.length - 1),
        ),
      ),
    );
  }

  List<Widget> _buildLoadingShimmers() {
    Widget shimmerBox({double height = 16, double? width, double radius = 8}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    Widget shimmerSection() {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
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
                shimmerBox(height: 34, width: 34, radius: 10),
                const SizedBox(width: 10),
                shimmerBox(height: 18, width: 140),
              ],
            ),
            const SizedBox(height: 14),
            shimmerBox(height: 14, width: double.infinity),
            const SizedBox(height: 8),
            shimmerBox(height: 14, width: 200),
            const SizedBox(height: 8),
            shimmerBox(height: 14, width: 160),
          ],
        ),
      );
    }

    return [
      shimmerSection(),
      shimmerSection(),
      shimmerSection(),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: GymiesColors.primary,
            ),
          ),
        ),
      ),
    ];
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  dynamic mapPick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) return map[key];
    }
    return null;
  }

  String mapStr(Map<String, dynamic> map, List<String> keys) {
    final v = mapPick(map, keys);
    return v?.toString() ?? '';
  }

  int? _priceCents(Map<String, dynamic> map) {
    // Probeer eerst _cents velden — die zijn al in centen.
    for (final key in ['price_cents', 'amount_cents']) {
      final v = map[key];
      if (v != null) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        final parsed = int.tryParse(v.toString());
        if (parsed != null) return parsed;
      }
    }
    // Fallback: price/amount in euro's — vermenigvuldig met 100.
    for (final key in ['price', 'amount']) {
      final v = map[key];
      if (v != null) {
        if (v is int) return v * 100;
        if (v is num) return (v.toDouble() * 100).round();
        final parsed = double.tryParse(v.toString());
        if (parsed != null) return (parsed * 100).round();
      }
    }
    return null;
  }

  Future<void> _openInMaps(String? region) async {
    final q = region?.trim() ?? '';
    if (q.isEmpty) return;
    final encoded = Uri.encodeComponent(q);
    final google = Uri.parse(
      '${AppConfig.googleMapsSearchUrl}$encoded',
    );
    final apple = Uri.parse('${AppConfig.appleMapsSearchUrl}$encoded');
    final openedGoogle = await launchUrl(
      google,
      mode: LaunchMode.externalApplication,
    );
    if (openedGoogle) return;
    final openedApple = await launchUrl(
      apple,
      mode: LaunchMode.externalApplication,
    );
    if (!openedApple && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kon kaarten-app niet openen.')),
      );
    }
  }

  bool _hasTrustSignals(Trainer t) {
    return t.avgResponseMinutes != null ||
        (t.clientsWith5PlusSessions != null && t.clientsWith5PlusSessions! > 0) ||
        (t.totalSessions != null && t.totalSessions! > 0);
  }

  bool _hasSocials(Trainer t) {
    return (t.instagramUrl ?? '').trim().isNotEmpty ||
        (t.snapchatUsername ?? '').trim().isNotEmpty ||
        (t.facebookUrl ?? '').trim().isNotEmpty;
  }

  bool _isProOrHigher(Trainer t) {
    final tier = t.tierNormalized;
    return tier == 'pro' || tier == 'pro_plus' || tier == 'studio';
  }

  String _socialUrl(String raw, String platform) {
    final v = raw.trim();
    if (v.startsWith('http')) return v;
    final handle = v.replaceAll('@', '');
    switch (platform) {
      case 'instagram':
        return 'https://instagram.com/$handle';
      case 'snapchat':
        return 'https://snapchat.com/add/$handle';
      case 'facebook':
        return 'https://facebook.com/$handle';
      default:
        return v;
    }
  }


  /// Parse hex color string (e.g. '#C9A84C') naar Color.
  Color? _parseBrandColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return null;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  // ── Tab content builders ──

  Widget _buildInfoTab() {
    final brandColor = _parseBrandColor(trainer.brandColor);
    final accentColor = brandColor ?? GymiesColors.primary;
    return ListView(
      key: const PageStorageKey('info_tab'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ── Over mij ──
        Text('Over mij', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
        const SizedBox(height: 6),
        if ((trainer.bio ?? '').trim().isNotEmpty)
          Text(trainer.bio!.trim(), style: GoogleFonts.sora(color: Colors.grey.shade700, height: 1.5, fontSize: 13))
        else
          Text('Nog geen bio toegevoegd.', style: GoogleFonts.sora(color: Colors.grey.shade500, fontSize: 13)),

        // ── Intro-aanbieding ──
        if (trainer.hasIntroOffer && (trainer.introOfferDescription ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.local_offer_rounded, size: 18, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text(trainer.introOfferDescription!.trim(), style: GoogleFonts.sora(fontSize: 13, color: Colors.green.shade800, fontWeight: FontWeight.w500))),
              ],
            ),
          ),
        ],

        // ── Specialisaties ──
        if (trainer.specializationsTags.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Specialisaties', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: trainer.specializationsTags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: GymiesColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tag, style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w500, color: GymiesColors.darkBlue)),
            )).toList(),
          ),
        ],

        // ── Beschikbaarheid ──
        if (!_dataLoading) ...[
          const SizedBox(height: 18),
          Text('Beschikbaarheid', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          const SizedBox(height: 8),
          if (availability.isEmpty)
            Text('Nog geen publieke beschikbaarheid.', style: GoogleFonts.sora(color: Colors.grey.shade500, fontSize: 13))
          else ...[
            // Compact day blocks with times for Pro+
            _buildAvailabilityDayBlocks(),
          ],
        ],

        // ── Boeken & betalen compact pill ──
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 15, color: GymiesColors.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  trainer.bookingAdvanceDays != null
                      ? 'Tot ${trainer.bookingAdvanceDays} dgn vooruit'
                      : 'Tot 4 wkn vooruit',
                  style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
              Container(width: 1, height: 14, color: Colors.grey.shade300),
              const SizedBox(width: 8),
              Icon(Icons.payment_rounded, size: 15, color: GymiesColors.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  trainer.paymentMethodLabel.replaceAll('Accepteert ', ''),
                  style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),

        // ── Review preview (Pro+ only) ──
        if (!_dataLoading && trainer.isProPlus && reviews.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Text('Laatste review', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Haptics.selection();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientTrainerReviewsScreen(trainer: trainer)));
                },
                child: Text('Bekijk alle', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Haptics.selection();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientTrainerReviewsScreen(trainer: trainer)));
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _LatestReviewPreview(review: reviews.first),
            ),
          ),
        ],

        if (_dataLoading) ...[
          const SizedBox(height: 16),
          ..._buildLoadingShimmers(),
        ],

        // ── Pricing CTA ──
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: trainer.isProPlus ? GymiesColors.darkBlue : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vanaf', style: GoogleFonts.sora(fontSize: 11, color: trainer.isProPlus ? Colors.white54 : Colors.grey.shade600)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          trainer.hourlyRateCents != null ? '€${(trainer.hourlyRateCents! / 100).toStringAsFixed(0)}' : 'N.t.b.',
                          style: GoogleFonts.sora(fontSize: 24, fontWeight: FontWeight.w700, color: trainer.isProPlus ? accentColor : GymiesColors.darkBlue),
                        ),
                        if (trainer.hourlyRateCents != null)
                          Text('/sessie', style: GoogleFonts.sora(fontSize: 12, color: trainer.isProPlus ? Colors.white54 : Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => DefaultTabController.of(context).animateTo(1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Bekijk pakketten',
                    style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: trainer.isProPlus && brandColor != null ? Colors.white : GymiesColors.darkBlue),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Locatie ──
        if (trainer.region != null && trainer.region!.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Locatie', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          const SizedBox(height: 6),
          Text(trainer.region!.trim(), style: GoogleFonts.sora(color: Colors.grey.shade800, fontSize: 13)),
          const SizedBox(height: 4),
          Text('Online / thuis / gym afhankelijk van afspraak', style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _openInMaps(trainer.region),
            icon: const Icon(Icons.directions_outlined, size: 16),
            label: Text('Plan route', style: GoogleFonts.sora(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: GymiesColors.darkBlue,
              side: BorderSide(color: GymiesColors.darkBlue.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],

        // ── Social icons ──
        if (_hasSocials(trainer) && _isProOrHigher(trainer)) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              if ((trainer.instagramUrl ?? '').trim().isNotEmpty)
                _SocialIconButton(icon: Icons.camera_alt_rounded, color: const Color(0xFFE1306C), url: _socialUrl(trainer.instagramUrl!, 'instagram')),
              if ((trainer.snapchatUsername ?? '').trim().isNotEmpty)
                _SocialIconButton(icon: Icons.chat_bubble_rounded, color: const Color(0xFFFFFC00), bgColor: const Color(0xFFFFFC00), iconColor: Colors.black, url: _socialUrl(trainer.snapchatUsername!, 'snapchat')),
              if ((trainer.facebookUrl ?? '').trim().isNotEmpty)
                _SocialIconButton(icon: Icons.facebook_rounded, color: const Color(0xFF1877F2), url: _socialUrl(trainer.facebookUrl!, 'facebook')),
            ],
          ),
        ],

        // ── Annuleringsbeleid ──
        if (trainer.hasCancellationPolicy) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_busy_rounded, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(trainer.cancellationPolicyLabel ?? 'Annuleringsbeleid', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade900))),
                  ],
                ),
                if ((trainer.cancellationExceptions ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(trainer.cancellationExceptions!.trim(), style: GoogleFonts.sora(fontSize: 12, color: Colors.orange.shade800, height: 1.4)),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        Text('Je ziet hier alleen openbare profielinformatie.', style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildAvailabilityDayBlocks() {
    final weekDays = _availabilityForWeek(availability, weekOffset: 0);
    final dayNames = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];

    return Row(
      children: List.generate(7, (i) {
        final dayData = i < weekDays.length ? weekDays[i] : null;
        final hasSlots = dayData != null && dayData.windows.isNotEmpty;
        final isWeekend = i >= 5;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 6 ? 4 : 0),
            child: Column(
              children: [
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: hasSlots
                        ? (isWeekend ? GymiesColors.primary.withValues(alpha: 0.15) : GymiesColors.darkBlue)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      dayNames[i],
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        fontWeight: hasSlots ? FontWeight.w600 : FontWeight.w400,
                        color: hasSlots
                            ? (isWeekend ? GymiesColors.primary : Colors.white)
                            : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ),
                if (trainer.isProPlus) ...[
                  const SizedBox(height: 3),
                  Text(
                    hasSlots ? dayData!.windows.first.split(' ').first : '-',
                    style: GoogleFonts.sora(fontSize: 8, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPackagesTab() {
    if (_dataLoading) {
      return Center(child: CircularProgressIndicator(color: GymiesColors.primary, strokeWidth: 2.5));
    }
    return ListView(
      key: const PageStorageKey('packages_tab'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ── Tarieven ──
        Text('Tarieven (indicatie)', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(child: Text('Losse sessie')),
            Text(trainer.priceLabel, style: GoogleFonts.sora(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Definitieve prijs bij het boeken.', style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 18),

        // ── Pakketten lijst ──
        Text('Abonnementen & pakketten', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
        const SizedBox(height: 8),
        if (packages.isEmpty)
          Text('Nog geen publieke pakketten.', style: GoogleFonts.sora(color: Colors.grey.shade500, fontSize: 13))
        else
          ...packages.map((p) {
            final name = mapStr(p, ['name', 'title']).isNotEmpty ? mapStr(p, ['name', 'title']) : 'Pakket';
            final sessions = mapStr(p, ['sessions_count', 'sessions', 'count']);
            final weeks = mapStr(p, ['weeks_count', 'weeks']);
            final cents = _priceCents(p);
            final price = cents != null ? '€${(cents / 100).toStringAsFixed(2)}' : 'Prijs op aanvraag';
            final details = [if (sessions.isNotEmpty) '$sessions lessen', if (weeks.isNotEmpty) '$weeks weken'].join(' · ');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GymiesColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GymiesColors.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.fitness_center_rounded, size: 20, color: GymiesColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.sora(fontWeight: FontWeight.w700)),
                        if (details.isNotEmpty) Text(details, style: GoogleFonts.sora(color: Colors.grey.shade700, fontSize: 13)),
                      ],
                    ),
                  ),
                  Text(price, style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: GymiesColors.primary)),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildReviewsTab() {
    if (_dataLoading) {
      return Center(child: CircularProgressIndicator(color: GymiesColors.primary, strokeWidth: 2.5));
    }
    return ListView(
      key: const PageStorageKey('reviews_tab'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Text('Reviews', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
            const Spacer(),
            if (trainer.rating != null)
              Row(
                children: [
                  Icon(Icons.star_rounded, size: 16, color: GymiesColors.primary),
                  const SizedBox(width: 4),
                  Text('${trainer.rating!.toStringAsFixed(1)} (${trainer.reviewCount ?? 0})', style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade700)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (reviews.isEmpty)
          Text('Nog geen reviews beschikbaar.', style: GoogleFonts.sora(color: Colors.grey.shade500, fontSize: 13))
        else ...[
          ...reviews.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
              child: _LatestReviewPreview(review: r),
            ),
          )),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () async {
              Haptics.selection();
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientTrainerReviewsScreen(trainer: trainer)));
            },
            icon: const Icon(Icons.rate_review_outlined, size: 16),
            label: Text('Alle reviews bekijken', style: GoogleFonts.sora(fontSize: 13)),
            style: TextButton.styleFrom(foregroundColor: GymiesColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaTab() {
    if (_dataLoading) {
      return Center(child: CircularProgressIndicator(color: GymiesColors.primary, strokeWidth: 2.5));
    }
    return ListView(
      key: const PageStorageKey('media_tab'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ── Stories ──
        if (storyMedia.isNotEmpty) ...[
          Text('Stories', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: storyMedia.asMap().entries.map((entry) {
                final url = _mediaUrl(entry.value);
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: _openStoryViewer,
                    child: Container(
                      width: 64,
                      height: 80,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: GymiesColors.primary, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: url.isNotEmpty
                            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, errorWidget: (_, _, _) => _mediaPlaceholder(false))
                            : _mediaPlaceholder(false),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
        ],
        // ── Galerij ──
        Text('Galerij', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
        const SizedBox(height: 8),
        if (mediaGallery.isEmpty)
          Text('Nog geen media toegevoegd.', style: GoogleFonts.sora(color: Colors.grey.shade500, fontSize: 13))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: mediaGallery.length,
            itemBuilder: (context, index) {
              final m = mediaGallery[index];
              final url = _mediaUrl(m);
              final isVid = _isVideo(m);
              return GestureDetector(
                onTap: () => _openGalleryViewer(index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: url.trim().isNotEmpty
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, errorWidget: (_, _, _) => _mediaPlaceholder(isVid)),
                            if (isVid) const Center(child: Icon(Icons.play_circle_filled, size: 40, color: Colors.white70)),
                          ],
                        )
                      : _mediaPlaceholder(isVid),
                ),
              );
            },
          ),
      ],
    );
  }

  void _showReportDialog(String trainerId, String trainerName) {
    String? selectedReason;
    final reasons = [
      'Ongepast gedrag',
      'Nep profiel',
      'Spam of misleiding',
      'Onveilige trainingspraktijken',
      'Anders',
    ];
    final detailController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Profiel melden', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Waarom wil je $trainerName melden?', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 12),
                ...reasons.map((r) => RadioListTile<String>(
                  title: Text(r, style: const TextStyle(fontSize: 13)),
                  value: r,
                  groupValue: selectedReason,
                  activeColor: GymiesColors.darkBlue,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (v) => setDialogState(() => selectedReason = v),
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: detailController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Toelichting (optioneel)',
                    hintStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Annuleer', style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      try {
                        final api = _api;
                        await api.createSupportTicket(
                          type: 'report',
                          subject: 'Profiel melding: $trainerName',
                          message: 'Reden: $selectedReason\nTrainer ID: $trainerId\n\nToelichting: ${detailController.text.trim().isEmpty ? '—' : detailController.text.trim()}',
                        );
                      } catch (_) {
                        // Support ticket endpoint might not exist yet
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Bedankt voor je melding. We bekijken dit zo snel mogelijk.'),
                          backgroundColor: GymiesColors.darkBlue,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
              child: const Text('Melden'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trainerName = trainer.displayName.trim().isNotEmpty
        ? trainer.displayName.trim()
        : 'Trainer';
    final brandColor = _parseBrandColor(trainer.brandColor);
    final hasLogo = trainer.isProPlus &&
        trainer.brandLogoUrl != null &&
        trainer.brandLogoUrl!.isNotEmpty;
    final accentColor = brandColor ?? GymiesColors.primary;
    final initials = trainerName.isNotEmpty ? trainerName[0].toUpperCase() : '?';

    final headerColors = brandColor != null && trainer.isProPlus
        ? [brandColor, brandColor.withValues(alpha: 0.85)]
        : [const Color(0xFF1E3A5F), const Color(0xFF2A4F7A)];

    final tabCount = trainer.isProPlus ? 4 : 3;
    final topPad = MediaQuery.of(context).padding.top;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Column(
          children: [
            Expanded(
              child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              floating: false,
              snap: false,
              automaticallyImplyLeading: false,
              expandedHeight: 240 + topPad,
              collapsedHeight: 60,
              toolbarHeight: 60,
              backgroundColor: headerColors.first,
              forceElevated: innerBoxIsScrolled,
              elevation: 2,
              // ── Collapsed title (always visible when scrolled) ──
              title: AnimatedOpacity(
                opacity: innerBoxIsScrolled ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Row(
                  children: [
                    ClipOval(
                      child: _GymiesAvatar(url: trainer.avatarUrl, fallbackName: trainerName, size: 32, fontSize: 11),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(trainerName, style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              // ── Back + more buttons ──
              leading: GestureDetector(
                onTap: () { Haptics.selection(); if (Navigator.of(context).canPop()) Navigator.of(context).pop(); },
                child: Center(
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 16),
                  ),
                ),
              ),
              actions: [
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                              const SizedBox(height: 16),
                              ListTile(
                                leading: const Icon(Icons.share_rounded),
                                title: Text('Profiel delen', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w500)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                onTap: () {
                                  Navigator.pop(context);
                                  final url = 'https://www.gymies.nl/trainer/${trainer.userId}';
                                  SharePlus.instance.share(
                                    ShareParams(
                                      text: 'Bekijk ${trainerName} op Gymies!\n$url',
                                    ),
                                  );
                                },
                              ),
                              ListTile(
                                leading: Icon(Icons.flag_outlined, color: Colors.red.shade400),
                                title: Text('Profiel melden', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.red.shade400)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                onTap: () {
                                  Navigator.pop(context);
                                  _showReportDialog(trainer.userId, trainerName);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              // ── Expanded header content ──
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: headerColors),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Avatar ──
                          Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: trainer.isProPlus ? SweepGradient(colors: [accentColor, accentColor.withValues(alpha: 0.6), accentColor]) : null,
                              border: !trainer.isProPlus ? Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2.5) : null,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: ClipOval(
                              child: _GymiesAvatar(url: trainer.avatarUrl, fallbackName: trainerName, size: 64, fontSize: 24),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // ── Name ──
                          Text(trainerName, style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          // ── Subtitle: specialty + region ──
                          Text(
                            [
                              if (trainer.specialty != null && trainer.specialty!.trim().isNotEmpty) trainer.specialty!.trim(),
                              if (trainer.region != null && trainer.region!.trim().isNotEmpty) trainer.region!.trim(),
                            ].join(' · '),
                            style: GoogleFonts.sora(fontSize: 12, color: Colors.white.withValues(alpha: 0.65)),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 14),
                          // ── Badges + rating row ──
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (trainer.trainerVerified)
                                _headerBadge('Geverifieerd', GymiesColors.primary.withValues(alpha: 0.2), GymiesColors.primary, icon: Icons.verified_rounded),
                              if (trainer.rating != null)
                                _headerBadge('${trainer.rating!.toStringAsFixed(1)} ★ (${trainer.reviewCount ?? 0})', Colors.white.withValues(alpha: 0.12), Colors.white),
                              if (trainer.isProPlus)
                                _headerBadge('PRO+', const Color(0xFF5DCAA5).withValues(alpha: 0.2), const Color(0xFF5DCAA5))
                              else if (_isProOrHigher(trainer))
                                _headerBadge('PRO', Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.8)),
                              if (hasLogo)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CachedNetworkImage(imageUrl: trainer.brandLogoUrl!, width: 24, height: 24, fit: BoxFit.contain, errorWidget: (_, __, ___) => const SizedBox.shrink()),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // ── Tab bar at the bottom of the header ──
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Material(
                  color: Colors.white,
                  child: TabBar(
                    labelStyle: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w400),
                    labelColor: GymiesColors.darkBlue,
                    unselectedLabelColor: Colors.grey.shade500,
                    indicatorColor: accentColor,
                    indicatorWeight: 2.5,
                    dividerColor: Colors.grey.shade200,
                    tabs: [
                      const Tab(text: 'Info'),
                      const Tab(text: 'Pakketten'),
                      const Tab(text: 'Reviews'),
                      if (trainer.isProPlus) const Tab(text: 'Media'),
                    ],
                  ),
                ),
              ),
            ),
          ],
          // ── Tab content ──
          body: TabBarView(
            children: [
              _buildInfoTab(),
              _buildPackagesTab(),
              _buildReviewsTab(),
              if (trainer.isProPlus) _buildMediaTab(),
            ],
          ),
        ),
            ),
            // ── Fixed bottom action buttons (veilig buiten NestedScrollView) ──
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: GymiesColors.darkBlue.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -3))],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        if (widget.onBookTap != null) { if (Navigator.of(context).canPop()) Navigator.of(context).pop(); widget.onBookTap!(); }
                        else { if (Navigator.of(context).canPop()) Navigator.of(context).pop('book'); }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(14)),
                        child: Center(child: Text('Boek nu', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: trainer.isProPlus && brandColor != null ? Colors.white : GymiesColors.darkBlue))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        if (widget.onChatTap != null) { if (Navigator.of(context).canPop()) Navigator.of(context).pop(); widget.onChatTap!(); }
                        else { if (Navigator.of(context).canPop()) Navigator.of(context).pop('chat'); }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: GymiesColors.darkBlue, width: 1.5)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 18, color: GymiesColors.darkBlue),
                            const SizedBox(width: 6),
                            Text('Bericht', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header helper widgets ──

  Widget _headerBadge(String label, Color bg, Color textColor, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 3),
          ],
          Text(label, style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w500, color: textColor)),
        ],
      ),
    );
  }

  Widget _headerStat(String value, String label, {bool isAccent = false, Color? accentColor}) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700, color: isAccent ? (accentColor ?? GymiesColors.primary) : Colors.white)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.sora(fontSize: 10, color: Colors.white.withValues(alpha: 0.45), letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _LatestReviewPreview extends StatelessWidget {
  const _LatestReviewPreview({required this.review});

  final Map<String, dynamic> review;

  String _str(List<String> keys) {
    for (final k in keys) {
      final v = review[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }

  int _intFromReview(List<String> keys) {
    final v = _str(keys);
    return int.tryParse(v) ?? 0;
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return raw;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final rating = _intFromReview(['rating']);
    final message = _str(['message', 'body', 'text']);
    final isAnonymous = review['is_anonymous'] == true;
    final displayName = isAnonymous ? 'Anoniem' : (_str(['client_name', 'clientName', 'author']).isEmpty ? 'Anoniem' : _str(['client_name', 'clientName', 'author']));
    final createdAt = _str(['created_at', 'createdAt', 'date']);
    final displayText = message.length > 120 ? '${message.substring(0, 120)}...' : message;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ...List.generate(5, (i) {
                final star = i + 1;
                return Icon(
                  star <= rating ? Icons.star_rounded : Icons.star_border_rounded,
                  color: Colors.amber,
                  size: 18,
                );
              }),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: GymiesColors.darkBlue,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (createdAt.isNotEmpty)
                Text(
                  _formatDate(createdAt),
                  style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          if (displayText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              displayText,
              style: GoogleFonts.sora(
                color: Colors.grey.shade800,
                fontSize: 13,
                height: 1.35,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
          ],
        ],
      ),
    );
  }
}

class _PublicProfileStoryRing extends StatelessWidget {
  const _PublicProfileStoryRing({
    required this.imageUrl,
    required this.fallbackName,
    this.hasStory = false,
  });

  final String? imageUrl;
  final String fallbackName;
  final bool hasStory;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                GymiesColors.primary,
                hasStory ? Colors.orange.shade400 : Colors.orange.shade300,
              ],
            ),
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: _GymiesAvatar(
                url: imageUrl,
                fallbackName: fallbackName,
                size: 50,
                bgColor: GymiesColors.primary.withValues(alpha: 0.2),
                textColor: GymiesColors.darkBlue,
              ),
            ),
          ),
        ),
        if (hasStory)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: GymiesColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: GymiesColors.darkBlue,
                size: 16,
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-screen story/gallery viewer met 10 sec progressie per item (stories) of swipe (gallery).
class _StoryViewerScreen extends StatefulWidget {
  const _StoryViewerScreen({
    required this.trainer,
    required this.items,
    required this.urlOf,
    required this.isVideo,
    this.initialIndex = 0,
  });

  final Trainer trainer;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) urlOf;
  final bool Function(Map<String, dynamic>) isVideo;
  final int initialIndex;

  @override
  State<_StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<_StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _index;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _progressController = AnimationController(
      vsync: this,
      duration: TimingConstants.bookingTimeout,
    )..addListener(() => setState(() {}));
    _progressController.forward();
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextOrPop();
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _nextOrPop() {
    if (_index + 1 < widget.items.length) {
      setState(() {
        _index += 1;
        _progressController.reset();
        _progressController.forward();
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final url = widget.urlOf(item);
    final isVideo = widget.isVideo(item);
    final trainerName = widget.trainer.displayName.trim().isNotEmpty
        ? widget.trainer.displayName.trim()
        : 'Trainer';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: List.generate(widget.items.length, (i) {
                  final progress = i < _index
                      ? 1.0
                      : i == _index
                          ? _progressController.value
                          : 0.0;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: url.trim().isEmpty
                            ? Center(
                                child: Icon(
                                  isVideo ? Icons.videocam : Icons.photo,
                                  size: 64,
                                  color: Colors.white54,
                                ),
                              )
                            : isVideo
                                ? _VideoStoryContent(url: url)
                                : CachedNetworkImage(
                                    imageUrl: url,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        size: 64,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Row(
                      children: [
                        ClipOval(
                          child: _GymiesAvatar(
                            url: widget.trainer.avatarUrl,
                            fallbackName: trainerName,
                            size: 40,
                            bgColor: GymiesColors.primary,
                            textColor: GymiesColors.darkBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          trainerName,
                          style: GoogleFonts.sora(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Trust signal stat — compact icoon + waarde + label
class _TrustStat extends StatelessWidget {
  const _TrustStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: GymiesColors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: GymiesColors.darkBlue,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

// Social media icoon-knop — compact rond icoon in de header
class _SocialIconButton extends StatelessWidget {
  const _SocialIconButton({
    required this.icon,
    required this.color,
    required this.url,
    this.bgColor,
    this.iconColor,
  });

  final IconData icon;
  final Color color;
  final String url;
  final Color? bgColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (bgColor ?? color).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: iconColor ?? color),
        ),
      ),
    );
  }
}

class _VideoStoryContent extends StatelessWidget {
  const _VideoStoryContent({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => const Center(
            child: Icon(Icons.videocam_off, size: 64, color: Colors.white54),
          ),
        ),
        const Center(
          child: Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
        ),
      ],
    );
  }
}
