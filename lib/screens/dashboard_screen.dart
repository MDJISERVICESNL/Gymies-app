import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/gymies_theme.dart';
import '../models/trainer.dart';
import '../utils/haptics.dart';
import '../utils/trainer_badges.dart';
import '../utils/map_utils.dart';
import '../models/booking.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import 'client_trainer_profile_screen.dart';
import 'client_favorites_standalone_screen.dart';
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

  // Group sessions tab
  bool _showGroupSessions = false;
  List<Map<String, dynamic>> _groupSessions = [];
  bool _groupSessionsLoading = false;
  String? _groupSessionsError;

  // Cached my trainers (berekend in _applyFilters, niet in build)
  List<Trainer> _cachedMyTrainers = [];

  // Debounce timer voor zoeken
  Timer? _debounceTimer;

  // Alle unieke specialisaties uit de database (categories + specialty + specializationsTags)
  List<String> _allSpecialties = [];

  static const int _itemsPerPage = TimingConstants.itemsPerPage;
  int _currentPage = 1;

  // Shuffle seed — wordt 1x gezet bij data load, niet bij elke rebuild
  int _shuffleSeed = 0;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final api = context.read<GymiesApi>();
    final prefs = await SharedPreferences.getInstance();

    // Favorieten: server → local fallback
    List<String> favList;
    try {
      favList = await api.getFavoriteTrainerIds();
      await prefs.setStringList(_kFavoritesKey, favList);
    } catch (_) {
      favList = prefs.getStringList(_kFavoritesKey) ?? [];
    }

    // Verborgen trainers: server → local fallback
    List<String> removedList;
    try {
      removedList = await api.getHiddenTrainerIds();
      await prefs.setStringList(_kRemovedFromMyTrainersKey, removedList);
    } catch (_) {
      removedList = prefs.getStringList(_kRemovedFromMyTrainersKey) ?? [];
    }

    // City: uit /me response (al beschikbaar via auth), fallback local
    final city = prefs.getString(_kClientCityKey);

    if (mounted) {
      setState(() {
        _favoriteIds = favList.toSet();
        _removedFromMyTrainersIds = removedList.toSet();
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
      // Sync naar server
      try {
        context.read<GymiesApi>().updateMe(city: city.trim());
      } catch (_) {}
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
    // Server sync
    try {
      await context.read<GymiesApi>().hideTrainer(id);
    } catch (_) {}
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
          if (kDebugMode) debugPrint('[Dashboard] Geolocation city lookup fout: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Dashboard] Geolocation initialization fout: $e');
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
          if (kDebugMode) debugPrint('[Dashboard] Bookings laden fout: $e');
          bookings = [];
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Kon gegevens niet laden. Probeer opnieuw.');
      }
    }

    // Specialties ophalen van API (parallel, foutbestendig)
    List<String> apiSpecialties = [];
    try {
      final specs = await api.getSpecialties();
      apiSpecialties = specs
          .map((s) => (s['name'] ?? '').toString().trim())
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (_) {
      // Fallback: afleiden uit trainer data (oude methode)
    }

    if (mounted) {
      _trainers = trainers;
      _bookings = bookings;
      _shuffleSeed = DateTime.now().millisecondsSinceEpoch;
      _buildAllSpecialties(apiSpecialties: apiSpecialties);
      _applyFilters();
      setState(() => _loading = false);
    }
  }

  /// Splits een tekst op zowel komma's als `&` en geeft opgeschoonde tokens.
  /// "Afvallen & Voeding, HIIT & Cardio" → ["Afvallen", "Voeding", "HIIT", "Cardio"]
  static List<String> _tokenizeSpecialty(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(RegExp(r'[,&]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Alle unieke specialty-tokens van één trainer (specialty + categories + tags).
  static Set<String> _trainerSpecTokens(Trainer t) {
    final tokens = <String>{};
    tokens.addAll(_tokenizeSpecialty(t.specialty));
    for (final c in t.categories) {
      tokens.addAll(_tokenizeSpecialty(c));
    }
    for (final s in t.specializationsTags) {
      tokens.addAll(_tokenizeSpecialty(s));
    }
    return tokens;
  }

  /// Bouw een gesorteerde lijst van alle unieke specialisaties uit de database.
  /// Split op zowel komma als & voor individuele sport-chips.
  void _buildAllSpecialties({List<String> apiSpecialties = const []}) {
    if (apiSpecialties.isNotEmpty) {
      // API geeft gesorteerde lijst — gebruik die direct
      _allSpecialties = apiSpecialties;
    } else {
      // Fallback: afleiden uit geladen trainers
      final specs = <String>{};
      for (final t in _trainers) {
        specs.addAll(_trainerSpecTokens(t));
      }
      _allSpecialties = specs.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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
      final spec = _selectedSpecialty!.toLowerCase();
      _filtered = _filtered
          .where((t) {
            // Gebruik gedeelde tokenizer: split op komma én &
            return _trainerSpecTokens(t).any(
              (token) => token.toLowerCase() == spec,
            );
          })
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
    // Cache my trainers (1x per filter cycle, niet in build)
    _cachedMyTrainers = _computeMyTrainers();

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
    final rng = Random(_shuffleSeed);
    final boosted = inCity.where((t) => t.isBoosted).toList()..shuffle(rng);
    final restInCity = inCity.where((t) => !t.isBoosted).toList()..shuffle(Random(_shuffleSeed + 1));
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
      _filtered.shuffle(Random(_shuffleSeed));
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
      s.addAll(_trainerSpecTokens(t));
    }
    return s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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

  void _onSearchChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _applyFilterUpdate();
    });
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
  List<Trainer> _computeMyTrainers() {
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


  Future<void> _toggleFavorite(Trainer trainer) async {
    Haptics.light();
    setState(() {
      if (_favoriteIds.contains(trainer.userId)) {
        _favoriteIds.remove(trainer.userId);
      } else {
        _favoriteIds.add(trainer.userId);
      }
    });
    await _saveFavorites();
  }

  Future<void> _openTrainerProfile(
    Trainer trainer, {
    bool focusBookingForm = false,
    bool showFullProfileOnly = false,
    bool isFromMyTrainers = false,
  }) async {
    // Navigeer direct naar het openbare profiel
    await _openPublicTrainerProfile(trainer, isFromMyTrainers: isFromMyTrainers);
  }

  /// Open het openbare profiel van een trainer — navigeert direct,
  /// het profiel-screen laadt zelf packages/availability/media/reviews async.
  Future<void> _openPublicTrainerProfile(
    Trainer trainer, {
    bool isFromMyTrainers = false,
  }) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ClientPublicTrainerProfileScreen(
          trainer: trainer,
          onChatTap: () {
            // Pop wordt al gedaan door het profiel-scherm zelf
            _openBookingWithChat(trainer);
          },
          onBookTap: () {
            // Pop wordt al gedaan door het profiel-scherm zelf
            _openBookingDirect(trainer);
          },
        ),
      ),
    );

    if (!mounted) return;
    if (result == 'chat') {
      _openBookingWithChat(trainer);
    } else if (result == 'book') {
      _openBookingDirect(trainer);
    }
  }

  /// Open de booking screen (voor "Boek sessie" knop vanuit profiel)
  void _openBookingDirect(Trainer trainer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientTrainerProfileScreen(
          trainer: trainer,
          focusBookingForm: true,
        ),
      ),
    );
  }

  /// Open de booking screen met chat focus
  void _openBookingWithChat(Trainer trainer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientTrainerProfileScreen(
          trainer: trainer,
        ),
      ),
    );
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
      if (kDebugMode) debugPrint('[Dashboard] Groepslessen laden fout: $e');
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        onRefresh: _showGroupSessions ? _loadGroupSessions : _load,
        color: const Color(0xFFB8860B),
        child: CustomScrollView(
          slivers: [
            // ── Compacte header ──────────────────────────────
            SliverAppBar(
              expandedHeight: 100,
              pinned: true,
              floating: false,
              backgroundColor: const Color(0xFF1E3A5F),
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF1E3A5F),
                        const Color(0xFF2A4F7A),
                        const Color(0xFF3A6090),
                      ],
                    ),
                  ),
                ),
              ),
              title: Text(
                'Ontdekken',
                style: GoogleFonts.sora(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            // ── Zoekbalk ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _SearchBar(
                  controller: _query,
                  loading: _loading,
                  hasActiveFilters: _hasActiveFilters,
                  clientCity: _clientCity,
                  onChanged: _onSearchChanged,
                  onSearch: _load,
                  onFilterTap: _showAllFiltersSheet,
                ),
              ),
            ),

            // ── Locatie indicator ────────────────────────────────
            if (_clientCity != null && _clientCity!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 14, color: const Color(0xFFB8860B)),
                      const SizedBox(width: 4),
                      Text(
                        _clientCity!,
                        style: GoogleFonts.sora(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFB8860B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Snelle filter chips ───────────────────────────
            if (!_showGroupSessions)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 4),
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
                            setState(() { _selectedRegion = null; _applyFilterUpdate(); });
                          },
                          onClearSpecialty: () {
                            setState(() { _selectedSpecialty = null; _applyFilterUpdate(); });
                          },
                          onClearDistance: () {
                            setState(() { _maxDistanceKm = null; _applyFilterUpdate(); });
                          },
                          onClearPrice: () {
                            setState(() { _maxPrice = 0; _applyFilterUpdate(); });
                          },
                          onClearRating: () {
                            setState(() { _minRating = 0; _applyFilterUpdate(); });
                          },
                          onClearSort: () {
                            setState(() { _sortOption = 'city'; _applyFilterUpdate(); });
                          },
                          onClearWoman2Woman: () {
                            setState(() { _woman2womanOnly = false; _applyFilterUpdate(); });
                          },
                          onClearLessonType: () {
                            setState(() { _selectedLessonType = null; _applyFilterUpdate(); });
                          },
                          onClearAll: () { _clearFilters(); setState(() {}); },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // ── Mijn trainers ─────────────────────────────────
            if (!_showGroupSessions && _cachedMyTrainers.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mijn trainers',
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ClientFavoritesStandaloneScreen(),
                          ),
                        ),
                        child: Text(
                          'Alle ›',
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            color: const Color(0xFFB8860B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _cachedMyTrainers.length,
                    itemBuilder: (_, i) {
                      final t = _cachedMyTrainers[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _MyTrainerChip(
                          trainer: t,
                          onTap: () => _openTrainerProfile(t, isFromMyTrainers: true),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],

            // ── Pill tabs: Trainers / Groepslessen ────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    _PillTab(
                      label: 'Trainers',
                      isActive: !_showGroupSessions,
                      onTap: () => _switchView(false),
                    ),
                    const SizedBox(width: 8),
                    _PillTab(
                      label: 'Groepslessen',
                      isActive: _showGroupSessions,
                      onTap: () => _switchView(true),
                    ),
                  ],
                ),
              ),
            ),

            // ── Trainer lijst ─────────────────────────────────
            if (!_showGroupSessions) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ErrorCard(
                      message: _error!,
                      onRetry: _load,
                    ),
                  ),
                )
              else if (_loading && _trainers.isEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
                      onClearFilters: () { _clearFilters(); setState(() {}); },
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
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: _showSortFilterSheet,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Sorteer',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: const Color(0xFFB8860B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 18, color: const Color(0xFFB8860B)),
                            ],
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: _TrainerCard(
                          trainer: t,
                          isFavorite: _favoriteIds.contains(t.userId),
                          onToggleFavorite: () => _toggleFavorite(t),
                          onTap: () => _openTrainerProfile(t),
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
                        onPageChanged: (p) => setState(() => _currentPage = p),
                      ),
                    ),
                  ),
              ],
            ] else ...[
              // ── Groepslessen tab (UNCHANGED) ─────────────────
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
                        Icon(Icons.groups_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Geen groepslessen gevonden',
                          style: GoogleFonts.sora(fontSize: 18, color: GymiesColors.darkBlue),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Er zijn momenteel geen groepslessen gepland\nin de komende 60 dagen.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: const Text('Mijn inschrijvingen'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GymiesColors.darkBlue,
                          side: BorderSide(color: GymiesColors.darkBlue.withValues(alpha: 0.4)),
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
                      final id = mapStr(s, ['id', 'group_session_id']);
                      final rawTitle = mapStr(s, ['title', 'name']);
                      final title = rawTitle.isEmpty ? 'Groepsles' : rawTitle;
                      final startsAt = DateTime.tryParse(mapStr(s, [
                            'starts_at', 'startsAt', 'start_at', 'date',
                        ])) ?? DateTime.now();
                      final trainerName = mapStr(s, ['trainer_name', 'trainerName', 'name']);
                      final capacity = int.tryParse(mapStr(s, ['capacity', 'max_participants'])) ?? 0;
                      final enrolled = int.tryParse(mapStr(s, ['enrolled_count', 'participants_count'])) ?? 0;
                      final city = mapStr(s, ['city', 'location']);
                      final spotsLeft = capacity > 0 ? capacity - enrolled : null;
                      final isFull = spotsLeft != null && spotsLeft <= 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: id.isEmpty ? null : () => _openGroupSessionDetail(id),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 56, height: 56,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFB8860B).withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('${startsAt.day}',
                                        style: GoogleFonts.sora(fontSize: 22, color: GymiesColors.darkBlue, height: 1)),
                                      Text(_shortMonth(startsAt.month),
                                        style: TextStyle(fontSize: 11, color: GymiesColors.darkBlue.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: GoogleFonts.sora(fontSize: 15, color: GymiesColors.darkBlue)),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}'
                                        '${trainerName.isNotEmpty ? ' · $trainerName' : ''}'
                                        '${city.isNotEmpty ? ' · $city' : ''}',
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                      ),
                                      if (capacity > 0) ...[
                                        const SizedBox(height: 4),
                                        Row(children: [
                                          Icon(Icons.people_outline_rounded, size: 13,
                                              color: isFull ? Colors.red.shade600 : Colors.grey.shade500),
                                          const SizedBox(width: 4),
                                          Text(
                                            isFull ? 'Vol' : '$spotsLeft plek${spotsLeft == 1 ? '' : 'ken'} vrij',
                                            style: TextStyle(fontSize: 12,
                                              color: isFull ? Colors.red.shade600 : Colors.grey.shade500,
                                              fontWeight: isFull ? FontWeight.w600 : FontWeight.normal),
                                          ),
                                        ]),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: Colors.grey.shade400),
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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: GymiesColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Kies stad',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
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
            ],
          ),
        ),
      ),
    );
  }

  void _showSpecialtyFilterSheet() {
    final specialties = _specialties();
    if (specialties.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: GymiesColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Kies specialiteit',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 350),
                child: ListView.builder(
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
            ],
          ),
        ),
      ),
    );
  }

  void _showLessonTypeFilterSheet() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.videocam_rounded,
                      color: GymiesColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Kies lesvorm',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPriceFilterSheet() {
    const options = [0, 50, 75, 100, 150, 200, 250, 500, 1000];
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.euro_rounded,
                      color: GymiesColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Max. prijs per sessie',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 350),
                child: ListView(
                  shrinkWrap: true,
                  children: [
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDistanceFilterSheet() {
    const options = [10, 25, 50];
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: GymiesColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Afstand',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListView(
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
            ],
          ),
        ),
      ),
    );
  }

  void _showRatingFilterSheet() {
    final options = [0.0, 3.5, 4.0, 4.5, 5.0];
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: GymiesColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Min. beoordeling',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.sort_rounded,
                      color: GymiesColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sorteren op',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllFiltersSheet() {
    final regions = _regions();
    const accent = Color(0xFFB8860B);
    const accentLight = Color(0xFFFFF8E1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        // Local state voor filter sheet
        return StatefulBuilder(
          builder: (ctx, sheetSetState) {
            // Bereken resultaten live
            int countResults() {
              var list = List<Trainer>.from(_trainers);
              final query = _query.text.trim().toLowerCase();
              if (query.isNotEmpty) {
                list = list.where((t) {
                  final haystack = [t.nameOrEmail, t.specialty ?? '', t.region ?? '', t.city ?? '', ...t.categories, ...t.lessonTypes].join(' ').toLowerCase();
                  return haystack.contains(query);
                }).toList();
              }
              if (_selectedRegion != null) list = list.where((t) => (t.region ?? '').toLowerCase() == _selectedRegion!.toLowerCase() || (t.city ?? '').toLowerCase() == _selectedRegion!.toLowerCase()).toList();
              if (_selectedSpecialty != null) {
                final spec = _selectedSpecialty!.toLowerCase();
                list = list.where((t) => _trainerSpecTokens(t).any((token) => token.toLowerCase() == spec)).toList();
              }
              if (_maxDistanceKm != null) list = list.where((t) => t.distanceKm != null && t.distanceKm! <= _maxDistanceKm!).toList();
              if (_maxPrice > 0) list = list.where((t) => (t.hourlyRateCents ?? 0) / 100 <= _maxPrice).toList();
              if (_minRating > 0) list = list.where((t) => (t.rating ?? 0) >= _minRating).toList();
              if (_verifiedOnly) list = list.where((t) => t.trainerVerified).toList();
              if (_woman2womanOnly) list = list.where((t) => t.woman2woman).toList();
              if (_selectedLessonType != null && _selectedLessonType!.isNotEmpty) {
                final lt = _selectedLessonType!.toLowerCase();
                list = list.where((t) {
                  if (lt == 'duo') return t.offersDuoTraining;
                  if (lt == '1-op-1') return t.lessonTypes.any((l) { final lower = l.toLowerCase(); return lower.contains('personal') || lower.contains('1-op-1') || lower.contains('individueel') || lower.contains('privé'); });
                  if (lt == 'groepsles') return t.lessonTypes.any((l) { final lower = l.toLowerCase(); return lower.contains('groep') || lower.contains('group'); });
                  return t.lessonTypes.any((l) => l.toLowerCase().contains(lt));
                }).toList();
              }
              return list.length;
            }

            final resultCount = countResults();

            Widget chipOption(String label, bool isSelected, VoidCallback onTap) {
              return GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? GymiesColors.darkBlue : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? Border.all(color: GymiesColors.primary, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? GymiesColors.primary : Colors.grey.shade700,
                    ),
                  ),
                ),
              );
            }

            Widget sectionLabel(String text) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: Text(
                  text.toUpperCase(),
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue.withValues(alpha: 0.5),
                    letterSpacing: 0.8,
                  ),
                ),
              );
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filters',
                          style: GoogleFonts.sora(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                        if (_hasActiveFilters)
                          GestureDetector(
                            onTap: () {
                              _clearFilters();
                              sheetSetState(() {});
                              setState(() {});
                            },
                            child: Text(
                              'Wis alles',
                              style: GoogleFonts.sora(
                                fontSize: 13,
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Icon(Icons.close_rounded, size: 22, color: Colors.grey.shade400),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Scrollable filter content
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shrinkWrap: true,
                      children: [
                        // ── Locatie ──
                        if (regions.isNotEmpty) ...[
                          sectionLabel('Locatie'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: regions.take(12).map((r) => chipOption(
                              r,
                              _selectedRegion == r,
                              () {
                                setState(() {
                                  _selectedRegion = _selectedRegion == r ? null : r;
                                  _applyFilterUpdate();
                                });
                                sheetSetState(() {});
                              },
                            )).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Afstand ──
                        sectionLabel('Afstand'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chipOption('< 10 km', _maxDistanceKm == 10, () {
                              setState(() { _maxDistanceKm = _maxDistanceKm == 10 ? null : 10; _applyFilterUpdate(); });
                              sheetSetState(() {});
                            }),
                            chipOption('< 25 km', _maxDistanceKm == 25, () {
                              setState(() { _maxDistanceKm = _maxDistanceKm == 25 ? null : 25; _applyFilterUpdate(); });
                              sheetSetState(() {});
                            }),
                            chipOption('< 50 km', _maxDistanceKm == 50, () {
                              setState(() { _maxDistanceKm = _maxDistanceKm == 50 ? null : 50; _applyFilterUpdate(); });
                              sheetSetState(() {});
                            }),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── Specialisatie (uit database) ──
                        if (_allSpecialties.isNotEmpty) ...[
                          sectionLabel('Specialisatie'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _allSpecialties.take(20).map((s) => chipOption(
                              s,
                              _selectedSpecialty == s,
                              () {
                                setState(() {
                                  _selectedSpecialty = _selectedSpecialty == s ? null : s;
                                  _applyFilterUpdate();
                                });
                                sheetSetState(() {});
                              },
                            )).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Lesvorm ──
                        sectionLabel('Lesvorm'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _lessonTypeOptions.map((lt) => chipOption(
                            lt,
                            _selectedLessonType == lt,
                            () {
                              setState(() {
                                _selectedLessonType = _selectedLessonType == lt ? null : lt;
                                _applyFilterUpdate();
                              });
                              sheetSetState(() {});
                            },
                          )).toList(),
                        ),
                        const SizedBox(height: 20),

                        // ── Prijs ──
                        sectionLabel('Max. prijs per sessie'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [0, 50, 75, 100, 150, 200].map((p) => chipOption(
                            p == 0 ? 'Geen limiet' : 'Tot €$p',
                            _maxPrice == p,
                            () {
                              setState(() { _maxPrice = p; _applyFilterUpdate(); });
                              sheetSetState(() {});
                            },
                          )).toList(),
                        ),
                        const SizedBox(height: 20),

                        // ── Beoordeling ──
                        sectionLabel('Min. beoordeling'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [0.0, 3.5, 4.0, 4.5].map((r) => chipOption(
                            r == 0 ? 'Alle' : '${r.toString()}★+',
                            _minRating == r,
                            () {
                              setState(() { _minRating = r; _applyFilterUpdate(); });
                              sheetSetState(() {});
                            },
                          )).toList(),
                        ),
                        const SizedBox(height: 20),

                        // ── Extra ──
                        sectionLabel('Extra'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chipOption(
                              '✓ Geverifieerd',
                              _verifiedOnly,
                              () {
                                setState(() { _verifiedOnly = !_verifiedOnly; _applyFilterUpdate(); });
                                sheetSetState(() {});
                              },
                            ),
                            chipOption(
                              'Woman2Woman',
                              _woman2womanOnly,
                              () {
                                setState(() { _woman2womanOnly = !_woman2womanOnly; _applyFilterUpdate(); });
                                sheetSetState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── Sortering ──
                        sectionLabel('Sorteren op'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ('city', 'Stad & afstand'),
                            ('name', 'Naam A–Z'),
                            ('priceLowHigh', 'Prijs ↑'),
                            ('priceHighLow', 'Prijs ↓'),
                            ('ratingHighLow', 'Rating'),
                          ].map((o) => chipOption(
                            o.$2,
                            _sortOption == o.$1,
                            () {
                              setState(() { _sortOption = o.$1; _applyFilterUpdate(); });
                              sheetSetState(() {});
                            },
                          )).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  // ── Sticky bottom CTA ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: FilledButton.styleFrom(
                            backgroundColor: GymiesColors.primary,
                            foregroundColor: GymiesColors.darkBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Toon $resultCount trainer${resultCount == 1 ? '' : 's'}',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
            style: GoogleFonts.sora(
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
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.sora(
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

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.loading,
    required this.onSearch,
    this.onChanged,
    this.onFilterTap,
    this.hasActiveFilters = false,
    this.clientCity,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSearch;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilterTap;
  final bool hasActiveFilters;
  final String? clientCity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue),
              decoration: InputDecoration(
                hintText: 'Zoek trainer, specialisme of stad...',
                hintStyle: GoogleFonts.sora(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: Icon(Icons.search_rounded, color: GymiesColors.darkBlue.withValues(alpha: 0.4), size: 22),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 44),
                suffixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFB8860B), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
              ),
              onChanged: onChanged,
              onSubmitted: (_) => onSearch(),
            ),
          ),
        ),
        if (onFilterTap != null) ...[
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [GymiesColors.darkBlue, GymiesColors.darkBlue.withValues(alpha: 0.9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: GymiesColors.darkBlue.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onFilterTap,
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        color: const Color(0xFFB8860B),
                        size: 22,
                      ),
                      if (hasActiveFilters)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: const Color(0xFFB8860B),
                              shape: BoxShape.circle,
                              border: Border.all(color: GymiesColors.darkBlue, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isClear
              ? Colors.grey.shade200
              : isActive
                  ? GymiesColors.darkBlue
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive && !isClear
                ? const Color(0xFFB8860B)
                : Colors.grey.shade200,
            width: isActive ? 1.5 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isClear
                ? Colors.grey.shade700
                : isActive
                    ? const Color(0xFFB8860B)
                    : Colors.grey.shade700,
          ),
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFB8860B),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB8860B).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB8860B).withValues(alpha: 0.15),
                  image: trainer.avatarUrl != null && trainer.avatarUrl!.isNotEmpty
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(trainer.avatarUrl!, errorListener: (_) {}),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: trainer.avatarUrl == null || trainer.avatarUrl!.isEmpty
                    ? Center(
                        child: Text(
                          trainer.nameOrEmail.isNotEmpty
                              ? trainer.nameOrEmail[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.sora(
                            fontSize: 20,
                            color: GymiesColors.darkBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              trainer.nameOrEmail.split(RegExp(r'\s+')).first,
              style: GoogleFonts.sora(
                fontSize: 11,
                color: GymiesColors.darkBlue,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? GymiesColors.darkBlue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
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

  static const _accent = Color(0xFFB8860B);
  static const _accentLight = Color(0xFFFFF8E1);

  @override
  Widget build(BuildContext context) {
    final categories = _DashboardScreenState._trainerSpecTokens(trainer)
        .take(3)
        .toList();

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: avatar + info + heart ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rounded-square avatar (72px)
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: _accentLight,
                      image: trainer.avatarUrl != null && trainer.avatarUrl!.isNotEmpty
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(trainer.avatarUrl!, errorListener: (_) {}),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: trainer.avatarUrl == null || trainer.avatarUrl!.isEmpty
                        ? Center(
                            child: Text(
                              trainer.nameOrEmail.isNotEmpty
                                  ? trainer.nameOrEmail[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.sora(
                                fontSize: 24,
                                color: _accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Info column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + badges
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                trainer.nameOrEmail,
                                style: GoogleFonts.sora(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: GymiesColors.darkBlue,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (trainer.trainerVerified)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _accentLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Verified',
                                  style: TextStyle(fontSize: 10, color: _accent, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Location
                        Text(
                          [trainer.city, trainer.region]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .toSet()
                              .join(' · ')
                          + (trainer.distanceKm != null ? ' · ${trainer.distanceKm!.toStringAsFixed(1)} km' : ''),
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Rating + beschikbaarheid
                        Row(
                          children: [
                            if (trainer.rating != null) ...[
                              ...List.generate(5, (i) {
                                final starValue = i + 1;
                                if (starValue <= trainer.rating!.floor()) {
                                  return Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade600);
                                } else if (starValue - 0.5 <= trainer.rating!) {
                                  return Icon(Icons.star_half_rounded, size: 14, color: Colors.amber.shade600);
                                }
                                return Icon(Icons.star_outline_rounded, size: 14, color: Colors.grey.shade300);
                              }),
                              const SizedBox(width: 4),
                              Text(
                                '${trainer.rating!.toStringAsFixed(1)}${trainer.reviewCount != null && trainer.reviewCount! > 0 ? ' (${trainer.reviewCount})' : ''}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Heart button
                  GestureDetector(
                    onTap: onToggleFavorite,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isFavorite ? Colors.red.shade50 : Colors.grey.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFavorite ? Colors.red.shade400 : Colors.grey.shade400,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              // ── Category pills + badge pills ──
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    ...categories.map((cat) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: GymiesColors.darkBlue.withValues(alpha: 0.7),
                        ),
                      ),
                    )),
                    ...TrainerBadges.forCard(trainer)
                        .map((b) => TrainerBadgePill(badge: b, compact: true)),
                  ],
                ),
              ],
              // ── Divider ──
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Colors.grey.shade200),
              ),
              // ── Price + CTAs ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Prijs
                  Flexible(
                    child: trainer.hourlyRateCents != null
                      ? RichText(
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '€${(trainer.hourlyRateCents! / 100).toStringAsFixed(0)}',
                                style: GoogleFonts.sora(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _accent,
                                ),
                              ),
                              TextSpan(
                                text: ' /sessie',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(
                          'Prijs op aanvraag',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                  // Dubbele CTA: Chat + Boek nu
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Bekijk',
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: GymiesColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Boek nu',
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                    ],
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

class _TrainerCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 140,
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8))),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 100,
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 8),
                  Row(children: List.generate(5, (_) =>
                    Padding(padding: const EdgeInsets.only(right: 2),
                      child: Container(width: 14, height: 14,
                        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle))))),
                  const SizedBox(height: 8),
                  Row(children: [
                    Container(height: 20, width: 50,
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(width: 4),
                    Container(height: 20, width: 60,
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6))),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
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
          style: GoogleFonts.sora(
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
                backgroundColor: const Color(0xFFB8860B),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Opnieuw zoeken'),
          style: OutlinedButton.styleFrom(
            foregroundColor: GymiesColors.darkBlue,
            side: const BorderSide(color: Color(0xFFB8860B)),
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
      backgroundColor: const Color(0xFFB8860B).withValues(alpha: 0.12),
      side: const BorderSide(color: Color(0xFFB8860B)),
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
                    ? const Color(0xFFB8860B)
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
