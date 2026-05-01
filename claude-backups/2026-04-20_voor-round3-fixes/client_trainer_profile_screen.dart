import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/trainer.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../config/app_config.dart';
import '../config/timing_constants.dart';
import '../utils/map_utils.dart';
import '../utils/trainer_badges.dart';
import 'client_messages_screen.dart';
import 'client_trainer_reviews_screen.dart';
import 'widgets/gymies_app_bar.dart';

class _AvailabilityDayView {
  const _AvailabilityDayView({required this.date, required this.windows});

  final DateTime date;
  final List<String> windows;
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
              return '$start - $end';
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

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.focusBookingForm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBookingForm();
      });
    }
  }

  @override
  void dispose() {
    _slotHoldTicker?.cancel();
    _noteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    Trainer? baseTrainer = widget.trainer;
    try {
      final api = context.read<GymiesApi>();
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
      final detail = await api.getTrainerById(baseTrainer.userId);
      final packages = await api.getTrainerPublicPackages(
        baseTrainer.userId,
      );
      final availability = await api.getTrainerPublicAvailability(
        baseTrainer.userId,
      );
      List<Map<String, dynamic>> mediaGallery = [];
      List<Map<String, dynamic>> storyMedia = [];
      try {
        final mediaRes = await api.getTrainerPublicMedia(baseTrainer.userId);
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
      } catch (_) {}
      List<Map<String, dynamic>> reviews = [];
      try {
        final revRes = await api.getTrainerReviews(baseTrainer.userId);
        final raw = revRes['data'];
        if (raw is List) {
          reviews = raw.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
        }
      } catch (_) {}
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
    final v = mapPick(map, ['price_cents', 'amount_cents', 'price', 'amount']);
    if (v is int) return v;
    if (v is num) {
      final value = v.toDouble();
      if (value > 1000) return value.toInt();
      return (value * 100).toInt();
    }
    return int.tryParse(v?.toString() ?? '');
  }

  String _formatPrice(int? cents) {
    if (cents == null) return 'Prijs op aanvraag';
    return '€${(cents / 100).toStringAsFixed(0)}';
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
    return (slot['start_time'] ?? slot['startTime'] ?? '').toString().trim();
  }

  String _slotEnd(Map<String, dynamic> slot) {
    return (slot['end_time'] ?? slot['endTime'] ?? '').toString().trim();
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
    final parts = start.split(':');
    final hh = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final mm = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      hh,
      mm,
    );
  }

  List<Map<String, dynamic>> _slotsForSelectedDate() {
    final selectedDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final list = _availability.where((slot) {
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
      return _slotStart(slot).isNotEmpty;
    }).toList();
    list.sort((a, b) => _slotStart(a).compareTo(_slotStart(b)));
    return list;
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
      final hold = await context.read<GymiesApi>().holdTrainerPublicSlot(
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
    setState(() => _booking = true);
    try {
      final dt = _slotDateTime(slot, _selectedDate);
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
      await context.read<GymiesApi>().createDirectBooking(
        trainerUserId: trainer.userId,
        scheduledAt: dt,
        packageId: _selectedPackageId,
        note: _noteController.text.trim(),
        availabilitySlotId: _slotId(slot),
        holdId: holdId,
        holdToken: holdToken,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Boeking succesvol aangemaakt'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Boeking mislukt. Probeer opnieuw.');
    } finally {
      if (mounted) setState(() => _booking = false);
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
      await context.read<GymiesApi>().joinTrainerWaitlist(
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
      final c = await context.read<GymiesApi>().ensureClientConversation(
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientPublicTrainerProfileScreen(
          trainer: trainer,
          packages: _packages,
          availability: _availability,
          mediaGallery: _mediaGallery,
          storyMedia: _storyMedia,
          reviews: _reviews,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trainer = _trainer ?? widget.trainer;
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: const GymiesAppBar(title: 'Trainer'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (trainer == null) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: const GymiesAppBar(title: 'Trainer'),
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
                  style: TextStyle(color: Colors.grey.shade800),
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
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(title: trainer.nameOrEmail),
      floatingActionButton: (!widget.showFullProfileOnly && !widget.isFromMyTrainers)
          ? FloatingActionButton.extended(
              onPressed: _scrollToBookingForm,
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Boek Nu'),
              elevation: 4,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: RefreshIndicator(
              onRefresh: _load,
              color: GymiesColors.primary,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Card(
                      color: Colors.red.shade50,
                      child: ListTile(
                        leading: const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                        ),
                        title: Text(_error!),
                      ),
                    ),
                  Card(
                    child: InkWell(
                      onTap: widget.isFromMyTrainers
                          ? () => _openFullPublicProfile(trainer)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: GymiesColors.primary.withValues(
                            alpha: 0.2,
                          ),
                          backgroundImage:
                              trainer.avatarUrl != null &&
                                  trainer.avatarUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(trainer.avatarUrl!)
                              : null,
                          child:
                              trainer.avatarUrl == null ||
                                  trainer.avatarUrl!.isEmpty
                              ? Text(
                                  trainer.nameOrEmail[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: GymiesColors.darkBlue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                        title: Text(trainer.nameOrEmail),
                        subtitle: Text(
                          [
                                trainer.specialty,
                                trainer.region,
                                if (trainer.rating != null)
                                  '⭐ ${trainer.rating!.toStringAsFixed(1)}',
                              ]
                              .whereType<String>()
                              .where((e) => e.isNotEmpty)
                              .join(' • '),
                        ),
                        trailing: widget.isFromMyTrainers
                            ? const Icon(Icons.open_in_new_rounded)
                            : null,
                      ),
                    ),
                  ),
                  if (widget.isFromMyTrainers) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onRemoveFromMyTrainers,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                        ),
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Verwijder uit mijn trainers'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                  if (!widget.focusBookingForm && !widget.isFromMyTrainers) ...[
                    Text(
                      'Eerst meer weten over deze trainer? Bekijk het volledige profiel.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _booking ? null : _scrollToBookingForm,
                            style: FilledButton.styleFrom(
                              backgroundColor: GymiesColors.primary,
                              foregroundColor: GymiesColors.darkBlue,
                            ),
                            icon: const Icon(Icons.event_available_rounded),
                            label: const Text('Boek sessie'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openFullPublicProfile(trainer),
                            icon: const Icon(Icons.open_in_full_rounded),
                            label: const Text('Bekijk volledig profiel'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Card(
                    key: _bookingCardKey,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Boek sessie',
                            style: GoogleFonts.fjallaOne(
                              fontSize: 18,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _usePackage = false;
                                    _selectedPackageId = null;
                                  }),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: !_usePackage
                                          ? GymiesColors.primary.withValues(alpha: 0.15)
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: !_usePackage
                                            ? GymiesColors.primary
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Losse sessie',
                                          style: GoogleFonts.fjallaOne(
                                            fontSize: 15,
                                            color: GymiesColors.darkBlue,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          trainer.hourlyRateCents != null
                                              ? _formatPrice(trainer.hourlyRateCents)
                                              : 'Prijs op aanvraag',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: GymiesColors.darkBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (_packages.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => setState(() {
                                      _usePackage = true;
                                      _selectedPackageId = _packages.isNotEmpty
                                          ? mapStr(_packages.first, ['id', 'package_id', 'packageId'])
                                          : null;
                                    }),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: _usePackage
                                            ? GymiesColors.primary.withValues(alpha: 0.15)
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: _usePackage
                                              ? GymiesColors.primary
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Pakket',
                                            style: GoogleFonts.fjallaOne(
                                              fontSize: 15,
                                              color: GymiesColors.darkBlue,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _selectedPackageMap() != null
                                                ? _formatPrice(_priceCents(_selectedPackageMap()!))
                                                : (_packages.isNotEmpty
                                                    ? _formatPrice(_priceCents(_packages.first))
                                                    : 'Prijs op aanvraag'),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: GymiesColors.darkBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_packages.isNotEmpty) const SizedBox(height: 10),
                          if (_usePackage && _packages.isNotEmpty)
                            DropdownButtonFormField<String>(
                              key: ValueKey(_selectedPackageId ?? ''),
                              initialValue: _selectedPackageId ?? mapStr(_packages.first, ['id', 'package_id', 'packageId']),
                              decoration: const InputDecoration(
                                labelText: 'Kies pakket',
                              ),
                              items: _packages
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: mapStr(p, [
                                        'id',
                                        'package_id',
                                        'packageId',
                                      ]),
                                      child: Text(
                                        '${mapStr(p, ['name', 'title']).isNotEmpty ? mapStr(p, ['name', 'title']) : 'Pakket'} - ${_formatPrice(_priceCents(p))}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedPackageId = v),
                            ),
                          if (_usePackage && _packages.isNotEmpty) const SizedBox(height: 10),
                          if (_usePackage && _packages.isNotEmpty) ...[
                            Builder(
                              builder: (_) {
                                final selected = _selectedPackageMap();
                                final sessions = _toInt(
                                  selected == null
                                      ? null
                                      : mapPick(selected, [
                                          'sessions_count',
                                          'sessions',
                                          'lessons_count',
                                        ]),
                                );
                                if (sessions == null || sessions <= 0) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Pakketverbruik: dit pakket bevat $sessions sessies.',
                                    style: TextStyle(
                                      color: Colors.blue.shade900,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Datum'),
                            subtitle: Text(
                              '${_selectedDate.day.toString().padLeft(2, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.year}',
                            ),
                            trailing: const Icon(Icons.calendar_month_outlined),
                            onTap: _pickDate,
                          ),
                          const SizedBox(height: 6),
                          Builder(
                            builder: (_) {
                              final daySlots = _slotsForSelectedDate();
                              if (daySlots.isEmpty) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Geen beschikbare slots op deze dag. Kies een andere dag.',
                                    style: TextStyle(
                                      color: Colors.orange.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Beschikbare slots',
                                    style: GoogleFonts.fjallaOne(
                                      fontSize: 15,
                                      color: GymiesColors.darkBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: daySlots.map((slot) {
                                      final label =
                                          '${_slotStart(slot)} - ${_slotEnd(slot)}';
                                      final selected =
                                          identical(_selectedSlot, slot) ||
                                          (_slotStart(_selectedSlot ?? {}) ==
                                                  _slotStart(slot) &&
                                              _slotEnd(_selectedSlot ?? {}) ==
                                                  _slotEnd(slot));
                                      return ChoiceChip(
                                        selected: selected,
                                        label: Text(label),
                                        onSelected: (_) => _selectSlot(slot),
                                      );
                                    }).toList(),
                                  ),
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
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          TextField(
                            controller: _noteController,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Notitie (optioneel)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _booking ? null : _bookSession,
                              style: FilledButton.styleFrom(
                                backgroundColor: GymiesColors.primary,
                                foregroundColor: GymiesColors.darkBlue,
                              ),
                              icon: const Icon(Icons.event_available_rounded),
                              label: Text(_booking ? 'Bezig...' : 'Boek nu'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _booking ? null : _joinWaitlist,
                              icon: const Icon(
                                Icons.notifications_active_outlined,
                              ),
                              label: const Text('Standby-lijst'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.chat_bubble_outline_rounded),
                      title: const Text('Stuur bericht'),
                      subtitle: const Text(
                        'Open direct een chat met deze trainer',
                      ),
                      trailing: FilledButton(
                        onPressed: _openingChat ? null : _openChat,
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                        ),
                        child: Text(_openingChat ? 'Bezig...' : 'Open chat'),
                      ),
                    ),
                  ),
                  if (_availability.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Beschikbaarheid',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 18,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._availabilityForWeek(_availability, weekOffset: 0)
                        .where((d) => d.windows.isNotEmpty)
                        .take(7)
                        .map(
                          (day) => Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.calendar_today_outlined,
                              ),
                              title: Text(
                                '${day.date.day.toString().padLeft(2, '0')}-${day.date.month.toString().padLeft(2, '0')}',
                              ),
                              subtitle: Text(day.windows.join(' · ')),
                            ),
                          ),
                        ),
                    const SizedBox(height: 6),
                    Text(
                      'Volgende week',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._availabilityForWeek(_availability, weekOffset: 1)
                        .where((d) => d.windows.isNotEmpty)
                        .take(7)
                        .map(
                          (day) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.event_repeat_outlined),
                              title: Text(
                                '${day.date.day.toString().padLeft(2, '0')}-${day.date.month.toString().padLeft(2, '0')}',
                              ),
                              subtitle: Text(day.windows.join(' · ')),
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
    );
  }
}

class ClientPublicTrainerProfileScreen extends StatefulWidget {
  const ClientPublicTrainerProfileScreen({
    super.key,
    required this.trainer,
    required this.packages,
    required this.availability,
    this.mediaGallery = const [],
    this.storyMedia = const [],
    this.reviews = const [],
  });

  final Trainer trainer;
  final List<Map<String, dynamic>> packages;
  final List<Map<String, dynamic>> availability;
  final List<Map<String, dynamic>> mediaGallery;
  final List<Map<String, dynamic>> storyMedia;
  final List<Map<String, dynamic>> reviews;

  @override
  State<ClientPublicTrainerProfileScreen> createState() =>
      _ClientPublicTrainerProfileScreenState();
}

class _ClientPublicTrainerProfileScreenState
    extends State<ClientPublicTrainerProfileScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _keyAbout = GlobalKey();
  final GlobalKey _keyPackages = GlobalKey();
  final GlobalKey _keyPricing = GlobalKey();
  final GlobalKey _keyLocation = GlobalKey();
  final GlobalKey _keyAvailability = GlobalKey();
  final GlobalKey _keyReviews = GlobalKey();

  Trainer get trainer => widget.trainer;
  List<Map<String, dynamic>> get packages => widget.packages;
  List<Map<String, dynamic>> get availability => widget.availability;
  List<Map<String, dynamic>> get mediaGallery => widget.mediaGallery;
  List<Map<String, dynamic>> get storyMedia => widget.storyMedia;
  List<Map<String, dynamic>> get reviews => widget.reviews;

  final GlobalKey _keyMedia = GlobalKey();
  final GlobalKey _keyStories = GlobalKey();

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
    final v = mapPick(map, ['price_cents', 'amount_cents', 'price', 'amount']);
    if (v is int) return v;
    if (v is num) {
      final value = v.toDouble();
      if (value > 1000) return value.toInt();
      return (value * 100).toInt();
    }
    final parsed = int.tryParse(v?.toString() ?? '');
    return parsed;
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

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  Widget _publicNavChip(String label, IconData icon, GlobalKey key) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: GymiesColors.darkBlue),
        label: Text(label),
        onPressed: () => _scrollToSection(key),
      ),
    );
  }

  Widget _publicNavChipReviews() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(Icons.star_outline, size: 18, color: GymiesColors.darkBlue),
        label: const Text('Reviews'),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ClientTrainerReviewsScreen(trainer: trainer),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trainerName = trainer.displayName.trim().isNotEmpty
        ? trainer.displayName.trim()
        : 'Trainer';
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(title: trainerName),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          KeyedSubtree(
            key: _keyStories,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: storyMedia.isNotEmpty ? _openStoryViewer : null,
                          child: _PublicProfileStoryRing(
                          imageUrl: trainer.avatarUrl,
                          fallbackName: trainerName,
                          hasStory: storyMedia.isNotEmpty,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trainerName,
                              style: GoogleFonts.fjallaOne(
                                fontSize: 20,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              trainer.rating != null
                                  ? '⭐ ${trainer.rating!.toStringAsFixed(1)} (${trainer.reviewCount ?? 0} reviews)'
                                  : 'Nog geen reviews',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            if (trainer.specialty != null &&
                                trainer.specialty!.trim().isNotEmpty)
                              Text(
                                trainer.specialty!.trim(),
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            if (trainer.region != null &&
                                trainer.region!.trim().isNotEmpty)
                              Text(
                                trainer.region!.trim(),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: TrainerBadges.all(trainer)
                          .map((b) => TrainerBadgePill(badge: b))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (storyMedia.isNotEmpty)
                  _publicNavChip('Stories', Icons.auto_stories_rounded, _keyStories),
                if (mediaGallery.isNotEmpty)
                  _publicNavChip('Galerij', Icons.photo_library_rounded, _keyMedia),
                _publicNavChip('Over mij', Icons.person_outline, _keyAbout),
                _publicNavChip(
                  'Pakketten',
                  Icons.loyalty_outlined,
                  _keyPackages,
                ),
                _publicNavChip(
                  'Tarieven',
                  Icons.receipt_long_outlined,
                  _keyPricing,
                ),
                _publicNavChip('Locatie', Icons.map_outlined, _keyLocation),
                _publicNavChip(
                  'Beschikbaarheid',
                  Icons.schedule_outlined,
                  _keyAvailability,
                ),
                _publicNavChipReviews(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _keyAbout,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Over deze trainer',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 18,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (trainer.specialty != null &&
                            trainer.specialty!.trim().isNotEmpty)
                          'Specialisatie: ${trainer.specialty!.trim()}',
                        if (trainer.region != null &&
                            trainer.region!.trim().isNotEmpty)
                          'Regio: ${trainer.region!.trim()}',
                      ].join('\n'),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (mediaGallery.isNotEmpty) ...[
            const SizedBox(height: 10),
            KeyedSubtree(
              key: _keyMedia,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Galerij',
                        style: GoogleFonts.fjallaOne(
                          fontSize: 18,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.zero,
                          clipBehavior: Clip.none,
                          children: [
                            ...mediaGallery.map((m) {
                              final url = _mediaUrl(m);
                              final isVid = _isVideo(m);
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: GestureDetector(
                                  onTap: () => _openGalleryViewer(
                                    mediaGallery.indexOf(m),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 160,
                                      height: 200,
                                      child: url.trim().isNotEmpty
                                          ? Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                CachedNetworkImage(
                                                  imageUrl: url,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, _, _) =>
                                                      _mediaPlaceholder(isVid),
                                                ),
                                                if (isVid)
                                                  const Center(
                                                    child: Icon(
                                                      Icons.play_circle_filled,
                                                      size: 56,
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                              ],
                                            )
                                          : _mediaPlaceholder(isVid),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _keyPricing,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tarieven (indicatie)',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 18,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(child: Text('Losse sessie')),
                        Text(
                          trainer.priceLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Prijsindicatie. Definitieve prijs wordt bevestigd bij het boeken.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Boeken & betalen',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 20, color: GymiesColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trainer.bookingAdvanceDays != null
                              ? 'Boeken tot ${trainer.bookingAdvanceDays} dagen van tevoren'
                              : 'Boeken tot 4 weken van tevoren',
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.payment_rounded, size: 20, color: GymiesColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trainer.paymentMethodLabel,
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _keyPackages,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Abonnementen & pakketten',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 18,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (packages.isEmpty)
                      Text(
                        'Nog geen publieke pakketten toegevoegd.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else
                      ...packages.map((p) {
                        final name = mapStr(p, ['name', 'title']).isNotEmpty
                            ? mapStr(p, ['name', 'title'])
                            : 'Pakket';
                        final sessions = mapStr(p, [
                          'sessions_count',
                          'sessions',
                          'count',
                        ]);
                        final weeks = mapStr(p, ['weeks_count', 'weeks']);
                        final cents = _priceCents(p);
                        final price = cents != null
                            ? '€${(cents / 100).toStringAsFixed(0)}'
                            : 'Prijs op aanvraag';
                        final details = [
                          if (sessions.isNotEmpty) '$sessions lessen',
                          if (weeks.isNotEmpty) '$weeks weken',
                        ].join(' • ');
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (details.isNotEmpty)
                                      Text(
                                        details,
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                price,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: GymiesColors.primary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _keyLocation,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Locatie',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 18,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (trainer.region == null ||
                        trainer.region!.trim().isEmpty)
                      Text(
                        'Regio nog niet ingevuld.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else ...[
                      Text(
                        trainer.region!.trim(),
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Online / thuis / gym afhankelijk van afspraak',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _openInMaps(trainer.region),
                        icon: const Icon(Icons.directions_outlined),
                        label: const Text('Plan route'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _keyAvailability,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beschikbaarheid',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 18,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (availability.isEmpty)
                      Text(
                        'Nog geen publieke beschikbaarheid toegevoegd.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else ...[
                      Text(
                        'Deze week',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._availabilityForWeek(availability, weekOffset: 0)
                          .where((d) => d.windows.isNotEmpty)
                          .map(
                            (day) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.calendar_today_outlined,
                              ),
                              title: Text(
                                '${day.date.day.toString().padLeft(2, '0')}-${day.date.month.toString().padLeft(2, '0')}',
                              ),
                              subtitle: Text(day.windows.join(' · ')),
                            ),
                          ),
                      const SizedBox(height: 6),
                      Text(
                        'Volgende week',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._availabilityForWeek(availability, weekOffset: 1)
                          .where((d) => d.windows.isNotEmpty)
                          .map(
                            (day) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.event_repeat_outlined),
                              title: Text(
                                '${day.date.day.toString().padLeft(2, '0')}-${day.date.month.toString().padLeft(2, '0')}',
                              ),
                              subtitle: Text(day.windows.join(' · ')),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _keyReviews,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Reviews',
                            style: GoogleFonts.fjallaOne(
                              fontSize: 18,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                        ),
                        if (trainer.rating != null)
                          Text(
                            '⭐ ${trainer.rating!.toStringAsFixed(1)} (${trainer.reviewCount ?? 0})',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (reviews.isEmpty)
                      Text(
                        'Nog geen reviews beschikbaar.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else ...[
                      _LatestReviewPreview(review: reviews.first),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ClientTrainerReviewsScreen(trainer: trainer),
                            ),
                          );
                        },
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text('Meer'),
                        style: TextButton.styleFrom(
                          foregroundColor: GymiesColors.primary,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Je ziet hier alleen openbare profielinformatie van deze trainer.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
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
                  style: const TextStyle(
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          if (displayText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              displayText,
              style: TextStyle(
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
            child: CircleAvatar(
              radius: 25,
              backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
              backgroundImage: hasImage ? CachedNetworkImageProvider(imageUrl!.trim()) : null,
              child: !hasImage
                  ? Text(
                      fallbackName.isNotEmpty
                          ? fallbackName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: GymiesColors.darkBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
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
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: GymiesColors.primary,
                          backgroundImage:
                              widget.trainer.avatarUrl != null &&
                                      widget.trainer.avatarUrl!.isNotEmpty
                                  ? CachedNetworkImageProvider(widget.trainer.avatarUrl!)
                                  : null,
                          child:
                              widget.trainer.avatarUrl == null ||
                                      widget.trainer.avatarUrl!.isEmpty
                                  ? Text(
                                      trainerName.isNotEmpty
                                          ? trainerName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: GymiesColors.darkBlue,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          trainerName,
                          style: const TextStyle(
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
                      icon: const Icon(Icons.close, color: Colors.white),
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
