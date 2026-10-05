import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/core/network/remote_pages.dart';
import 'package:mi_finca_app/features/sync/data/services/manual_data_refresh.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

Paddock paddock(String name) => Paddock(
  id: 'p',
  name: name,
  areaHectares: 1,
  status: 'Disponible',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
Movement movement() => Movement(
  id: 'm',
  animalId: 'a',
  toPaddockId: 'p',
  date: DateTime.utc(2026),
);
void main() {
  test('full refresh ordering and success timestamp', () async {
    final calls = <String>[];
    final worker = ManualDataRefresh(
      validate: () async {},
      push: () async {
        calls.add('push');
      },
      tombstones: () async {
        calls.add('tombstones');
      },
      downloads: {
        'paddocks': () async {
          calls.add('paddocks');
        },
        'animals': () async {
          calls.add('animals');
        },
        'movements': () async {
          calls.add('movements');
        },
        'expenses': () async {
          calls.add('expenses');
        },
      },
      reload: () async {
        calls.add('reload');
      },
      saveSuccess: () async {
        calls.add('timestamp');
      },
    );
    expect((await worker.refresh()).complete, isTrue);
    expect(calls, [
      'push',
      'tombstones',
      'paddocks',
      'animals',
      'movements',
      'expenses',
      'tombstones',
      'reload',
      'timestamp',
    ]);
  });
  test(
    'double invocation shares complete execution through final pull',
    () async {
      final gate = Completer<void>();
      var pulls = 0;
      var saves = 0;
      final worker = ManualDataRefresh(
        validate: () async {},
        push: () async {},
        tombstones: () async {
          pulls++;
          if (pulls == 2) await gate.future;
        },
        downloads: {},
        reload: () async {},
        saveSuccess: () async {
          saves++;
        },
      );
      final first = worker.refresh();
      final second = worker.refresh();
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(pulls, 2);
      gate.complete();
      await first;
      expect(saves, 1);
    },
  );
  for (final failed in ['connection', 'tombstones', 'animals', 'reload']) {
    test(
      '$failed failure preserves partial result and never records success',
      () async {
        var saved = false;
        Future<void> fail() async => throw StateError('network');
        final worker = ManualDataRefresh(
          validate: failed == 'connection' ? fail : () async {},
          push: () async {},
          tombstones: failed == 'tombstones' ? fail : () async {},
          downloads: {'animals': failed == 'animals' ? fail : () async {}},
          reload: failed == 'reload' ? fail : () async {},
          saveSuccess: () async {
            saved = true;
          },
        );
        expect((await worker.refresh()).complete, isFalse);
        expect(saved, isFalse);
      },
    );
  }
  test('session change stops subsequent downloads and timestamp', () async {
    var changed = false;
    var later = false;
    var saved = false;
    final worker = ManualDataRefresh(
      validate: () async {
        if (changed) throw StateError('owner');
      },
      push: () async {},
      tombstones: () async {},
      downloads: {
        'animals': () async {
          changed = true;
        },
        'expenses': () async {
          later = true;
        },
      },
      reload: () async {},
      saveSuccess: () async {
        saved = true;
      },
    );
    expect((await worker.refresh()).complete, isFalse);
    expect(later, isFalse);
    expect(saved, isFalse);
  });
  test(
    'keyset pagination handles server cap below requested page size',
    () async {
      final seen = <String?>[];
      final rows = await readRemotePages((after) async {
        seen.add(after);
        return after == null
            ? [
                {'id': 'a'},
              ]
            : after == 'a'
            ? [
                {'id': 'b'},
              ]
            : [];
      });
      expect(rows.map((r) => r['id']), ['a', 'b']);
      expect(seen, [null, 'a', 'b']);
    },
  );
  group('safe local merges', () {
    late AppDatabase db;
    late AnimalLocalDataSource animals;
    late PaddockLocalDataSource paddocks;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.writeSetting('session', jsonEncode({'id': 'owner'}));
      animals = AnimalLocalDataSource(db);
      paddocks = PaddockLocalDataSource(db);
    });
    tearDown(() async {
      await db.close();
    });
    test('populated paddock refresh updates active cache', () async {
      await paddocks.save(
        paddock('old'),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      final before = await paddocks.snapshot('owner');
      await paddocks.mergeRemote([paddock('new')], 'owner', before);
      expect((await paddocks.getAll()).single.name, 'new');
    });
    test('pending paddock remains pending and absence never deletes', () async {
      await paddocks.save(paddock('local'));
      final before = await paddocks.snapshot('owner');
      await paddocks.mergeRemote([paddock('remote')], 'owner', before);
      await paddocks.mergeRemote([], 'owner', before);
      expect((await paddocks.getAll()).single.name, 'local');
      expect(await db.pendingCount(), 1);
    });
    test('paddock edit during GET is protected', () async {
      await paddocks.save(
        paddock('old'),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      final before = await paddocks.snapshot('owner');
      await paddocks.save(paddock('local'));
      await paddocks.mergeRemote([paddock('remote')], 'owner', before);
      expect((await paddocks.getAll()).single.name, 'local');
    });
    test(
      'paddock tombstone survives stale active GET and keeps D3 name',
      () async {
        await paddocks.save(
          paddock('history'),
          pending: false,
          verifiedRemoteOwner: 'owner',
        );
        final before = await paddocks.snapshot('owner');
        await db.mergeRemoteTombstones('owner', [
          RemoteTombstone(
            collection: 'paddocks',
            id: 'p',
            ownerId: 'owner',
            operationId: 'delete',
            deletedAt: DateTime.utc(2026),
          ),
        ]);
        await paddocks.mergeRemote([paddock('stale')], 'owner', before);
        expect(await paddocks.getAll(), isEmpty);
        expect((await paddocks.resolveHistory({'p'}))['p']!.name, 'history');
      },
    );
    test(
      'remote movement repeated exactly once, absence preserves history',
      () async {
        for (var i = 0; i < 2; i++) {
          await animals.mergeRemoteMovements(
            [movement()],
            'owner',
            await animals.movementSnapshot('owner'),
          );
        }
        await animals.mergeRemoteMovements(
          [],
          'owner',
          await animals.movementSnapshot('owner'),
        );
        expect((await animals.getMovements()).length, 1);
      },
    );
    test('movement receipt is preserved', () async {
      await animals.mergeRemoteMovements(
        [movement()],
        'owner',
        await animals.movementSnapshot('owner'),
      );
      final row = await db.readRecord('movements', 'm');
      await db.putRecord(
        'movements',
        'm',
        {
          ...row!.payload,
          '_moveReceipt': {'id': 'm'},
        },
        row.updatedAt,
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      final before = await animals.movementSnapshot('owner');
      await animals.mergeRemoteMovements([movement()], 'owner', before);
      expect((await db.readRecord('movements', 'm'))!.payload['_moveReceipt'], {
        'id': 'm',
      });
    });
    test('owner changed rejects merge without mixing data', () async {
      final before = await paddocks.snapshot('owner');
      await db.writeSetting('session', jsonEncode({'id': 'other'}));
      await expectLater(
        paddocks.mergeRemote([paddock('remote')], 'owner', before),
        throwsStateError,
      );
      expect(await paddocks.getAll(), isEmpty);
    });
  });
}
