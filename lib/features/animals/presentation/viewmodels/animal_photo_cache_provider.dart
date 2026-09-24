import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/core/network/network_status.dart';
import 'package:mi_finca_app/features/animals/data/services/animal_photo_cache.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_photo_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Nullable for local-only hosts/tests which intentionally disable disk caching.
final animalPhotoCacheServiceProvider = Provider<AnimalPhotoCache?>((ref) {
  final database = ref.watch(databaseProvider);
  return AnimalPhotoCache(
    root: () async => Directory(
      '${(await getApplicationSupportDirectory()).path}/animal_photo_cache',
    ),
    currentOwner: () async {
      if (database.isClosingSession) return null;
      final raw = await database.readSetting('session');
      return raw == null ? null : (jsonDecode(raw) as Map)['id'] as String?;
    },
    download: (owner, path) async {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != owner) {
        throw const AuthException('Inicia sesión para descargar la foto.');
      }
      return client.storage.from('animal-photos').download(path);
    },
    validate: (bytes) async {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1600);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    },
  );
});

final animalPhotoCacheProvider = FutureProvider.autoDispose
    .family<File?, AnimalPhotoKey>(
      (ref, key) async {
        ref.watch(animalPhotoSessionProvider);
        final allowNetwork = ref.watch(photoNetworkAllowedProvider);
        final cache = ref.watch(animalPhotoCacheServiceProvider);
        if (cache == null) return null;
        return cache.get(
          key.animalId,
          key.objectPath,
          allowNetwork: allowNetwork,
        );
      },
      retry: (attempt, error) =>
          attempt < 4 &&
              error is! FormatException &&
              error is! StateError &&
              error is! AuthException
          ? Duration(seconds: 5 * (1 << attempt))
          : null,
    );
