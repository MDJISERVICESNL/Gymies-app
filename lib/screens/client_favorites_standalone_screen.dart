import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trainer.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'client_trainer_profile_screen.dart';
import 'widgets/trainer_state_views.dart';

const _kFavoritesKey = 'gymies_favorite_trainer_ids';

/// Zelfstandig favorietenscherm — laadt trainers en favorieten-IDs zelf,
/// zonder callbacks van een parent widget.
class ClientFavoritesStandaloneScreen extends StatefulWidget {
  const ClientFavoritesStandaloneScreen({super.key});

  @override
  State<ClientFavoritesStandaloneScreen> createState() =>
      _ClientFavoritesStandaloneScreenState();
}

class _ClientFavoritesStandaloneScreenState
    extends State<ClientFavoritesStandaloneScreen> {
  List<Trainer> _trainers = [];
  Set<String> _favoriteIds = {};
  bool _loading = true;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();
  String _specialtyFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final prefs = await SharedPreferences.getInstance();

      // Probeer server-favorieten; fallback naar local.
      List<String> ids;
      try {
        ids = await api.getFavoriteTrainerIds();
        // Sync server → local cache
        await prefs.setStringList(_kFavoritesKey, ids);
      } catch (_) {
        ids = prefs.getStringList(_kFavoritesKey) ?? [];
      }

      final trainers = await api.getTrainers();
      if (!mounted) return;
      // Verwijder orphaned IDs die niet meer in de trainerlijst bestaan
      final validIds = {for (final t in trainers) t.userId};
      final cleanedIds = ids.where((id) => validIds.contains(id)).toSet();
      if (cleanedIds.length != ids.length) {
        await prefs.setStringList(_kFavoritesKey, cleanedIds.toList());
      }
      setState(() {
        _trainers = trainers;
        _favoriteIds = cleanedIds;
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
        _error = 'Kon favorieten niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite(Trainer trainer) async {
    final api = context.read<GymiesApi>();
    final prefs = await SharedPreferences.getInstance();
    final adding = !_favoriteIds.contains(trainer.userId);
    setState(() {
      if (adding) {
        _favoriteIds.add(trainer.userId);
      } else {
        _favoriteIds.remove(trainer.userId);
      }
    });
    // Local cache bijwerken
    await prefs.setStringList(_kFavoritesKey, _favoriteIds.toList());
    // Server sync (fire-and-forget)
    try {
      if (adding) {
        await api.addFavoriteTrainer(trainer.userId);
      } else {
        await api.removeFavoriteTrainer(trainer.userId);
      }
    } catch (_) {
      // Server fout — local state blijft behouden
    }
  }

  Future<void> _openTrainer(Trainer trainer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientTrainerProfileScreen(trainerId: trainer.userId),
      ),
    );
  }

  List<Trainer> _favorites() {
    final byId = {for (final t in _trainers) t.userId: t};
    return _favoriteIds.map((id) => byId[id]).whereType<Trainer>().toList();
  }

  List<String> _specialties(List<Trainer> favorites) {
    final set = <String>{};
    for (final t in favorites) {
      final s = (t.specialty ?? '').trim();
      if (s.isNotEmpty) set.add(s);
    }
    return ['all', ...set.toList()..sort()];
  }

  List<Trainer> _visible(List<Trainer> favorites) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return favorites.where((t) {
      final matchesSpec = _specialtyFilter == 'all' ||
          (t.specialty ?? '') == _specialtyFilter;
      if (!matchesSpec) return false;
      if (query.isEmpty) return true;
      final hay =
          '${t.nameOrEmail} ${t.specialty ?? ''} ${t.region ?? ''}'.toLowerCase();
      return hay.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Favorieten',
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
          Expanded(
            child: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: Builder(
          builder: (context) {
            final favorites = _favorites();
            if (favorites.isEmpty) {
              return ListView(
                padding: EdgeInsets.zero,
                children: const [
                  TrainerEmptyState(
                    icon: Icons.favorite_outline_rounded,
                    title: 'Nog geen favorieten',
                    subtitle:
                        'Voeg trainers toe aan je favorieten via hun profiel.',
                    padding: EdgeInsets.all(32),
                  ),
                ],
              );
            }
            final specialties = _specialties(favorites);
            final visible = _visible(favorites);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Zoek op naam, specialiteit of regio',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (specialties.length > 1) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: specialties.map((s) {
                        final selected = _specialtyFilter == s;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(s == 'all' ? 'Alles' : s),
                            selected: selected,
                            onSelected: (_) {
                              Haptics.selection();
                              setState(() => _specialtyFilter = s);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const TrainerEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Geen resultaten',
                    subtitle: 'Pas je zoekterm of filter aan.',
                    padding: EdgeInsets.symmetric(vertical: 36),
                  )
                else
                  ...visible.map((trainer) => _TrainerCard(
                        trainer: trainer,
                        isFavorite: _favoriteIds.contains(trainer.userId),
                        onTap: () {
                          Haptics.selection();
                          _openTrainer(trainer);
                        },
                        onToggleFavorite: () {
                          Haptics.light();
                          _toggleFavorite(trainer);
                        },
                      )),
              ],
            );
          },
        ),
      ),
          ),
        ],
      ),
    );
  }
}

class _TrainerCard extends StatelessWidget {
  const _TrainerCard({
    required this.trainer,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final Trainer trainer;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _Avatar(trainer: trainer),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trainer.nameOrEmail,
                          style: GoogleFonts.sora(
                            color: GymiesColors.darkBlue,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((trainer.specialty ?? '').isNotEmpty ||
                            (trainer.region ?? '').isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            [
                              if ((trainer.specialty ?? '').isNotEmpty) trainer.specialty!,
                              if ((trainer.region ?? '').isNotEmpty) trainer.region!,
                            ].join(' · '),
                            style: GoogleFonts.sora(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                      color: isFavorite ? Colors.red.shade400 : Colors.grey.shade400,
                    ),
                    onPressed: onToggleFavorite,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.trainer});
  final Trainer trainer;

  @override
  Widget build(BuildContext context) {
    final url = trainer.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: CachedNetworkImageProvider(url, errorListener: (_) {}),
        backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
      );
    }
    final initial = trainer.nameOrEmail.isNotEmpty
        ? trainer.nameOrEmail[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 26,
      backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
      child: Text(
        initial,
        style: GoogleFonts.sora(
          color: GymiesColors.darkBlue,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}
