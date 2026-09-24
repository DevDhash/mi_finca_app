import 'package:flutter/material.dart';
import 'package:mi_finca_app/core/network/network_status.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_cache_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_provider.dart';
import 'package:mi_finca_app/features/animals/presentation/widgets/local_animal_photo_avatar.dart';

/// Local first; private remote rendering is mounted only when needed.
class AnimalPhotoAvatar extends StatelessWidget {
  const AnimalPhotoAvatar({
    super.key,
    required this.animalId,
    required this.localPhotoPath,
    required this.remotePhotoPath,
    required this.radius,
    required this.placeholder,
  });
  final String animalId;
  final String? localPhotoPath;
  final String? remotePhotoPath;
  final double radius;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) => LocalAnimalPhotoAvatar(
    localPhotoPath: localPhotoPath,
    radius: radius,
    placeholder: placeholder,
    fallback: remotePhotoPath == null
        ? null
        : _RemotePhoto(
            key: ValueKey((animalId, remotePhotoPath)),
            photo: (animalId: animalId, objectPath: remotePhotoPath!),
            diameter: radius * 2,
            placeholder: placeholder,
          ),
  );
}

class _RemotePhoto extends ConsumerStatefulWidget {
  const _RemotePhoto({
    super.key,
    required this.photo,
    required this.diameter,
    required this.placeholder,
  });
  final AnimalPhotoKey photo;
  final double diameter;
  final Widget placeholder;
  @override
  ConsumerState<_RemotePhoto> createState() => _RemotePhotoState();
}

class _RemotePhotoState extends ConsumerState<_RemotePhoto> {
  bool renewedAfterAccessError = false;

  Widget retryPlaceholder() => IconButton(
    tooltip: 'Reintentar foto',
    onPressed: () async {
      renewedAfterAccessError = false;
      if (ref.read(animalPhotoCacheServiceProvider) != null) {
        ref.invalidate(animalPhotoCacheProvider(widget.photo));
        try {
          final file = await ref.read(
            animalPhotoCacheProvider(widget.photo).future,
          );
          if (file != null) return;
        } catch (_) {
          // Keep the online signed-URL fallback available after cache failure.
        }
      }
      if (mounted) ref.invalidate(animalPhotoUrlProvider(widget.photo));
    },
    icon: widget.placeholder,
  );

  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(animalPhotoCacheProvider(widget.photo));
    if (cache.isLoading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final file = cache.asData?.value;
    if (file != null) {
      return ClipOval(
        child: Image.file(
          file,
          width: widget.diameter,
          height: widget.diameter,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stackTrace) => retryPlaceholder(),
        ),
      );
    }
    if (!ref.watch(photoNetworkAllowedProvider)) return retryPlaceholder();
    final url = ref.watch(animalPhotoUrlProvider(widget.photo));
    // Never show previous AsyncData during session changes/URL renewal.
    if (url.isLoading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final value = url.asData?.value;
    if (value == null) return retryPlaceholder();
    return ClipOval(
      child: Image.network(
        value,
        key: ValueKey(value),
        width: widget.diameter,
        height: widget.diameter,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stackTrace) {
          if (!renewedAfterAccessError &&
              error is NetworkImageLoadException &&
              (error.statusCode == 401 || error.statusCode == 403)) {
            renewedAfterAccessError = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) ref.invalidate(animalPhotoUrlProvider(widget.photo));
            });
          }
          return retryPlaceholder();
        },
      ),
    );
  }
}
