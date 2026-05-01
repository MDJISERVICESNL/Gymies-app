import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../services/api_client.dart';
import '../../services/gymies_api.dart';
import '../../services/subscription_entitlements_service.dart';
import '../../theme/gymies_theme.dart';

/// Max duur video op profiel: 30 sec.
const Duration kMaxVideoDuration = Duration(seconds: 30);

Future<Duration?> _getVideoDuration(String path) async {
  final controller = VideoPlayerController.file(File(path));
  try {
    await controller.initialize();
    final duration = controller.value.duration;
    await controller.dispose();
    return duration;
  } catch (_) {
    try {
      await controller.dispose();
    } catch (_) {}
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
          _error = 'Kon media niet laden.';
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

  Future<void> _addMedia(String usage, {bool preferVideo = false}) async {
    if (!_canUseMedia || _uploading) return;
    final story = _filterByUsage('story');
    final gallery = _filterByUsage('gallery');
    final galleryPhotos = gallery.where((m) => !_isVideo(m)).length;
    final galleryVideos = gallery.where((m) => _isVideo(m)).length;

    if (usage == 'story' && story.length >= _storyLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Max $_storyLimit story. Upgrade voor meer.')),
      );
      return;
    }
    if (usage == 'gallery') {
      if (galleryPhotos >= _galleryPhotoLimit && !preferVideo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Max 5 foto\'s in gallery. Voeg een video toe.'),
          ),
        );
        return;
      }
      if (galleryVideos >= _galleryVideoLimit && preferVideo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Max 1 video in gallery (Pro). Upgrade voor meer.'),
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
        // imageQuality: 90 forceert JPEG-conversie op iOS (HEIC → JPEG) zodat
        // "selected media invalid types" niet meer voorkomt bij HEIC-foto's.
        file = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
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
              content: Text('Video kon niet worden gelezen. Kies een andere.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (duration > kMaxVideoDuration) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Video mag max. 30 seconden zijn op je profiel.'),
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
          const SnackBar(content: Text('Media toegevoegd')),
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
            content: Text('Upload mislukt. Probeer opnieuw.'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Media verwijderen'),
        content: const Text('Weet je zeker dat je dit wilt verwijderen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await api.deleteTrainerMedia(id);
      if (mounted) {
        await _load();
        messenger?.showSnackBar(
          const SnackBar(content: Text('Media verwijderd')),
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

  @override
  Widget build(BuildContext context) {
    if (!_canUseMedia) return const SizedBox.shrink();

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
              child: const Text('Opnieuw proberen'),
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
        Text(
          'Foto\'s & video\'s op je profiel',
          style: GymiesTextStyles.h2,
        ),
        const SizedBox(height: 6),
        Text(
          'Voeg foto\'s en video\'s toe voor je Story en de Media Gallery. Video\'s max. 30 sec. Klanten zien dit op je openbare profiel.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
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
          uploading: _uploading,
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
          uploading: _uploading,
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
    required this.uploading,
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
  final bool uploading;

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
            children: [
              Text(title, style: GymiesTextStyles.h3),
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ...items.map((m) => _MediaThumb(
                    url: url(m),
                    isVideo: isVideo(m),
                    onRemove: () => onRemove(m),
                  )),
              if (items.length < limit) ...[
                _AddMediaButton(
                  label: 'Foto',
                  icon: Icons.photo_library_outlined,
                  onTap: uploading ? null : onAdd,
                ),
                _AddMediaButton(
                  label: 'Video',
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
  });

  final String url;
  final bool isVideo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.trim().isNotEmpty;
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasUrl
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
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
        Positioned(
          top: 4,
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
          color: GymiesColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: GymiesColors.primary.withValues(alpha: 0.5),
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
