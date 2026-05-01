import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/gymies_theme.dart';
import '../models/trainer.dart';
import '../utils/trainer_badges.dart';
import '../models/booking.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../services/notification_realtime_service.dart';
import '../services/api_client.dart';
import '../utils/map_utils.dart';
import 'login_register_screen.dart';
import 'trainer_dashboard_screen.dart';
import 'client_invoices_screen.dart';
import 'client_messages_screen.dart';
import 'client_notifications_screen.dart';
import 'client_check_in_qr_screen.dart';
import 'client_sessions_screen.dart';
import 'client_trainer_profile_screen.dart';
import 'client_favorites_screen.dart';
import 'client_group_session_detail_screen.dart';
import 'client_my_group_sessions_screen.dart';
import 'widgets/trainer_state_views.dart';
import '../config/app_config.dart';
import '../config/timing_constants.dart';
import '../config/ui_constants.dart';

const _kFavoritesKey = 'gymies_favorite_trainer_ids';
const _kRemovedFromMyTrainersKey = 'gymies_removed_from_my_trainers_ids';
const _kClientCityKey = 'gymies_client_city';

/// Klant-dashboard met GYMIES thema.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _query = TextEditingController();
  List<Trainer> _trainers = [];
  List<Trainer> _filtered = [];
  List<Booking> _bookings = [];
  Set<String> _favoriteIds = {};
  Set<String> _removedFromMyTrainersIds = {};
  bool _loading = false;
  String? _error;
  // Filters
  String? _selectedRegion;
  String? _selectedSpecialty;
  int? _maxDistanceKm;
  int _maxPrice = 0; // 0 = geen limiet, toont alle trainers
  double _minRating = 0;
  String _sortOption = 'city';
  String? _clientCity;
  double? _userLat;
  double? _userLng;
  bool _verifiedOnly = false;
  bool _woman2womanOnly = false;
  String? _selectedLessonType;
  Timer? _clockTicker;

  // Group sessions tab
  bool _showGroupSessions = false;
  List<Map<String, dynamic>> _groupSessions = [];
  bool _groupSessionsLoading = false;
  String? _groupSessionsError;

  static const int _itemsPerPage = TimingConstants.itemsPerPage;
  int _currentPage = 1;

  NotificationRealtimeService? _realtime({bool listen = false}) {
    try {
      return Provider.of<NotificationRealtimeService>(context, listen: listen);
    } catch (e) {
      // Intentional silent catch for realtime helper
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    if (auth.isTrainer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TrainerDashboardScreen()),
        );
      });
      return;
    }
    _startClockTicker();
    _loadFavorites();
    _load();
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _startClockTicker() {
    _clockTicker?.cancel();
    _clockTicker = Timer.periodic(TimingConstants.clockTickInterval, (_) {
      if (!mounted) return;
      setState(() {
        // Trigger countdown refresh for check-in availability text.
      });
    });
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kFavoritesKey) ?? [];
    final removed = prefs.getStringList(_kRemovedFromMyTrainersKey) ?? [];
    final city = prefs.getString(_kClientCityKey);
    if (mounted) {
      setState(() {
        _favoriteIds = list.toSet();
        _removedFromMyTrainersIds = removed.toSet();
        _clientCity = city?.trim().isNotEmpty == true ? city!.trim() : null;
      });
    }
  }

  void _setClientCity(String? city) {
    setState(() => _clientCity = city?.trim().isNotEmpty == true ? city!.trim() : null);
    if (city != null && city.trim().isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(_kClientCityKey, city.trim());
      });
    }
  }

  Future<void> _removeFromMyTrainers(Trainer trainer) async {
    final id = trainer.userId;
    if (id.isEmpty) return;
    setState(() => _removedFromMyTrainersIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kRemovedFromMyTrainersKey,
      _removedFromMyTrainersIds.toList(),
    );
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kFavoritesKey, _favoriteIds.toList());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    final api = context.read<GymiesApi>();
    final apiClient = context.read<ApiClient>();

    // Cruciaal: synchroniseer token van auth naar ApiClient vóór eerste request
    if (auth.isLoggedIn && auth.token != null && auth.token!.isNotEmpty) {
      apiClient.setAuthToken(auth.token);
    }

    List<Trainer> trainers = [];
    List<Booking> bookings = [];
    int unreadCount = 0;

    double? lat;
    double? lng;
    String? gpsCity;
    try {
      final perm = await Permission.location.request();
      if (perm.isGranted) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        lat = pos.latitude;
        lng = pos.longitude;
        if (mounted) {
          setState(() {
            _userLat = lat;
            _userLng = lng;
          });
        }
        try {
          final places = await placemarkFromCoordinates(lat, lng);
          if (places.isNotEmpty) {
            final p = places.first;
            gpsCity = (p.locality ?? p.administrativeArea ?? p.subAdministrativeArea ?? '')
                .trim();
            if (gpsCity.isNotEmpty && mounted) _setClientCity(gpsCity);
          }
        } catch (e) {
          debugPrint('[Dashboard] Geolocation city lookup fout: $e');
        }
      }
    } catch (e) {
      debugPrint('[Dashboard] Geolocation initialization fout: $e');
    }

    try {
      final query = _query.text.trim().isEmpty ? null : _query.text.trim();
      trainers = await api.getTrainers(query: query, lat: lat, lng: lng);
      if (auth.isLoggedIn) {
        try {
          bookings = await api.getBookings();
        } on ApiException catch (e) {
          if (e.statusCode == 401) rethrow;
          bookings = [];
        } catch (e) {
          debugPrint('[Dashboard] Bookings laden fout: $e');
          bookings = [];
        }
        try {
          final me = await api.getMe();
          final city = (me['city'] ?? '').toString().trim();
          if (mounted && city.isNotEmpty) _setClientCity(city);
        } on ApiException catch (e) {
          if (e.statusCode == 401) rethrow;
        } catch (e) {
          debugPrint('[Dashboard] User details laden fout: $e');
        }
        try {
          unreadCount = await api.getNotificationUnreadCount();
        } on ApiException catch (e) {
          if (e.statusCode == 401) rethrow;
          unreadCount = 0;
        } catch (e) {
          debugPrint('[Dashboard] Unread notification count laden fout: $e');
          unreadCount = 0;
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Kon gegevens niet laden. Probeer opnieuw.');
      }
    }

    if (mounted) {
      _realtime()?.setUnreadCount(unreadCount);
      _trainers = trainers;
      _bookings = bookings;
      _applyFilters();
      setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    _currentPage = 1;
    _filtered = List<Trainer>.from(_trainers);
    final query = _query.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      _filtered = _filtered.where((t) {
        final haystack = [
          t.nameOrEmail,
          t.specialty ?? '',
          t.region ?? '',
          t.city ?? '',
          ...t.categories,
          ...t.lessonTypes,
        ].join(' ').toLowerCase();
        return haystack.contains(query);
      }).toList();
    }
    if (_selectedRegion != null && _selectedRegion!.isNotEmpty) {
      final selected = _selectedRegion!.toLowerCase();
      _filtered = _filtered
          .where(
            (t) =>
                (t.region ?? '').toLowerCase() == selected ||
                (t.city ?? '').toLowerCase() == selected,
          )
          .toList();
    }
    if (_selectedSpecialty != null && _selectedSpecialty!.isNotEmpty) {
      _filtered = _filtered
          .where(
            (t) =>
                (t.specialty ?? '').toLowerCase() ==
                _selectedSpecialty!.toLowerCase(),
          )
          .toList();
    }
    if (_maxDistanceKm != null) {
      _filtered = _filtered
          .where(
            (t) => t.distanceKm != null && t.distanceKm! <= _maxDistanceKm!,
          )
          .toList();
    }
    if (_maxPrice > 0) {
      _filtered = _filtered
          .where((t) => (t.hourlyRateCents ?? 0) / 100 <= _maxPrice)
          .toList();
    }
    if (_minRating > 0) {
      _filtered = _filtered
          .where((t) => (t.rating ?? 0) >= _minRating)
          .toList();
    }
    if (_verifiedOnly) {
      _filtered = _filtered.where((t) => t.trainerVerified).toList();
    }
    if (_woman2womanOnly) {
      _filtered = _filtered.where((t) => t.woman2woman).toList();
    }
    if (_selectedLessonType != null && _selectedLessonType!.isNotEmpty) {
      final lt = _selectedLessonType!.toLowerCase();
      _filtered = _filtered.where((t) {
        if (lt == 'duo') return t.offersDuoTraining;
        if (lt == '1-op-1') {
          return t.lessonTypes.any((l) {
            final lower = l.toLowerCase();
            return lower.contains('personal') ||
                lower.contains('1-op-1') ||
                lower.contains('individueel') ||
                lower.contains('privé');
          });
        }
        if (lt == 'groepsles') {
          return t.lessonTypes.any((l) {
            final lower = l.toLowerCase();
            return lower.contains('groep') || lower.contains('group');
          });
        }
        return t.lessonTypes.any((l) => l.toLowerCase().contains(lt));
      }).toList();
    }
    switch (_sortOption) {
      case 'priceLowHigh':
        _filtered.sort(
          (a, b) => (a.hourlyRateCents ?? 0).compareTo(b.hourlyRateCents ?? 0),
        );
        break;
      case 'priceHighLow':
        _filtered.sort(
          (a, b) => (b.hourlyRateCents ?? 0).compareTo(a.hourlyRateCents ?? 0),
        );
        break;
      case 'ratingHighLow':
        _filtered.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        break;
      case 'city':
        _applyCityFirstSort();
        break;
      default:
        _filtered.sort(
          (a, b) => a.nameOrEmail.toLowerCase().compareTo(
            b.nameOrEmail.toLowerCase(),
          ),
        );
    }
  }

  /// Stad-eerst sortering: trainers uit jouw stad (geboost eerst 5, rest shuffle),
  /// daarna anderen op afstand (dichtbij eerst).
  void _applyCityFirstSort() {
    final clientCity = (_clientCity ?? '').toLowerCase().trim();
    if (clientCity.isEmpty) {
      _sortByDistanceOnly();
      return;
    }
    final inCity = <Trainer>[];
    final others = <Trainer>[];
    for (final t in _filtered) {
      final tCity = (t.city ?? '').toLowerCase().trim();
      final tRegion = (t.region ?? '').toLowerCase().trim();
      if (tCity == clientCity || tRegion == clientCity) {
        inCity.add(t);
      } else {
        others.add(t);
      }
    }
    final boosted = inCity.where((t) => t.isBoosted).toList()..shuffle(Random());
    final restInCity = inCity.where((t) => !t.isBoosted).toList()..shuffle(Random());
    final topBoosted = boosted.take(5).toList();
    final restBoosted = boosted.skip(5).toList();
    _sortByDistance(others);
    _filtered = [
      ...topBoosted,
      ...restBoosted,
      ...restInCity,
      ...others,
    ];
  }

  void _sortByDistance(List<Trainer> list) {
    list.sort((a, b) {
      final da = _distanceKm(a);
      final db = _distanceKm(b);
      return da.compareTo(db);
    });
  }

  void _sortByDistanceOnly() {
    if (_userLat != null && _userLng != null) {
      _filtered.sort((a, b) {
        final da = _distanceKm(a);
        final db = _distanceKm(b);
        return da.compareTo(db);
      });
    } else {
      _filtered.shuffle(Random());
    }
  }

  double _distanceKm(Trainer t) {
    if (t.distanceKm != null && t.distanceKm! >= 0) return t.distanceKm!;
    if (_userLat != null && _userLng != null) {
      final tLat = _cityLat(t.city ?? t.region);
      final tLng = _cityLng(t.city ?? t.region);
      if (tLat != null && tLng != null) {
        return _haversineKm(_userLat!, _userLng!, tLat, tLng);
      }
    }
    return double.infinity;
  }

  static const _cityCoords = <String, (double, double)>{
    'rotterdam': (51.9225, 4.4792),
    'amsterdam': (52.3676, 4.9041),
    'den haag': (52.0705, 4.3007),
    'denhaag': (52.0705, 4.3007),
    "s-gravenhage": (52.0705, 4.3007),
    'utrecht': (52.0907, 5.1214),
    'leiden': (52.1601, 4.4970),
    'haarlem': (52.3874, 4.6462),
    'eindhoven': (51.4416, 5.4697),
    'groningen': (53.2194, 6.5665),
    'tilburg': (51.5555, 5.0913),
    'almere': (52.3508, 5.2647),
    'breda': (51.5866, 4.7760),
    'nijmegen': (51.8427, 5.8532),
    'enschede': (52.2215, 6.8937),
    'apeldoorn': (52.2112, 5.9699),
    'arnhem': (51.9851, 5.8987),
    'zaandam': (52.4389, 4.8264),
    'amstelveen': (52.3008, 4.8636),
    'haarlemmermeer': (52.3333, 4.6667),
  };

  double? _cityLat(String? city) {
    if (city == null || city.isEmpty) return null;
    final key = city.toLowerCase().trim();
    return _cityCoords[key]?.$1 ?? _cityCoords[key.replaceAll(' ', '')]?.$1;
  }

  double? _cityLng(String? city) {
    if (city == null || city.isEmpty) return null;
    final key = city.toLowerCase().trim();
    return _cityCoords[key]?.$2 ?? _cityCoords[key.replaceAll(' ', '')]?.$2;
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    final r = AppConfig.earthRadiusKm;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  List<String> _regions() {
    final r = <String>{};
    for (final t in _trainers) {
      if (t.region != null && t.region!.trim().isNotEmpty) {
        r.add(t.region!.trim());
      }
      if (t.city != null && t.city!.trim().isNotEmpty) {
        r.add(t.city!.trim());
      }
    }
    return r.toList()..sort();
  }

  List<String> _specialties() {
    final s = <String>{};
    for (final t in _trainers) {
      if (t.specialty != null && t.specialty!.trim().isNotEmpty) {
        s.add(t.specialty!.trim());
      }
    }
    return s.toList()..sort();
  }

  static const List<String> _lessonTypeOptions = ['Duo', '1-op-1', 'Groepsles'];

  void _clearFilters() {
    setState(() {
      _selectedRegion = null;
      _selectedSpecialty = null;
      _maxDistanceKm = null;
      _maxPrice = 0;
      _minRating = 0;
      _sortOption = 'city';
      _verifiedOnly = false;
      _woman2womanOnly = false;
      _selectedLessonType = null;
    });
    _applyFilters();
  }

  void _applyFilterUpdate() {
    _applyFilters();
    setState(() {});
  }

  bool get _hasActiveFilters =>
      _selectedRegion != null ||
      _selectedSpecialty != null ||
      _maxDistanceKm != null ||
      _maxPrice != 0 ||
      _minRating > 0 ||
      _sortOption != 'city' ||
      _verifiedOnly ||
      _woman2womanOnly ||
      (_selectedLessonType != null && _selectedLessonType!.isNotEmpty);

  List<Trainer> get _paginatedTrainers {
    final start = (_currentPage - 1) * _itemsPerPage;
    if (start >= _filtered.length) return [];
    final end = (start + _itemsPerPage).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  int get _totalPages =>
      (_filtered.length / _itemsPerPage).ceil().clamp(1, 999);

  String _sortLabel(String s) {
    switch (s) {
      case 'city':
        return 'Stad & afstand';
      case 'priceLowHigh':
        return 'Prijs oplopend';
      case 'priceHighLow':
        return 'Prijs aflopend';
      case 'ratingHighLow':
        return 'Rating';
      case 'name':
        return 'Naam';
      default:
        return 'Stad & afstand';
    }
  }

  /// Trainers bij wie de klant minstens 1 voltooide les heeft gehad.
  List<Trainer> _myTrainers() {
    final ids = <String>{};
    for (final b in _bookings) {
      final status = b.status.toLowerCase();
      if (status == 'cancelled') continue;
      if (status != 'completed' && status != 'done' && status != 'finished') continue;
      final id = (b.trainerUserId ?? b.trainerName).trim();
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return [];
    return _trainers
        .where((t) =>
            (ids.contains(t.userId) || ids.contains(t.nameOrEmail)) &&
            !_removedFromMyTrainersIds.contains(t.userId))
        .toList();
  }

  String _userDisplayName() {
    final user = context.read<AuthService>().user;
    if (user == null) return 'daar';
    final name = user['display_name'] ?? user['first_name'] ?? user['name'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString().trim().split(RegExp(r'\s+')).first;
    }
    final email = user['email']?.toString().trim() ?? '';
    if (email.isNotEmpty) {
      final part = email.split('@').first;
      if (part.isNotEmpty) return part;
    }
    return 'daar';
  }

  Booking? _nextSession() {
    final upcoming = _bookings.where((b) => b.isUpcoming).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  Booking? _checkInWindowSession() {
    final now = DateTime.now();
    final candidates = _bookings.where((b) {
      final status = b.status.toLowerCase();
      if (status == 'cancelled' || status == 'completed') return false;
      final isToday =
          b.scheduledAt.year == now.year &&
          b.scheduledAt.month == now.month &&
          b.scheduledAt.day == now.day;
      if (!isToday) return false;
      final startWindow = b.scheduledAt.subtract(TimingConstants.checkInWindow);
      final endWindow = b.scheduledAt
          .add(Duration(minutes: b.durationMinutes))
          .add(TimingConstants.checkInWindow);
      return !now.isBefore(startWindow) && !now.isAfter(endWindow);
    }).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  String? _checkInCountdownLabel() {
    final now = DateTime.now();
    final todayUpcoming = _bookings.where((b) {
      final status = b.status.toLowerCase();
      if (status == 'cancelled' || status == 'completed') return false;
      final isToday =
          b.scheduledAt.year == now.year &&
          b.scheduledAt.month == now.month &&
          b.scheduledAt.day == now.day;
      return isToday && b.scheduledAt.isAfter(now);
    }).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    if (todayUpcoming.isEmpty) return null;
    final next = todayUpcoming.first;
    final checkInStartsAt = next.scheduledAt.subtract(
      TimingConstants.checkInWindow,
    );
    if (!now.isBefore(checkInStartsAt)) return null;
    final remaining = checkInStartsAt.difference(now);
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    if (hours > 0) {
      return 'Check-in beschikbaar over ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return 'Check-in beschikbaar over ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  int _countToPay() => _bookings
      .where(
        (b) =>
            b.status == 'confirmed' &&
            b.paidAt == null &&
            (b.amountCents ?? 0) > 0,
      )
      .length;

  /// Aantal opeenvolgende weken met minstens 1 voltooide sessie.
  int _trainingsStreak() {
    final completed = _bookings.where((b) {
      final s = b.status.toLowerCase();
      return s == 'completed' || s == 'done' || s == 'finished';
    }).toList();
    if (completed.isEmpty) return 0;

    DateTime weekStart(DateTime d) {
      final daysFromMonday = d.weekday - 1;
      return DateTime(d.year, d.month, d.day)
          .subtract(Duration(days: daysFromMonday));
    }

    final weeks = completed
        .map((b) => weekStart(b.scheduledAt))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (weeks.isEmpty) return 0;
    int streak = 1;
    for (int i = 0; i < weeks.length - 1; i++) {
      final diff = weeks[i].difference(weeks[i + 1]).inDays;
      if (diff == 7) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  String _retentionHint() {
    final now = DateTime.now();
    final monthAgo = now.subtract(const Duration(days: 30));
    final completedLast30 = _bookings.where((b) {
      final status = b.status.toLowerCase();
      return b.scheduledAt.isAfter(monthAgo) &&
          (status == 'completed' || status == 'done' || status == 'finished');
    }).length;
    if (_nextSession() == null) {
      return 'Get started!';
    }
    if (completedLast30 >= 8) {
      return 'Top ritme! Blijf consistent met je huidige trainingsstreak.';
    }
    if (completedLast30 >= 4) {
      return 'Goed bezig. Voeg 1 extra sessie toe voor snellere progressie.';
    }
    return 'Bouw momentum op: mik op 2 trainingen per week.';
  }

  Future<void> _toggleFavorite(Trainer trainer) async {
    setState(() {
      if (_favoriteIds.contains(trainer.userId)) {
        _favoriteIds.remove(trainer.userId);
      } else {
        _favoriteIds.add(trainer.userId);
      }
    });
    await _saveFavorites();
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _openMySessions() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ClientSessionsScreen()));
    if (mounted) await _load();
  }

  Future<void> _openCheckInQr(Booking booking) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientCheckInQrScreen(booking: booking),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openInvoices() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ClientInvoicesScreen()));
    if (mounted) await _load();
  }

  Future<void> _openFavoritesScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientFavoritesScreen(
          trainers: _trainers,
          initialFavoriteIds: _favoriteIds,
          onOpenTrainer: _openTrainerProfile,
          onToggleFavorite: _toggleFavorite,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openMessages() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ClientMessagesScreen()));
    if (mounted) await _load();
  }

  Future<void> _openTrainerProfile(
    Trainer trainer, {
    bool focusBookingForm = false,
    bool showFullProfileOnly = false,
    bool isFromMyTrainers = false,
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientTrainerProfileScreen(
          trainer: trainer,
          focusBookingForm: focusBookingForm,
          showFullProfileOnly: showFullProfileOnly,
          isFromMyTrainers: isFromMyTrainers,
          onRemoveFromMyTrainers: isFromMyTrainers
              ? () async {
                  await _removeFromMyTrainers(trainer);
                  if (mounted) Navigator.of(context).pop(true);
                }
              : null,
        ),
      ),
    );
    if (mounted && changed == true) await _load();
  }

  Future<void> _chooseTrainerAction(Trainer trainer) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  trainer.nameOrEmail,
                  style: GoogleFonts.fjallaOne(
                    fontSize: 20,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              Text(
                'Wat wil je doen?',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.event_available_rounded),
                title: const Text('Sessie boeken'),
                subtitle: const Text('Ga direct naar het boekformulier'),
                onTap: () => Navigator.of(ctx).pop('book'),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Profiel bekijken'),
                subtitle: const Text('Bekijk eerst alle trainerinformatie'),
                onTap: () => Navigator.of(ctx).pop('profile'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'book') {
      await _openTrainerProfile(trainer, focusBookingForm: true);
      return;
    }
    await _openTrainerProfile(trainer, showFullProfileOnly: true);
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientNotificationsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _loadGroupSessions() async {
    setState(() {
      _groupSessionsLoading = true;
      _groupSessionsError = null;
    });
    try {
      final list = await context.read<GymiesApi>().getPublicGroupSessions(
        from: DateTime.now(),
        to: DateTime.now().add(const Duration(days: 60)),
      );
      if (!mounted) return;
      setState(() {
        _groupSessions = list;
        _groupSessionsLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _groupSessionsError = e.message;
        _groupSessionsLoading = false;
      });
    } catch (e) {
      debugPrint('[Dashboard] Groepslessen laden fout: $e');
      if (!mounted) return;
      setState(() {
        _groupSessionsError = 'Kon groepslessen niet laden.';
        _groupSessionsLoading = false;
      });
    }
  }

  void _switchView(bool showGroup) {
    setState(() => _showGroupSessions = showGroup);
    if (showGroup && _groupSessions.isEmpty && !_groupSessionsLoading) {
      _loadGroupSessions();
    }
  }

  Future<void> _openGroupSessionDetail(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientGroupSessionDetailScreen(groupSessionId: id),
      ),
    );
    if (mounted && _showGroupSessions) _loadGroupSessions();
  }

  Future<void> _openMyGroupSessions() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientMyGroupSessionsScreen()),
    );
    if (mounted && _showGroupSessions) _loadGroupSessions();
  }

  static String _shortMonth(int m) {
    const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
                    'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    return months[(m - 1).clamp(0, 11)];
  }

  @override
  Widget build(BuildContext context) {
    final liveUnread = _realtime(listen: true)?.unreadCount ?? 0;
    // Realtime is bron van waarheid: bij mark-read wordt die direct bijgewerkt
    final effectiveUnread = liveUnread;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: GymiesColors.primary,
        elevation: 0,
        title: Text(
          AppConfig.appName,
          style: GoogleFonts.fjallaOne(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (effectiveUnread > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        effectiveUnread > 99 ? '99+' : '$effectiveUnread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Meldingen',
            onPressed: () => _openNotifications(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _showGroupSessions ? _loadGroupSessions : _load,
        color: GymiesColors.primary,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _HeaderSection(
                  userDisplayName: _userDisplayName(),
                  trainingsStreak: _trainingsStreak(),
                  nextSession: _nextSession(),
                  checkInBooking: _checkInWindowSession(),
                  checkInCountdownLabel: _checkInCountdownLabel(),
                  trainers: _trainers,
                  toPayCount: _countToPay(),
                  favoriteCount: _favoriteIds.length,
                  onMyBookings: () => _openMySessions(),
                  onMessages: () => _openMessages(),
                  onFavorites: () => _openFavoritesScreen(),
                  onFacturen: () => _openInvoices(),
                  onOpenCheckIn: _openCheckInQr,
                  retentionHint: _retentionHint(),
                  messageUnreadCount: effectiveUnread,
                ),
              ),
            if (!_showGroupSessions && _myTrainers().isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Text(
                    'Mijn trainers',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
              ),
            if (!_showGroupSessions && _myTrainers().isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _myTrainers().length,
                    itemBuilder: (_, i) {
                      final t = _myTrainers()[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _MyTrainerChip(
                          trainer: t,
                          onTap: () => _openTrainerProfile(t, isFromMyTrainers: true),
                        ),
                      );
                    },
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.person_search_rounded, size: 18),
                      label: Text('Individuele Trainers'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.groups_rounded, size: 18),
                      label: Text('Groepslessen'),
                    ),
                  ],
                  selected: {_showGroupSessions},
                  onSelectionChanged: (s) => _switchView(s.first),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return GymiesColors.primary.withValues(alpha: 0.18);
                      }
                      return Colors.white;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return GymiesColors.darkBlue;
                      }
                      return Colors.grey.shade600;
                    }),
                    side: WidgetStateProperty.all(
                      BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
            ),
            if (!_showGroupSessions)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SearchBar(
                      controller: _query,
                      loading: _loading,
                      hasActiveFilters: _hasActiveFilters,
                      onChanged: (_) {
                        _applyFilterUpdate();
                      },
                      onSearch: _load,
                      onFilterTap: _showAllFiltersSheet,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Snelle filters',
                      style: GoogleFonts.fjallaOne(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.darkBlue.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _QuickFiltersRow(
                      selectedRegion: _selectedRegion,
                      selectedSpecialty: _selectedSpecialty,
                      selectedLessonType: _selectedLessonType,
                      maxDistanceKm: _maxDistanceKm,
                      maxPrice: _maxPrice,
                      minRating: _minRating,
                      sortOption: _sortOption,
                      woman2womanOnly: _woman2womanOnly,
                      hasActiveFilters: _hasActiveFilters,
                      regions: _regions(),
                      specialties: _specialties(),
                      onRegionTap: () => _showRegionFilterSheet(),
                      onSpecialtyTap: () => _showSpecialtyFilterSheet(),
                      onLessonTypeTap: () => _showLessonTypeFilterSheet(),
                      onDistanceTap: () => _showDistanceFilterSheet(),
                      onPriceTap: () => _showPriceFilterSheet(),
                      onRatingTap: () => _showRatingFilterSheet(),
                      onSortTap: () => _showSortFilterSheet(),
                      onWoman2WomanTap: () => setState(() {
                        _woman2womanOnly = !_woman2womanOnly;
                        _applyFilterUpdate();
                      }),
                      onClearFilters: () {
                        _clearFilters();
                        setState(() {});
                      },
                    ),
                    if (_hasActiveFilters) ...[
                      const SizedBox(height: 8),
                      _ActiveFilterBadges(
                        selectedRegion: _selectedRegion,
                        selectedSpecialty: _selectedSpecialty,
                        maxDistanceKm: _maxDistanceKm,
                        maxPrice: _maxPrice,
                        minRating: _minRating,
                        sortOption: _sortOption,
                        woman2womanOnly: _woman2womanOnly,
                        selectedLessonType: _selectedLessonType,
                        onClearRegion: () {
                          setState(() {
                            _selectedRegion = null;
                            _applyFilterUpdate();
                          });
                        },
                        onClearSpecialty: () {
                          setState(() {
                            _selectedSpecialty = null;
                            _applyFilterUpdate();
                          });
                        },
                        onClearDistance: () {
                          setState(() {
                            _maxDistanceKm = null;
                            _applyFilterUpdate();
                          });
                        },
                        onClearPrice: () {
                          setState(() {
                            _maxPrice = 0;
                            _applyFilterUpdate();
                          });
                        },
                        onClearRating: () {
                          setState(() {
                            _minRating = 0;
                            _applyFilterUpdate();
                          });
                        },
                        onClearSort: () {
                          setState(() {
                            _sortOption = 'city';
                            _applyFilterUpdate();
                          });
                        },
                        onClearWoman2Woman: () {
                          setState(() {
                            _woman2womanOnly = false;
                            _applyFilterUpdate();
                          });
                        },
                        onClearLessonType: () {
                          setState(() {
                            _selectedLessonType = null;
                            _applyFilterUpdate();
                          });
                        },
                        onClearAll: () {
                          _clearFilters();
                          setState(() {});
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!_showGroupSessions) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ErrorCard(
                      message: _error!,
                      onRetry: _load,
                      onLogout: (_error!.toLowerCase().contains('sessie') ||
                              _error!.toLowerCase().contains('verlopen'))
                          ? _logout
                          : null,
                    ),
                  ),
                )
              else if (_loading && _trainers.isEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: _TrainerCardSkeleton(),
                    ),
                    childCount: 5,
                  ),
                )
              else if (_filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _EmptyState(
                      onSearch: _load,
                      hasActiveFilters: _hasActiveFilters,
                      onClearFilters: () {
                        _clearFilters();
                        setState(() {});
                      },
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_filtered.length} trainer${_filtered.length == 1 ? '' : 's'} gevonden',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Sorteer: ${_sortLabel(_sortOption)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    final t = _paginatedTrainers[i];
                    final animationDelay = Duration(
                      milliseconds: UiConstants.animStaggerBaseMs + (i.clamp(0, UiConstants.animStaggerMaxItems) * UiConstants.animStaggerStepMs),
                    );
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: animationDelay,
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 6,
                        ),
                        child: _TrainerCard(
                          trainer: t,
                          isFavorite: _favoriteIds.contains(t.userId),
                          onToggleFavorite: () => _toggleFavorite(t),
                          onTap: () => _chooseTrainerAction(t),
                        ),
                      ),
                    );
                  }, childCount: _paginatedTrainers.length),
                ),
                if (_totalPages > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: _PaginationRow(
                        currentPage: _currentPage,
                        totalPages: _totalPages,
                        totalItems: _filtered.length,
                        itemsPerPage: _itemsPerPage,
                        onPageChanged: (p) {
                          setState(() => _currentPage = p);
                        },
                      ),
                    ),
                  ),
              ],
            ] else ...[
              // ── Groepslessen tab ─────────────────────────────────
              if (_groupSessionsError != null)
                SliverToBoxAdapter(
                  child: TrainerErrorView(
                    message: _groupSessionsError!,
                    onRetry: _loadGroupSessions,
                  ),
                )
              else if (_groupSessionsLoading)
                const SliverToBoxAdapter(child: TrainerLoadingView())
              else if (_groupSessions.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                    child: Column(
                      children: [
                        Icon(Icons.groups_outlined, size: 64,
                            color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Geen groepslessen gevonden',
                          style: GoogleFonts.fjallaOne(
                            fontSize: 18,
                            color: GymiesColors.darkBlue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Er zijn momenteel geen groepslessen gepland\nin de komende 60 dagen.',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Builder(builder: (ctx) {
                    final auth = ctx.watch<AuthService>();
                    if (!auth.isLoggedIn || auth.isTrainer || auth.isAdmin) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: OutlinedButton.icon(
                        onPressed: _openMyGroupSessions,
                        icon: const Icon(
                            Icons.event_available_rounded, size: 18),
                        label: const Text('Mijn inschrijvingen'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GymiesColors.darkBlue,
                          side: BorderSide(
                              color: GymiesColors.darkBlue
                                  .withValues(alpha: 0.4)),
                        ),
                      ),
                    );
                  }),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((_, i) {
                      final s = _groupSessions[i];
                      final id =
                          mapStr(s, ['id', 'group_session_id']);
                      final rawTitle = mapStr(s, ['title', 'name']);
                      final title =
                          rawTitle.isEmpty ? 'Groepsles' : rawTitle;
                      final startsAt = DateTime.tryParse(mapStr(s, [
                            'starts_at',
                            'startsAt',
                            'start_at',
                            'date',
                          ])) ??
                          DateTime.now();
                      final trainerName = mapStr(
                          s, ['trainer_name', 'trainerName', 'name']);
                      final capacity = int.tryParse(
                              mapStr(s, ['capacity', 'max_participants'])) ??
                          0;
                      final enrolled = int.tryParse(mapStr(s, [
                            'enrolled_count',
                            'participants_count'
                          ])) ??
                          0;
                      final city = mapStr(s, ['city', 'location']);
                      final spotsLeft =
                          capacity > 0 ? capacity - enrolled : null;
                      final isFull =
                          spotsLeft != null && spotsLeft <= 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: id.isEmpty
                              ? null
                              : () => _openGroupSessionDetail(id),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: GymiesColors.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${startsAt.day}',
                                        style: GoogleFonts.fjallaOne(
                                          fontSize: 22,
                                          color: GymiesColors.darkBlue,
                                          height: 1,
                                        ),
                                      ),
                                      Text(
                                        _shortMonth(startsAt.month),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: GymiesColors.darkBlue
                                              .withValues(alpha: 0.7),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: GoogleFonts.fjallaOne(
                                          fontSize: 15,
                                          color: GymiesColors.darkBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}'
                                        '${trainerName.isNotEmpty ? ' · $trainerName' : ''}'
                                        '${city.isNotEmpty ? ' · $city' : ''}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600),
                                      ),
                                      if (capacity > 0) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.people_outline_rounded,
                                              size: 13,
                                              color: isFull
                                                  ? Colors.red.shade600
                                                  : Colors.grey.shade500,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isFull
                                                  ? 'Vol'
                                                  : '$spotsLeft plek${spotsLeft == 1 ? '' : 'ken'} vrij',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isFull
                                                    ? Colors.red.shade600
                                                    : Colors.grey.shade500,
                                                fontWeight: isFull
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    color: Colors.grey.shade400),
                              ],
                            ),
                          ),
                        ),
                      );
                    }, childCount: _groupSessions.length),
                  ),
                ),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  void _showRegionFilterSheet() {
    final regions = _regions();
    if (regions.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Kies stad',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    controller: scrollController,
                    shrinkWrap: true,
                    itemCount: regions.length,
                    itemBuilder: (_, i) {
                      final r = regions[i];
                      return ListTile(
                        title: Text(r),
                        trailing: _selectedRegion == r
                            ? const Icon(Icons.check, color: GymiesColors.primary)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedRegion = _selectedRegion == r ? null : r;
                            _applyFilterUpdate();
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSpecialtyFilterSheet() {
    final specialties = _specialties();
    if (specialties.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Kies specialiteit',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    controller: scrollController,
                    shrinkWrap: true,
                    itemCount: specialties.length,
                    itemBuilder: (_, i) {
                      final s = specialties[i];
                      return ListTile(
                        title: Text(s),
                        trailing: _selectedSpecialty == s
                            ? const Icon(Icons.check, color: GymiesColors.primary)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedSpecialty =
                                _selectedSpecialty == s ? null : s;
                            _applyFilterUpdate();
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLessonTypeFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Kies lesvorm',
                  style: GoogleFonts.fjallaOne(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              ..._lessonTypeOptions.map(
                (lt) => ListTile(
                  title: Text(lt),
                  trailing: _selectedLessonType == lt
                      ? const Icon(Icons.check, color: GymiesColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedLessonType =
                          _selectedLessonType == lt ? null : lt;
                      _applyFilterUpdate();
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showPriceFilterSheet() {
    const options = [0, 50, 75, 100, 150, 200, 250, 500, 1000];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Max. prijs per sessie',
                  style: GoogleFonts.fjallaOne(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              ...options.map(
                (p) => ListTile(
                  title: Text(p == 0 ? 'Geen limiet' : 'Tot €$p'),
                  trailing: _maxPrice == p
                      ? const Icon(Icons.check, color: GymiesColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _maxPrice = p;
                      _applyFilterUpdate();
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showDistanceFilterSheet() {
    const options = [10, 25, 50];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.35,
        minChildSize: 0.25,
        maxChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Afstand',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    controller: scrollController,
                    shrinkWrap: true,
                    children: [
                      ...options.map(
                        (km) => ListTile(
                          title: Text('< $km km'),
                          trailing: _maxDistanceKm == km
                              ? const Icon(Icons.check, color: GymiesColors.primary)
                              : null,
                          onTap: () {
                            setState(() {
                              _maxDistanceKm = _maxDistanceKm == km ? null : km;
                              _applyFilterUpdate();
                            });
                            Navigator.pop(ctx);
                          },
                        ),
                      ),
                      ListTile(
                        title: const Text('Geen afstandsfilter'),
                        trailing: _maxDistanceKm == null
                            ? const Icon(Icons.check, color: GymiesColors.primary)
                            : null,
                        onTap: () {
                          setState(() {
                            _maxDistanceKm = null;
                            _applyFilterUpdate();
                          });
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRatingFilterSheet() {
    final options = [0.0, 3.5, 4.0, 4.5, 5.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Min. beoordeling',
                  style: GoogleFonts.fjallaOne(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              ...options.map(
                (r) => ListTile(
                  title: Text(r == 0 ? 'Alle' : '$r★ en hoger'),
                  trailing: _minRating == r
                      ? const Icon(Icons.check, color: GymiesColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _minRating = r;
                      _applyFilterUpdate();
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortFilterSheet() {
    final options = [
      ('name', 'Naam A–Z'),
      ('priceLowHigh', 'Prijs: laag naar hoog'),
      ('priceHighLow', 'Prijs: hoog naar laag'),
      ('ratingHighLow', 'Beoordeling: hoog naar laag'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sorteren op',
                  style: GoogleFonts.fjallaOne(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
              ...options.map(
                (o) => ListTile(
                  title: Text(o.$2),
                  trailing: _sortOption == o.$1
                      ? const Icon(Icons.check, color: GymiesColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _sortOption = o.$1;
                      _applyFilterUpdate();
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllFiltersSheet() {
    final regions = _regions();
    final specialties = _specialties();
    final sortOptions = [
      ('city', 'Stad & afstand'),
      ('name', 'Naam A–Z'),
      ('priceLowHigh', 'Prijs: laag naar hoog'),
      ('priceHighLow', 'Prijs: hoog naar laag'),
      ('ratingHighLow', 'Beoordeling: hoog naar laag'),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filters',
                        style: GoogleFonts.fjallaOne(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      if (_hasActiveFilters)
                        TextButton(
                          onPressed: () {
                            _clearFilters();
                            setState(() {});
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            'Wis alles',
                            style: TextStyle(
                              color: GymiesColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      _FilterSection(
                        title: 'Locatie',
                        children: [
                          if (regions.isNotEmpty)
                            _FilterSectionTile(
                              label: 'Stad',
                              value: _selectedRegion ?? 'Alle steden',
                              onTap: () {
                                Navigator.pop(ctx);
                                _showRegionFilterSheet();
                              },
                            ),
                          _FilterSectionTile(
                            label: 'Afstand',
                            value: _maxDistanceKm == null
                                ? 'Geen limiet'
                                : '< $_maxDistanceKm km',
                            onTap: () {
                              Navigator.pop(ctx);
                              _showDistanceFilterSheet();
                            },
                          ),
                        ],
                      ),
                      if (specialties.isNotEmpty)
                        _FilterSection(
                          title: 'Specialiteit',
                          children: [
                            _FilterSectionTile(
                              label: 'Specialiteit',
                              value: _selectedSpecialty ?? 'Alle',
                              onTap: () {
                                Navigator.pop(ctx);
                                _showSpecialtyFilterSheet();
                              },
                            ),
                          ],
                        ),
                      _FilterSection(
                        title: 'Lesvorm',
                        children: [
                          _FilterSectionTile(
                            label: 'Lesvorm',
                            value: _selectedLessonType ?? 'Alle',
                            onTap: () {
                              Navigator.pop(ctx);
                              _showLessonTypeFilterSheet();
                            },
                          ),
                        ],
                      ),
                      _FilterSection(
                        title: 'Prijs & beoordeling',
                        children: [
                          _FilterSectionTile(
                            label: 'Max. prijs',
                            value: _maxPrice == 0
                                ? 'Geen limiet'
                                : 'Tot €$_maxPrice',
                            onTap: () {
                              Navigator.pop(ctx);
                              _showPriceFilterSheet();
                            },
                          ),
                          _FilterSectionTile(
                            label: 'Min. beoordeling',
                            value: _minRating == 0
                                ? 'Alle'
                                : '$_minRating★ en hoger',
                            onTap: () {
                              Navigator.pop(ctx);
                              _showRatingFilterSheet();
                            },
                          ),
                        ],
                      ),
                      _FilterSection(
                        title: 'Sortering',
                        children: [
                          _FilterSectionTile(
                            label: 'Sorteer op',
                            value: sortOptions
                                .firstWhere(
                                  (o) => o.$1 == _sortOption,
                                  orElse: () => sortOptions.first,
                                )
                                .$2,
                            onTap: () {
                              Navigator.pop(ctx);
                              _showSortFilterSheet();
                            },
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: SwitchListTile(
                          title: Text(
                            'Woman2Woman',
                            style: GoogleFonts.fjallaOne(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                          value: _woman2womanOnly,
                          onChanged: (v) {
                            setState(() {
                              _woman2womanOnly = v;
                              _applyFilterUpdate();
                            });
                          },
                          activeThumbColor: GymiesColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.fjallaOne(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: GymiesColors.darkBlue.withValues(alpha: 0.6),
            ),
          ),
        ),
        ...children.expand((c) => [c, const SizedBox(height: 8)]).toList()
          ..removeLast(),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _FilterSectionTile extends StatelessWidget {
  const _FilterSectionTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.fjallaOne(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.userDisplayName,
    required this.trainingsStreak,
    required this.nextSession,
    required this.checkInBooking,
    required this.checkInCountdownLabel,
    required this.trainers,
    required this.toPayCount,
    required this.favoriteCount,
    required this.onMyBookings,
    required this.onMessages,
    required this.onFavorites,
    required this.onFacturen,
    required this.onOpenCheckIn,
    required this.retentionHint,
    this.messageUnreadCount = 0,
  });

  final String userDisplayName;
  final int trainingsStreak;
  final Booking? nextSession;
  final Booking? checkInBooking;
  final String? checkInCountdownLabel;
  final List<Trainer> trainers;
  final int toPayCount;
  final int favoriteCount;
  final VoidCallback onMyBookings;
  final VoidCallback onMessages;
  final VoidCallback onFavorites;
  final VoidCallback onFacturen;
  final Future<void> Function(Booking booking) onOpenCheckIn;
  final String retentionHint;
  final int messageUnreadCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: GymiesColors.darkBlue,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hallo, $userDisplayName',
            style: GoogleFonts.fjallaOne(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: GymiesColors.primary,
            ),
          ),
          if (trainingsStreak > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: GymiesColors.primary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: GymiesColors.primary.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    color: GymiesColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    trainingsStreak == 1
                        ? 'Je hebt 1 week achter elkaar getraind'
                        : 'Je hebt $trainingsStreak weken achter elkaar getraind',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (nextSession != null)
            _NextSessionCard(
              booking: nextSession!,
              trainers: trainers,
              canCheckIn: checkInBooking?.id == nextSession!.id,
              onMyBookings: onMyBookings,
              onOpenCheckIn: () => onOpenCheckIn(checkInBooking!),
            ),
          if (nextSession != null) const SizedBox(height: 12),
          _QuickStatsGrid(
            nextSession: nextSession,
            toPayCount: toPayCount,
            favoriteCount: favoriteCount,
            onMyBookings: onMyBookings,
            onMessages: onMessages,
            onFavorites: onFavorites,
            onFacturen: onFacturen,
            messageUnreadCount: messageUnreadCount,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: GymiesColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.trending_up_rounded,
                  color: GymiesColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    retentionHint,
                    style: const TextStyle(
                      color: GymiesColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (checkInBooking != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => onOpenCheckIn(checkInBooking!),
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Inchecken'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Beschikbaar vanaf 15 min voor je les tot 15 min erna.',
              style: TextStyle(
                color: GymiesColors.primary.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          ] else if (checkInCountdownLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              checkInCountdownLabel!,
              style: TextStyle(
                color: GymiesColors.primary.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NextSessionCard extends StatelessWidget {
  const _NextSessionCard({
    required this.booking,
    required this.trainers,
    required this.canCheckIn,
    required this.onMyBookings,
    required this.onOpenCheckIn,
  });

  final Booking booking;
  final List<Trainer> trainers;
  final bool canCheckIn;
  final VoidCallback onMyBookings;
  final VoidCallback onOpenCheckIn;

  Trainer? _trainer() {
    final id = booking.trainerUserId ?? booking.trainerName;
    if (id.isEmpty) return null;
    for (final t in trainers) {
      if (t.userId == id ||
          t.displayName == id ||
          t.email == id ||
          t.nameOrEmail == id) {
        return t;
      }
    }
    return null;
  }

  String _location() {
    final t = _trainer();
    if (t == null) return '';
    final parts = <String>[];
    if (t.city != null && t.city!.isNotEmpty) parts.add(t.city!);
    if (t.region != null && t.region!.isNotEmpty) parts.add(t.region!);
    return parts.join(', ');
  }

  Future<void> _openMaps() async {
    final loc = _location();
    if (loc.isEmpty) return;
    final encoded = Uri.encodeComponent(loc);
    final google = Uri.parse(
      '${AppConfig.googleMapsSearchUrl}$encoded',
    );
    final apple = Uri.parse('${AppConfig.appleMapsSearchUrl}$encoded');
    final opened = await launchUrl(google, mode: LaunchMode.externalApplication);
    if (opened) return;
    await launchUrl(apple, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final loc = _location();
    final dateStr =
        '${booking.scheduledAt.day}/${booking.scheduledAt.month}/${booking.scheduledAt.year}';
    final timeStr =
        '${booking.scheduledAt.hour.toString().padLeft(2, '0')}:${booking.scheduledAt.minute.toString().padLeft(2, '0')}';
    return Material(
      color: GymiesColors.primary.withValues(alpha: 0.2),
      elevation: 2,
      shadowColor: GymiesColors.darkBlue.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: GymiesColors.primary, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_available_rounded,
                    color: GymiesColors.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Volgende sessie',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              booking.trainerName,
              style: GoogleFonts.fjallaOne(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$dateStr om $timeStr · ${booking.durationMinutes} min',
              style: TextStyle(
                fontSize: 14,
                color: GymiesColors.darkBlue.withValues(alpha: 0.85),
              ),
            ),
            if (loc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 16, color: GymiesColors.darkBlue.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      loc,
                      style: TextStyle(
                        fontSize: 13,
                        color: GymiesColors.darkBlue.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onMyBookings,
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: const Text('Afspraken bekijken'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GymiesColors.darkBlue,
                    side: const BorderSide(color: GymiesColors.primary),
                  ),
                ),
                if (canCheckIn)
                  FilledButton.icon(
                    onPressed: onOpenCheckIn,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Inchecken'),
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                  ),
                if (loc.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _openMaps,
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Rute'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: GymiesColors.darkBlue,
                      side: const BorderSide(color: GymiesColors.primary),
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

class _QuickStatsGrid extends StatelessWidget {
  const _QuickStatsGrid({
    required this.nextSession,
    required this.toPayCount,
    required this.favoriteCount,
    required this.onMyBookings,
    required this.onMessages,
    required this.onFavorites,
    required this.onFacturen,
    this.messageUnreadCount = 0,
  });

  final Booking? nextSession;
  final int toPayCount;
  final int favoriteCount;
  final VoidCallback onMyBookings;
  final VoidCallback onMessages;
  final VoidCallback onFavorites;
  final VoidCallback onFacturen;
  final int messageUnreadCount;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.0,
      children: [
        _StatCard(
          icon: Icons.event_available_rounded,
          label: 'Mijn afspraken',
          subtitle: nextSession != null
              ? '${nextSession!.scheduledAt.day}/${nextSession!.scheduledAt.month}${nextSession!.sessionsRemaining != null ? ' · nog ${nextSession!.sessionsRemaining}' : ''}'
              : 'Geen gepland',
          onTap: onMyBookings,
        ),
        _StatCard(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Berichten',
          subtitle: 'Chat',
          onTap: onMessages,
          badgeCount: messageUnreadCount,
        ),
        _StatCard(
          icon: Icons.favorite_rounded,
          label: 'Favorieten',
          subtitle: favoriteCount > 0 ? '$favoriteCount trainer(s)' : null,
          onTap: onFavorites,
        ),
        _StatCard(
          icon: Icons.receipt_long_rounded,
          label: 'Factuur',
          subtitle: toPayCount > 0 ? '$toPayCount te betalen' : 'Overzicht',
          onTap: onFacturen,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: GymiesColors.darkBlue.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: GymiesColors.primary, width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: GymiesColors.primary.withValues(alpha: 0.2),
        highlightColor: GymiesColors.primary.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Badge(
                isLabelVisible: badgeCount > 0,
                label: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
                backgroundColor: Colors.red.shade600,
                child: Icon(icon, color: GymiesColors.primary, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.fjallaOne(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        badgeCount > 0 ? '$badgeCount ongelezen' : subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: badgeCount > 0 ? Colors.red.shade700 : GymiesColors.darkBlue,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.loading,
    required this.onSearch,
    this.onChanged,
    this.onFilterTap,
    this.hasActiveFilters = false,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSearch;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilterTap;
  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Zoek op categorie, les of stad...',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: GymiesColors.darkBlue,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: GymiesColors.primary,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onChanged: onChanged,
            onSubmitted: (_) => onSearch(),
          ),
        ),
        if (onFilterTap != null) ...[
          const SizedBox(width: 8),
          Material(
            color: hasActiveFilters
                ? GymiesColors.primary.withValues(alpha: 0.2)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onFilterTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasActiveFilters
                        ? GymiesColors.primary
                        : Colors.grey.shade300,
                    width: hasActiveFilters ? 2 : 1,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      color: GymiesColors.darkBlue,
                      size: 24,
                    ),
                    if (hasActiveFilters)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: GymiesColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 12),
        FilledButton(
          onPressed: loading ? null : onSearch,
          style: FilledButton.styleFrom(
            backgroundColor: GymiesColors.primary,
            foregroundColor: GymiesColors.darkBlue,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: GymiesColors.darkBlue,
                  ),
                )
              : const Icon(Icons.search_rounded, size: 24),
        ),
      ],
    );
  }
}

class _QuickFiltersRow extends StatelessWidget {
  const _QuickFiltersRow({
    required this.selectedRegion,
    required this.selectedSpecialty,
    required this.selectedLessonType,
    required this.maxDistanceKm,
    required this.maxPrice,
    required this.minRating,
    required this.sortOption,
    required this.woman2womanOnly,
    required this.hasActiveFilters,
    required this.regions,
    required this.specialties,
    required this.onRegionTap,
    required this.onSpecialtyTap,
    required this.onLessonTypeTap,
    required this.onDistanceTap,
    required this.onPriceTap,
    required this.onRatingTap,
    required this.onSortTap,
    required this.onWoman2WomanTap,
    required this.onClearFilters,
  });

  final String? selectedRegion;
  final String? selectedSpecialty;
  final String? selectedLessonType;
  final int? maxDistanceKm;
  final int maxPrice;
  final double minRating;
  final String sortOption;
  final bool woman2womanOnly;
  final bool hasActiveFilters;
  final List<String> regions;
  final List<String> specialties;
  final VoidCallback onRegionTap;
  final VoidCallback onSpecialtyTap;
  final VoidCallback onLessonTypeTap;
  final VoidCallback onDistanceTap;
  final VoidCallback onPriceTap;
  final VoidCallback onRatingTap;
  final VoidCallback onSortTap;
  final VoidCallback onWoman2WomanTap;
  final VoidCallback onClearFilters;

  String _sortLabel(String s) {
    switch (s) {
      case 'city':
        return 'Stad & afstand';
      case 'priceLowHigh':
        return 'Prijs oplopend';
      case 'priceHighLow':
        return 'Prijs aflopend';
      case 'ratingHighLow':
        return 'Rating';
      case 'name':
        return 'Naam';
      default:
        return 'Stad & afstand';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: selectedRegion ?? 'Stad',
            isActive: selectedRegion != null,
            onTap: onRegionTap,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: selectedSpecialty ?? 'Specialiteit',
            isActive: selectedSpecialty != null,
            onTap: onSpecialtyTap,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: selectedLessonType ?? 'Lesvorm',
            isActive: selectedLessonType != null && selectedLessonType!.isNotEmpty,
            onTap: onLessonTypeTap,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: maxDistanceKm == null ? 'Afstand' : '< ${maxDistanceKm}km',
            isActive: maxDistanceKm != null,
            onTap: onDistanceTap,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: maxPrice == 0 ? 'Prijs' : 'Tot €$maxPrice',
            isActive: maxPrice != 0,
            onTap: onPriceTap,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: minRating > 0 ? '≥ $minRating ★' : 'Beoordeling',
            isActive: minRating > 0,
            onTap: onRatingTap,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'WOMAN2WOMAN',
            isActive: woman2womanOnly,
            onTap: onWoman2WomanTap,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: _sortLabel(sortOption),
            isActive: sortOption != 'city',
            onTap: onSortTap,
          ),
          if (hasActiveFilters) ...[
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Wis filters',
              isActive: true,
              onTap: onClearFilters,
              isClear: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _MyTrainerChip extends StatelessWidget {
  const _MyTrainerChip({
    required this.trainer,
    required this.onTap,
  });

  final Trainer trainer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
                backgroundImage:
                    trainer.avatarUrl != null && trainer.avatarUrl!.isNotEmpty
                    ? CachedNetworkImageProvider(trainer.avatarUrl!)
                    : null,
                child: trainer.avatarUrl == null || trainer.avatarUrl!.isEmpty
                    ? Text(
                        trainer.nameOrEmail.isNotEmpty
                            ? trainer.nameOrEmail[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 16,
                          color: GymiesColors.darkBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                trainer.nameOrEmail,
                style: GoogleFonts.fjallaOne(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isClear = false,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isClear;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.fjallaOne(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      selected: isActive,
      onSelected: (_) => onTap(),
      selectedColor: isClear
          ? Colors.grey.shade300
          : GymiesColors.primary.withValues(alpha: 0.3),
      checkmarkColor: GymiesColors.darkBlue,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isActive ? GymiesColors.primary : Colors.grey.shade300,
        width: isActive ? 2 : 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    this.onLogout,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Colors.red.shade700,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (onLogout != null)
              TextButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Log opnieuw in'),
              )
            else
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Opnieuw proberen'),
              ),
            if (onLogout != null)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Opnieuw proberen'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onSearch,
    this.hasActiveFilters = false,
    this.onClearFilters,
  });

  final VoidCallback onSearch;
  final bool hasActiveFilters;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          'Geen trainers gevonden',
          style: GoogleFonts.fjallaOne(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasActiveFilters
              ? 'Je filters leveren geen resultaten op.\nPas je filters aan of zoek in een andere stad.'
              : 'Er zijn momenteel geen trainers beschikbaar.\nProbeer het later opnieuw of pas je zoekopdracht aan.',
          style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (hasActiveFilters && onClearFilters != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Alle filters wissen'),
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Opnieuw zoeken'),
          style: OutlinedButton.styleFrom(
            foregroundColor: GymiesColors.darkBlue,
            side: const BorderSide(color: GymiesColors.primary),
          ),
        ),
      ],
    );
  }
}

class _ActiveFilterBadges extends StatelessWidget {
  const _ActiveFilterBadges({
    required this.selectedRegion,
    required this.selectedSpecialty,
    required this.maxDistanceKm,
    required this.maxPrice,
    required this.minRating,
    required this.sortOption,
    required this.woman2womanOnly,
    required this.selectedLessonType,
    required this.onClearRegion,
    required this.onClearSpecialty,
    required this.onClearDistance,
    required this.onClearPrice,
    required this.onClearRating,
    required this.onClearSort,
    required this.onClearWoman2Woman,
    required this.onClearLessonType,
    required this.onClearAll,
  });

  final String? selectedRegion;
  final String? selectedSpecialty;
  final int? maxDistanceKm;
  final int maxPrice;
  final double minRating;
  final String sortOption;
  final bool woman2womanOnly;
  final String? selectedLessonType;
  final VoidCallback onClearRegion;
  final VoidCallback onClearSpecialty;
  final VoidCallback onClearDistance;
  final VoidCallback onClearPrice;
  final VoidCallback onClearRating;
  final VoidCallback onClearSort;
  final VoidCallback onClearWoman2Woman;
  final VoidCallback onClearLessonType;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (selectedRegion != null) {
      chips.add(_RemovableChip(label: selectedRegion!, onRemove: onClearRegion));
    }
    if (selectedSpecialty != null) {
      chips.add(_RemovableChip(label: selectedSpecialty!, onRemove: onClearSpecialty));
    }
    if (maxDistanceKm != null) {
      chips.add(_RemovableChip(label: '< ${maxDistanceKm}km', onRemove: onClearDistance));
    }
    if (maxPrice > 0) {
      chips.add(_RemovableChip(label: 'Tot €$maxPrice', onRemove: onClearPrice));
    }
    if (minRating > 0) {
      chips.add(_RemovableChip(label: '≥ $minRating ★', onRemove: onClearRating));
    }
    if (woman2womanOnly) {
      chips.add(_RemovableChip(label: 'Woman2Woman', onRemove: onClearWoman2Woman));
    }
    if (selectedLessonType != null && selectedLessonType!.isNotEmpty) {
      chips.add(_RemovableChip(label: selectedLessonType!, onRemove: onClearLessonType));
    }
    if (sortOption != 'city') {
      final label = sortOption == 'priceLowHigh'
          ? 'Prijs ↑'
          : sortOption == 'priceHighLow'
              ? 'Prijs ↓'
              : sortOption == 'ratingHighLow'
                  ? 'Rating'
                  : 'Naam';
      chips.add(_RemovableChip(label: label, onRemove: onClearSort));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        ...chips,
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onClearAll,
          child: Text(
            'Alles wissen',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onRemove,
      backgroundColor: GymiesColors.primary.withValues(alpha: 0.15),
      side: const BorderSide(color: GymiesColors.primary),
    );
  }
}

class _PaginationRow extends StatelessWidget {
  const _PaginationRow({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.itemsPerPage,
    required this.onPageChanged,
  });

  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int itemsPerPage;
  final void Function(int) onPageChanged;

  @override
  Widget build(BuildContext context) {
    final maxVisible = 5;
    int start = (currentPage - maxVisible ~/ 2).clamp(1, totalPages);
    int end = (start + maxVisible - 1).clamp(1, totalPages);
    if (end - start + 1 < maxVisible) {
      start = (end - maxVisible + 1).clamp(1, totalPages);
    }
    final pages = <int>[];
    for (int i = start; i <= end; i++) {
      pages.add(i);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (currentPage > 1)
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onPageChanged(currentPage - 1),
          ),
        ...pages.map((p) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: p == currentPage
                    ? GymiesColors.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => onPageChanged(p),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: Text(
                        '$p',
                        style: TextStyle(
                          fontWeight: p == currentPage
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: p == currentPage
                              ? GymiesColors.darkBlue
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )),
        if (currentPage < totalPages)
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onPageChanged(currentPage + 1),
          ),
      ],
    );
  }
}

class _TrainerCard extends StatelessWidget {
  const _TrainerCard({
    required this.trainer,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  final Trainer trainer;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
                backgroundImage:
                    trainer.avatarUrl != null && trainer.avatarUrl!.isNotEmpty
                    ? CachedNetworkImageProvider(trainer.avatarUrl!)
                    : null,
                child: trainer.avatarUrl == null || trainer.avatarUrl!.isEmpty
                    ? Text(
                        trainer.nameOrEmail.isNotEmpty
                            ? trainer.nameOrEmail[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 22,
                          color: GymiesColors.darkBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trainer.nameOrEmail,
                      style: GoogleFonts.fjallaOne(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                            trainer.specialty,
                            trainer.city,
                            trainer.region,
                            trainer.lessonTypes.isNotEmpty
                                ? trainer.lessonTypes.first
                                : null,
                          ]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' • '),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: TrainerBadges.forCard(trainer)
                          .map((b) => TrainerBadgePill(badge: b, compact: true))
                          .toList(),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (trainer.rating != null) ...[
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            trainer.rating!.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          trainer.priceLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: GymiesColors.primary,
                          ),
                        ),
                        if (trainer.distanceKm != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${trainer.distanceKm!.toStringAsFixed(1)} km',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onToggleFavorite,
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite
                      ? Colors.red.shade400
                      : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainerCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 16,
                    width: 140,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
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
