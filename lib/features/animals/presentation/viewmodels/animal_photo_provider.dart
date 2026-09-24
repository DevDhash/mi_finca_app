import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_photo_url_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AnimalPhotoKey = ({String animalId, String objectPath});

final animalPhotoUrlSourceProvider = Provider<AnimalPhotoUrlSource>(
  (ref) => SupabaseAnimalPhotoUrlSource(Supabase.instance.client),
);

final animalPhotoSessionProvider = StreamProvider.autoDispose<String?>((ref) {
  final source = ref.watch(animalPhotoUrlSourceProvider);
  // Subscribe before emitting the snapshot so logout cannot fall in a gap.
  final controller = StreamController<String?>();
  final subscription = source.authChanges.listen(
    controller.add,
    onError: controller.addError,
  );
  controller.add(source.currentUserId);
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});

/// Shared only in memory while watched; no signed URL enters SQLite or outbox.
final animalPhotoUrlProvider = FutureProvider.autoDispose
    .family<String, AnimalPhotoKey>((ref, key) async {
      final owner = ref.watch(animalPhotoSessionProvider).asData?.value;
      final source = ref.watch(animalPhotoUrlSourceProvider);
      if (owner == null || source.currentUserId != owner) {
        throw StateError('No hay una sesión activa para esta foto.');
      }
      final started = DateTime.now();
      final url = await source.sign(key.animalId, key.objectPath, 600);
      if (!ref.mounted || source.currentUserId != owner) {
        throw StateError('La sesión cambió mientras se cargaba la foto.');
      }
      // Renew before expiry, only while a widget watches this photo.
      final remaining =
          const Duration(seconds: 570) - DateTime.now().difference(started);
      final timer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        ref.invalidateSelf,
      );
      ref.onDispose(timer.cancel);
      return url;
    }, retry: (_, _) => null);
