import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/api_client.dart';
import '../../services/gymies_api.dart';
import '../../services/subscription_entitlements_service.dart';
import '../../theme/gymies_theme.dart';
import '../../utils/haptics.dart';
import 'gymies_dialog.dart';
import '../trainer_subscription_screen.dart';

/// Max duur video op profiel: 30 sec.
const Duration kMaxVideoDuration = Duration(seconds: 30);

Future<Duration?> _getVideoDuration(String path) async {
  final controller = VideoPlayerController.file(File(path));
  try {
    await controller.initialize();
    final duration = controller.value.duration;
    await controller.dispose();
    return duration;
  } catch (e) {
    // Fail-open: Video duration check failed
    if (kDebugMode) debugPrint('[TrainerMediaSection] Get video duration failed: $e');
    try {
      await controller.dispose();
    } catch (_) {
      // Cleanup disposal error, continue
    }
    return null;
  }
}

/// Sectie voor trainers om foto's en video's toe te voegen voor Story en Media Gallery.
/// Pro: max 5 foto + 1 video (gallery), 1 story. Elite: onbeperkt.
class TrainerMediaSection extends StatefulWidget {
  const TrainerMediaSection({super.key});

  @override
  State<TrainerMediaSection> createState() => _TrainerMediaSectionState();
}

class _TrainerMediaSectionState extends State<TrainerMediaSection> {
  List<Map<String, dynamic>> _allMedia = [];
  bool _loading = true;
  String? _error;
  bool _uploading = false;
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  bool _deleting = false;

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
      final items = await context.read<GymiesApi>().getTrainerMedia();
      if (mounted) {
        setState(() {
          _allMedia = items;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _allMedia = [];
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _allMedia = [];
          _error = S.of(context).konMediaNietLaden;
          _loading = false;
        });
      }
    }
  }

  String _url(Map<String, dynamic> m) =>
      (m['url'] ?? m['thumbnail_url'] ?? m['media_url'] ?? '').toString();

  bool _isVideo(Map<String, dynamic> m) {
    final t = (m['type'] ?? m['media_type'] ?? '').toString().toLowerCase();
    return t == 'video' || _url(m).toLowerCase().contains('.mp4');
  }

  String _usage(Map<String, dynamic> m) =>
      (m['usage'] ?? m['usage_type'] ?? 'gallery').toString();

  String _id(Map<String, dynamic> m) =>
      (m['id'] ?? m['media_id'] ?? '').toString();

  List<Map<String, dynamic>> _filterByUsage(String usage) =>
      _allMedia.where((m) => _usage(m) == usage).toList();

  int get _storyLimit {
    final ent = context.read<SubscriptionEntitlementsService>();
    final limit = ent.getLimit('profile_stories');
    return limit < 0 ? 999 : limit;
  }

  int get _galleryPhotoLimit {
    final ent = context.read<SubscriptionEntitlementsService>();
    final limit = ent.getLimit('profile_photos');
    // Fallback naar profile_videos als profile_photos niet geconfigureerd is (0).
    if (limit != 0) return limit < 0 ? 999 : limit;
    final videoLimit = ent.getLimit('profile_videos');
    return videoLimit < 0 ? 999 : 5;
  }

  int get _galleryVideoLimit {
    final ent = context.read<SubscriptionEntitlementsService>();
    final limit = ent.getLimit('profile_videos');
    return limit < 0 ? 999 : (limit > 0 ? limit : 0);
  }

  bool get _canUseMedia {
    final ent = context.read<SubscriptionEntitlementsService>();
    return ent.getLimit('profile_stories') != 0 ||
        ent.getLimit('profile_videos') != 0;
  }

  String get _tierName {
    final ent = context.read<SubscriptionEntitlementsService>();
    final tier = ent.tier?.toLowerCase() ?? 'starter';
    if (tier.contains('pro_plus') || tier.contains('proplus')) return 'Pro+';
    if (tier.contains('pro')) return 'Pro';
    return 'Starter';
  }

  bool get _isStarterTier {
    final ent = context.read<SubscriptionEntitlementsService>();
    final tier = ent.tier?.toLowerCase() ?? 'starter';
    return !tier.contains('pro');
  }

  // ignore: unused_element
  bool get _isProTier {
    final ent = context.read<SubscriptionEntitlementsService>();
    final tier = ent.tier?.toLowerCase() ?? 'starter';
    return tier.contains('pro') && !tier.contains('pro_plus') && !tier.contains('proplus');
  }

  // ignore: unused_element
  bool get _isProPlusTier {
    final ent = context.read<SubscriptionEntitlementsService>();
    final tier = ent.tier?.toLowerCase() ?? 'starter';
    return tier.contains('pro_plus') || tier.contains('proplus') || tier == 'studio';
  }

  Future<void> _addMedia(String usage, {bool preferVideo = false}) async {
    if (!_canUseMedia || _uploading) {
      if (_isStarterTier) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(S.of(context).mediaIsNietBeschikbaarVoorStarterPlanUpgradeNaarPro),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
      return;
    }

    final story = _filterByUsage('story');
    final gallery = _filterByUsage('gallery');
    final galleryPhotos = gallery.where((m) => !_isVideo(m)).length;
    final galleryVideos = gallery.where((m) => _isVideo(m)).length;

    if (usage == 'story' && story.length >= _storyLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Max $_storyLimit story bereikt. Upgrade naar $_tierName voor meer.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    if (usage == 'gallery') {
      if (galleryPhotos >= _galleryPhotoLimit && !preferVideo) {
        final photosAllowed = _galleryPhotoLimit;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Max $photosAllowed foto\'s bereikt voor $_tierName. Verwijder een foto of upgrade.'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
        return;
      }
      if (galleryVideos >= _galleryVideoLimit && preferVideo) {
        final videosAllowed = _galleryVideoLimit;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Max $videosAllowed video\'s bereikt voor $_tierName. Verwijder een video of upgrade.'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
        return;
      }
    }

    final picker = ImagePicker();
    final api = context.read<GymiesApi>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      XFile? file;
      String type = 'photo';
      if (preferVideo) {
        file = await picker.pickVideo(source: ImageSource.gallery);
        type = 'video';
      } else {
        // imageQuality + maxWidth/maxHeight zorgen ervoor dat:
        // 1. HEIC → JPEG conversie op iOS (voorkomt "invalid types")
        // 2. Foto automatisch verkleind wordt zodat "entity too large" niet
        //    meer voorkomt bij hoge-resolutie foto's van moderne telefoons.
        file = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 80,
        );
      }
      if (file == null || !mounted) return;
      final path = file.path;
      if (path.isEmpty) return;

      if (preferVideo) {
        setState(() => _uploading = true);
        final duration = await _getVideoDuration(path);
        if (!mounted) return;
        setState(() => _uploading = false);
        if (duration == null) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(S.of(context).videoKonNietWordenGelezenKiesEenAndere),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (duration > kMaxVideoDuration) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(S.of(context).videoMagMax30SecondenZijnOpJeProfiel),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }

      // Veiligheidsnet: controleer bestandsgrootte (max 5 MB voor foto's)
      if (type == 'photo') {
        final fileSize = await File(path).length();
        if (fileSize > 5 * 1024 * 1024) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(
                S.of(context).fotoIsTeGrootMax5
                S.of(context).pasDeResolutieAan,
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }

      setState(() => _uploading = true);
      await api.postTrainerMedia(
        filePath: path,
        type: type,
        usage: usage,
      );
      if (mounted) {
        await _load();
        setState(() => _uploading = false);
        messenger?.showSnackBar(
          const SnackBar(content: Text(S.of(context).mediaToegevoegd)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        messenger?.showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _uploading = false);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(S.of(context).uploadMisluktProbeerOpnieuw),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeMedia(Map<String, dynamic> item) async {
    final id = _id(item);
    if (id.isEmpty) return;
    final api = context.read<GymiesApi>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await GymiesDialog.destructive(
      context,
      title: S.of(context).mediaVerwijderenTitle,
      message: S.of(context).weetJeZekerDatJeDit,
      icon: Icons.delete_rounded,
      confirmLabel: S.of(context).verwijderen,
    );
    if (confirmed != true || !mounted) return;
    try {
      await api.deleteTrainerMedia(id);
      if (mounted) {
        await _load();
        messenger?.showSnackBar(
          const SnackBar(content: Text(S.of(context).mediaVerwijderd)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _setFeatured(String mediaId) async {
    final api = context.read<GymiesApi>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await api.setFeaturedMedia(mediaId);
      if (mounted) {
        await _load();
        messenger?.showSnackBar(
          const SnackBar(content: Text(S.of(context).mediaAlsFeaturedIngesteld)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteBulk() async {
    if (_selectedIds.isEmpty) return;
    final api = context.read<GymiesApi>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await GymiesDialog.destructive(
      context,
      title: S.of(context).mediaVerwijderen,
      message: 'Weet je zeker dat je ${_selectedIds.length} item(s) wilt verwijderen?',
      icon: Icons.delete_rounded,
      confirmLabel: S.of(context).verwijderen,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await api.deleteTrainerMediaBulk(_selectedIds.toList());
      if (mounted) {
        await _load();
        setState(() {
          _selectMode = false;
          _selectedIds.clear();
          _deleting = false;
        });
        messenger?.showSnackBar(
          SnackBar(content: Text(S.of(context).mediaItemsVerwijderd(_selectedIds.length.toString()))),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        messenger?.showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(S.of(context).verwijderenMisluktProbeerOpnieuw),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show upgrade prompt for Starter tier
    if (!_canUseMedia) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: Colors.blue.shade700, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.of(context).fotos & video\S.of(context).sNietBeschikbaar,
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        S.of(context).mediaFeaturesZijnAlleenBeschikbaarVoorProEnProPlannen,
                        style: GoogleFonts.sora(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TrainerSubscriptionScreen()),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
              ),
              child: Text(S.of(context).upgradeToProAction, style: GoogleFonts.sora(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _load,
              child: Text(S.of(context).retryAction),
            ),
          ],
        ),
      );
    }

    final story = _filterByUsage('story');
    final gallery = _filterByUsage('gallery');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).fotos & video\S.of(context).sOpJeProfiel,
                    style: GymiesTextStyles.h2,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.of(context).voegFotos en video\S.of(context).sToeVoorJeStoryEn,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () {
                Haptics.selection();
                setState(() {
                  _selectMode = !_selectMode;
                  if (!_selectMode) {
                    _selectedIds.clear();
                  }
                });
              },
              style: TextButton.styleFrom(
                backgroundColor: _selectMode ? GymiesColors.primary.withOpacity(0.2) : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                S.of(context).selecteer,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _selectMode ? GymiesColors.darkBlue : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MediaSubSection(
          title: 'Story',
          subtitle: 'Video max 30 sec • Pro: 1 • Elite: onbeperkt',
          items: story,
          isVideo: _isVideo,
          url: _url,
          limit: _storyLimit,
          onAdd: () => _addMedia('story'),
          onAddVideo: () => _addMedia('story', preferVideo: true),
          onRemove: _removeMedia,
          onSetFeatured: _setFeatured,
          uploading: _uploading,
          selectMode: _selectMode,
          selectedIds: _selectedIds,
          onSelectionChanged: (id, selected) {
            setState(() {
              if (selected) {
                _selectedIds.add(id);
              } else {
                _selectedIds.remove(id);
              }
            });
          },
        ),
        const SizedBox(height: 20),
        _MediaSubSection(
          title: 'Media Gallery',
          subtitle: 'Video max 60 sec • Pro: 5 foto\'s + 1 video • Elite: onbeperkt',
          items: gallery,
          isVideo: _isVideo,
          url: _url,
          limit: _galleryPhotoLimit + _galleryVideoLimit,
          onAdd: () => _addMedia('gallery'),
          onAddVideo: () => _addMedia('gallery', preferVideo: true),
          onRemove: _removeMedia,
          onSetFeatured: _setFeatured,
          uploading: _uploading,
          selectMode: _selectMode,
          selectedIds: _selectedIds,
          onSelectionChanged: (id, selected) {
            setState(() {
              if (selected) {
                _selectedIds.add(id);
              } else {
                _selectedIds.remove(id);
              }
            });
          },
        ),
        if (_selectMode && _selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _deleting ? null : _deleteBulk,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.delete_rounded),
                label: Text(
                  'Verwijder geselecteerde (${_selectedIds.length})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MediaSubSection extends StatelessWidget {
  const _MediaSubSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.isVideo,
    required this.url,
    required this.limit,
    required this.onAdd,
    required this.onAddVideo,
    required this.onRemove,
    required this.onSetFeatured,
    required this.uploading,
    required this.selectMode,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> items;
  final bool Function(Map<String, dynamic>) isVideo;
  final String Function(Map<String, dynamic>) url;
  final int limit;
  final VoidCallback onAdd;
  final VoidCallback onAddVideo;
  final void Function(Map<String, dynamic>) onRemove;
  final void Function(String) onSetFeatured;
  final bool uploading;
  final bool selectMode;
  final Set<String> selectedIds;
  final void Function(String, bool) onSelectionChanged;

  String _id(Map<String, dynamic> m) =>
      (m['id'] ?? m['media_id'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(title, style: GymiesTextStyles.h3, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                S.of(context).sleepItemsOmDeVolgordeTeWijzigen,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ...items.map((m) {
                final itemId = _id(m);
                return _MediaThumb(
                  url: url(m),
                  isVideo: isVideo(m),
                  onRemove: () => onRemove(m),
                  onSetFeatured: () => onSetFeatured(itemId),
                  selectMode: selectMode,
                  isSelected: selectedIds.contains(itemId),
                  onSelectionChanged: (selected) => onSelectionChanged(itemId, selected),
                );
              }),
              if (items.length < limit) ...[
                _AddMediaButton(
                  label: S.of(context).photoLabel,
                  icon: Icons.photo_library_outlined,
                  onTap: uploading ? null : onAdd,
                ),
                _AddMediaButton(
                  label: S.of(context).galleryLabel,
                  icon: Icons.videocam_outlined,
                  onTap: uploading ? null : onAddVideo,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({
    required this.url,
    required this.isVideo,
    required this.onRemove,
    required this.onSetFeatured,
    required this.selectMode,
    required this.isSelected,
    required this.onSelectionChanged,
  });

  final String url;
  final bool isVideo;
  final VoidCallback onRemove;
  final VoidCallback onSetFeatured;
  final bool selectMode;
  final bool isSelected;
  final Function(bool) onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.trim().isNotEmpty;
    return GestureDetector(
      onLongPress: () {
        Haptics.selection();
        onSelectionChanged(!isSelected);
      },
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
              border: selectMode && isSelected
                  ? Border.all(color: GymiesColors.darkBlue, width: 2)
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: hasUrl
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                    cacheHeight: 160,
                    errorWidget: (_, _, _) => Center(
                      child: Icon(
                        isVideo ? Icons.videocam : Icons.photo,
                        size: 32,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      isVideo ? Icons.videocam : Icons.photo,
                      size: 32,
                      color: Colors.grey,
                    ),
                  ),
          ),
          if (isVideo)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
              ),
            ),
          if (selectMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? GymiesColors.darkBlue : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 12)
                    : null,
              ),
            )
          else ...[
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onSetFeatured,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star, color: Colors.white, size: 14),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddMediaButton extends StatelessWidget {
  const _AddMediaButton({
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: GymiesColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: GymiesColors.primary.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: GymiesColors.darkBlue),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: GymiesColors.darkBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
