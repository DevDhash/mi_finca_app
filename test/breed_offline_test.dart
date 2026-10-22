import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';

void main() {
  for (final breed in [
    'Brahman',
    'Mi cruce local ágil',
    'Raza no especificada',
  ]) {
    test('offline create and edit survive database restart: $breed', () async {
      final dir = await Directory.systemTemp.createTemp('breed-offline-');
      final file = File('${dir.path}/animals.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      await db.writeSetting('session', jsonEncode({'id': 'owner'}));
      final now = DateTime.utc(2026, 10, 22);
      await AnimalLocalDataSource(db).save(
        Animal(
          id: 'animal',
          code: 'A1',
          type: 'Vaca',
          breed: breed,
          sex: 'Hembra',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      expect((await AnimalLocalDataSource(db).getAll()).single.breed, breed);
      expect((await db.readPendingRecords()).single.payload['breed'], breed);
      await AnimalLocalDataSource(db).edit(
        'animal',
        AnimalPatch({AnimalField.breed: 'Otra raza personalizada'}),
      );
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      final animal = (await AnimalLocalDataSource(db).getAll()).single;
      expect(animal.breed, 'Otra raza personalizada');
      expect(animal.code, 'A1');
      final patches = await db.animalPatches('owner', entityId: 'animal');
      expect(patches.single.payload['fields'], {
        'breed': 'Otra raza personalizada',
      });
    });
  }
}
