import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/usecases/calculate_paddock_rotation.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late PaddockLocalDataSource local;
  void open() {
    db = AppDatabase(NativeDatabase(File('${dir.path}/db')));
    local = PaddockLocalDataSource(db);
  }

  Future<void> seed(String id, int order) => local.save(
    Paddock(
      id: id,
      name: 'Nombre $id',
      areaHectares: 1,
      rotationOrder: order,
      status: 'Disponible',
      requiredRestDays: 1,
      lastGrazingEndDate: DateTime.utc(2025),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
    pending: false,
    verifiedRemoteOwner: 'owner',
  );
  Future<void> terminal(String id) => db.mergeRemoteTombstones('owner', [
    RemoteTombstone(
      collection: 'paddocks',
      id: id,
      ownerId: 'owner',
      operationId: 'delete-$id',
      deletedAt: DateTime.utc(2026),
    ),
  ]);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('d3-history');
    open();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'cached tombstone retains history and stays outside active list',
    () async {
      await seed('p', 1);
      await terminal('p');
      expect(await local.getAll(), isEmpty);
      expect(
        (await local.resolveHistory({'p'}))['p']!.label,
        'Nombre p (eliminado)',
      );
    },
  );
  test(
    'minimal terminal and absent identity have distinct stable labels',
    () async {
      await terminal('minimal');
      final refs = await local.resolveHistory({'minimal', 'unknown'});
      expect(refs['minimal']!.label, 'Potrero minimal (eliminado)');
      expect(refs['unknown']!.label, 'Potrero unknown');
      expect(refs['unknown']!.isDeleted, false);
    },
  );
  test('foreign owner cannot expose name or terminal metadata', () async {
    await seed('p', 1);
    await terminal('p');
    await db.writeSetting('session', jsonEncode({'id': 'other'}));
    final ref = (await local.resolveHistory({'p'}))['p']!;
    expect(ref.name, isNull);
    expect(ref.isDeleted, false);
    expect(ref.label, 'Potrero p');
  });
  test('history requires local owner', () async {
    await db.deleteSetting('session');
    await expectLater(local.resolveHistory({'p'}), throwsStateError);
  });
  test('SQLite restart offline retains name and terminal state', () async {
    await seed('p', 1);
    await terminal('p');
    await db.close();
    open();
    expect(
      (await local.resolveHistory({'p'}))['p']!.label,
      'Nombre p (eliminado)',
    );
    expect(await local.getAll(), isEmpty);
  });
  test('history reads never change records or pending outbox', () async {
    await seed('p', 1);
    await terminal('p');
    final before = await db.customSelect('SELECT * FROM records').get();
    final pending = await db.pendingCount();
    await local.resolveHistory({'p', 'missing'});
    final after = await db.customSelect('SELECT * FROM records').get();
    expect(
      after.map((r) => r.data).toList(),
      before.map((r) => r.data).toList(),
    );
    expect(await db.pendingCount(), pending);
  });
  test(
    'deleting order two preserves gaps dates and operational rotation',
    () async {
      for (var i = 1; i <= 3; i++) {
        await seed('$i', i);
      }
      final first = (await db.readRecord('paddocks', '1'))!.payload;
      final third = (await db.readRecord('paddocks', '3'))!.payload;
      await db.markDeleted('paddocks', '2', 'owner');
      await terminal('2');
      final active = await local.getAll();
      expect(active.map((p) => p.rotationOrder).toSet(), {1, 3});
      expect((await db.readRecord('paddocks', '1'))!.payload, first);
      expect((await db.readRecord('paddocks', '3'))!.payload, third);
      final rotation = const CalculatePaddockRotation()(
        paddocks: active,
        animals: [],
        referenceDate: DateTime.utc(2026),
      );
      expect(rotation.active, isNull);
      expect(rotation.next?.paddock.id, isNot('2'));
    },
  );
  test('late active download cannot replace historical tombstone', () async {
    await seed('p', 1);
    await terminal('p');
    final before = (await db.readRecord(
      'paddocks',
      'p',
      includeDeleted: true,
    ))!.payload;
    await seed('p', 1);
    expect(
      (await db.readRecord('paddocks', 'p', includeDeleted: true))!.payload,
      before,
    );
    expect(await local.getAll(), isEmpty);
  });
}
