import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_remote_payload.dart';
import 'package:uuid/uuid.dart';

/// Durable, account-scoped cache. It never modifies animals or the outbox.
class AnimalPhotoCache {
  AnimalPhotoCache({
    required this.root,
    required this.currentOwner,
    required this.download,
    required this.validate,
    this.maxBytes = 100 * 1024 * 1024,
  });
  final Future<Directory> Function() root;
  final Future<String?> Function() currentOwner;
  final Future<Uint8List> Function(String owner, String path) download;
  final Future<void> Function(Uint8List) validate;
  final int maxBytes;
  final _active = <String, Future<File?>>{};
  final _prepared = <String, Future<void>>{};
  final _generations = <String, int>{};

  Future<File?> get(
    String animalId,
    String objectPath, {
    required bool allowNetwork,
  }) async {
    final owner = await currentOwner();
    if (owner == null) return null;
    AnimalRemotePayload.validatedPhotoPath(objectPath, owner, animalId);
    final key = '$owner|$objectPath';
    return _active[key] ??= _load(owner, objectPath, allowNetwork).whenComplete(
      () {
        _active.remove(key);
      },
    );
  }

  Future<void> _checkOwner(String owner, int generation) async {
    if (await currentOwner() != owner ||
        (_generations[owner] ?? 0) != generation) {
      throw StateError('La sesión de la foto cambió.');
    }
  }

  Future<File?> _load(String owner, String path, bool allowNetwork) async {
    final generation = _generations[owner] ?? 0;
    final directory = Directory('${(await root()).path}/$owner');
    await (_prepared[owner] ??= _removeInterruptedFiles(directory));
    final digest = sha256.convert(utf8.encode(path));
    final file = File('${directory.path}/$digest.image');
    await _checkOwner(owner, generation);
    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        await validate(bytes);
        await _checkOwner(owner, generation);
        await file.setLastModified(DateTime.now());
        return file;
      } on StateError {
        rethrow;
      } catch (_) {
        if (await file.exists()) await file.delete();
      }
    }
    if (!allowNetwork) return null;
    final bytes = await download(
      owner,
      path,
    ).timeout(const Duration(seconds: 20));
    if (bytes.isEmpty ||
        bytes.length > 6 * 1024 * 1024 ||
        bytes.length > maxBytes) {
      throw const FormatException(
        'La foto supera el tamaño de caché admitido.',
      );
    }
    await validate(bytes);
    await _checkOwner(owner, generation);
    await directory.create(recursive: true);
    final temporary = File('${file.path}.${const Uuid().v4()}.part');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await _checkOwner(owner, generation);
      await temporary.rename(file.path);
      await _checkOwner(owner, generation);
      await _trim(directory, file);
      return file;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  // Runs once before any writer in this process can create a temporary file.
  Future<void> _removeInterruptedFiles(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entry in directory.list()) {
      if (entry is File && entry.path.endsWith('.part')) await entry.delete();
    }
  }

  Future<void> _trim(Directory directory, File keep) async {
    final files = <({File file, FileStat stat})>[];
    await for (final entry in directory.list()) {
      if (entry is File && entry.path.endsWith('.image')) {
        files.add((file: entry, stat: await entry.stat()));
      }
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var total = files.fold<int>(0, (sum, entry) => sum + entry.stat.size);
    for (final entry in files) {
      if (total <= maxBytes) break;
      if (entry.file.path != keep.path && await entry.file.exists()) {
        await entry.file.delete();
        total -= entry.stat.size;
      }
    }
  }

  Future<void> clearOwner(String owner) async {
    _generations[owner] = (_generations[owner] ?? 0) + 1;
    final running = [
      for (final entry in _active.entries)
        if (entry.key.startsWith('$owner|'))
          entry.value.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    ];
    await Future.wait(running);
    _prepared.remove(owner);
    final directory = Directory('${(await root()).path}/$owner');
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
