import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';

void main() {
  for (final pastureType in [
    'Setaria',
    'Setarea histórica',
    'Pastura no especificada',
  ]) {
    test(
      'offline create and edit survive database restart: $pastureType',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'pastureType-offline-',
        );
        final file = File('${dir.path}/paddocks.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        addTearDown(() async {
          await db.close();
          await dir.delete(recursive: true);
        });
        await db.writeSetting('session', jsonEncode({'id': 'owner'}));
        final now = DateTime.utc(2026, 10, 22);
        await PaddockLocalDataSource(db).save(
          Paddock(
            id: 'paddock',
            name: 'Norte',
            areaHectares: 2,
            pastureType: pastureType,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(
          (await PaddockLocalDataSource(db).getAll()).single.pastureType,
          pastureType,
        );
        expect(
          (await db.readPendingRecords()).single.payload['pastureType'],
          pastureType,
        );
        await PaddockLocalDataSource(db).edit(
          'paddock',
          PaddockPatch({
            PaddockField.pastureType: 'Otra pastura personalizada',
          }),
        );
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final paddock = (await PaddockLocalDataSource(db).getAll()).single;
        expect(paddock.pastureType, 'Otra pastura personalizada');
        expect(paddock.name, 'Norte');
        final patches = await db.paddockPatches('owner', entityId: 'paddock');
        expect(patches.single.payload['fields'], {
          'pastureType': 'Otra pastura personalizada',
        });
      },
    );
  }
}
