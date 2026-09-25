import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_local_datasource.dart';
import 'package:mi_finca_app/features/animals/data/models/animal_model.dart';
import 'package:mi_finca_app/features/animals/data/repositories/animal_repository_impl.dart';
import 'package:mi_finca_app/features/animals/data/services/animal_photo_sync.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/domain/repositories/animal_repository.dart';
import 'package:mi_finca_app/features/animals/domain/usecases/move_animal.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_remote_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/repositories/paddock_repository_impl.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';

import 'remote_presence_sync_test.dart'
    show PresenceRemote, PresenceStorage, PresenceAnimals;

class DeleteReader extends PresenceAnimals {
  DeleteReader(super.client);
  bool exists = false;
  List<Movement> movements = [];
  int reads = 0;
  @override
  Future<List<Animal>> getAnimals() async {
    reads++;
    return super.getAnimals();
  }

  int probes = 0;
  Future<void> Function()? onProbe;
  @override
  Future<bool> verifyAnimalOwner(String id, String owner) async {
    probes++;
    await onProbe?.call();
    return exists;
  }

  @override
  Future<List<Movement>> getMovements() async => movements;
}

class DeleteTransport extends PresenceRemote {
  bool failDelete = false;
  final deletedOperations = <String>[];
  @override
  Future<RemoteTombstone> softDelete(PendingRecord record) async {
    deletedOperations.add(record.operationId!);
    if (failDelete) throw const SocketException('offline');
    return super.softDelete(record);
  }
}

class DelayedAnimalRepository extends AnimalRepositoryImpl {
  DelayedAnimalRepository({
    required super.local,
    required super.remote,
    super.pullTombstones,
  });
  Future<void> Function()? afterSave;
  @override
  Future<void> save(Animal animal) async {
    await super.save(animal);
    await afterSave?.call();
  }
}

final deletionDate = DateTime.utc(2026, 9, 25);
Animal deletionAnimal({String id = 'a', String? photo}) => Animal(
  id: id,
  code: id,
  name: 'Fifi',
  type: 'Vaca',
  breed: 'Holstein',
  sex: 'Hembra',
  paddockId: 'p1',
  localPhotoPath: photo,
  createdAt: deletionDate,
  updatedAt: deletionDate,
);
Movement deletionMovement(String id) => Movement(
  id: id,
  animalId: 'a',
  fromPaddockId: 'p1',
  toPaddockId: 'p2',
  date: deletionDate,
);

void main() {
  late Directory directory;
  late AppDatabase db;
  late AnimalLocalDataSource local;
  late DelayedAnimalRepository repository;
  late DeleteReader reader;
  late DeleteTransport remote;
  late PresenceStorage storage;
  late SyncRepositoryImpl sync;
  late SupabaseClient client;
  ProviderContainer? container;

  void connect() {
    db = AppDatabase(NativeDatabase(File('${directory.path}/store.sqlite')));
    local = AnimalLocalDataSource(db);
    sync = SyncRepositoryImpl(
      SyncLocalDataSource(db),
      remote,
      photos: AnimalPhotoSync(db, storage),
    );
    repository = DelayedAnimalRepository(
      local: local,
      remote: reader,
      pullTombstones: sync.pullRemoteTombstones,
    );
  }

  Future<PendingRecord> row([
    String collection = 'animals',
    String id = 'a',
  ]) async => (await db.readRecord(collection, id, includeDeleted: true))!;
  Future<void> confirmed() async {
    await local.save(deletionAnimal());
    await db.markRemoteConfirmed('animals', 'a', 'owner');
    remote.physical.add('animals/a');
  }

  Future<void> unknown({String? photo}) async {
    await local.save(deletionAnimal(photo: photo));
    await db.beginRemotePublish(await row());
  }

  Future<AnimalViewModel> viewModel() async {
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        animalRepositoryProvider.overrideWithValue(repository),
        syncRepositoryProvider.overrideWithValue(sync),
        paddockRepositoryProvider.overrideWithValue(
          PaddockRepositoryImpl(
            local: PaddockLocalDataSource(db),
            remote: PaddockRemoteDataSource(client),
          ),
        ),
      ],
    );
    await container!.read(animalViewModelProvider.future);
    await container!.read(syncViewModelProvider.future);
    container!.read(syncViewModelProvider.notifier).setOnline(false);
    return container!.read(animalViewModelProvider.notifier);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('animal-delete-');
    client = SupabaseClient('https://example.supabase.co', 'test');
    reader = DeleteReader(client);
    remote = DeleteTransport();
    storage = PresenceStorage();
    connect();
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
  });
  tearDown(() async {
    container?.dispose();
    container = null;
    await db.close();
    await client.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'confirmed offline intent survives restart; reconnect and retry preserve identity',
    () async {
      await confirmed();
      reader.owner = null;
      expect(await repository.deleteAnimal('a'), AnimalDeletionResult.accepted);
      final before = await row();
      expect(before.remotePresence, RemotePresence.confirmed);
      expect(before.payload['name'], 'Fifi');
      expect(await repository.getAll(), isEmpty);
      expect(
        await repository.deleteAnimal('a'),
        AnimalDeletionResult.alreadyDeleted,
      );
      expect((await row()).operationId, before.operationId);
      await db.close();
      connect();
      expect(await repository.getAll(), isEmpty);
      expect(await db.pendingCount(), 1);
      remote.failDelete = true;
      await sync.pushPendingChanges();
      expect(await db.pendingCount(), 1);
      remote.failDelete = false;
      await sync.pushPendingChanges();
      expect(remote.deletedOperations, [
        before.operationId,
        before.operationId,
      ]);
      expect(await db.pendingCount(), 0);
      expect(
        SyncMetadata.read((await row()).payload)['remoteOperationId'],
        before.operationId,
      );
    },
  );

  test(
    'confirmed online deletion preserves historical and pending movements',
    () async {
      await confirmed();
      await local.saveMovement(
        deletionMovement('history'),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      await local.saveMovement(deletionMovement('pending'));
      for (final id in ['p1', 'p2']) {
        await db.putRecord(
          'paddocks',
          id,
          {'id': id, 'status': 'En uso'},
          deletionDate,
          pending: false,
          verifiedRemoteOwner: 'owner',
        );
        remote.physical.add('paddocks/$id');
      }
      await repository.deleteAnimal('a');
      expect(await local.getMovements(), hasLength(2));
      await sync.pushPendingChanges();
      expect(remote.sent, ['movements/pending']);
      expect(remote.ledger.single.collection, 'animals');
      expect(await local.getMovements(), hasLength(2));
      expect((await row('paddocks', 'p1')).payload['status'], 'En uso');
    },
  );

  test(
    'local cancellation atomically hides all movements and preserves paddocks and photo metadata',
    () async {
      await local.save(deletionAnimal(photo: '/private/not-uploaded.jpg'));
      await local.saveMovement(deletionMovement('m1'));
      await local.saveMovement(deletionMovement('m2'));
      await db.putRecord('paddocks', 'p1', {
        'id': 'p1',
        'status': 'En uso',
        'grazingStartDate': '2026-09-01',
      }, deletionDate);
      final paddock = (await row('paddocks', 'p1')).payload;
      final before = await row();
      expect(await repository.deleteAnimal('a'), AnimalDeletionResult.accepted);
      for (final r in [
        await row(),
        await row('movements', 'm1'),
        await row('movements', 'm2'),
      ]) {
        final meta = SyncMetadata.read(r.payload);
        expect(r.isDeleted, true);
        expect(r.remotePresence, RemotePresence.localOnly);
        expect(meta['localCancellation'], true);
        expect(meta['deletedAt'], isNull);
        expect(meta['remoteOperationId'], isNull);
      }
      expect(
        (await row()).payload['_photoUpload'],
        before.payload['_photoUpload'],
      );
      expect(await local.getMovements(), isEmpty);
      expect((await row('paddocks', 'p1')).payload, paddock);
      expect((await db.readPendingRecords()).map((r) => r.collection), [
        'paddocks',
      ]);
      await sync.pushPendingChanges();
      expect(remote.sent, ['paddocks/p1']);
      expect(remote.ledger, isEmpty);
      expect(storage.calls, 0);
      await db.close();
      connect();
      expect(await repository.getAll(), isEmpty);
      expect(await local.getMovements(), isEmpty);
      expect(
        await db.readRecord('animals', 'a', includeDeleted: true),
        isNotNull,
      );
    },
  );

  for (final presence in [RemotePresence.unknown, RemotePresence.confirmed]) {
    test(
      'local animal with $presence movement refuses entire cancellation',
      () async {
        await local.save(deletionAnimal());
        await local.saveMovement(deletionMovement('first'));
        await local.saveMovement(deletionMovement('ambiguous'));
        final m = await row('movements', 'ambiguous');
        if (presence == RemotePresence.unknown) {
          await db.beginRemotePublish(m);
        } else {
          await db.markRemoteConfirmed('movements', 'ambiguous', 'owner');
        }
        final before = (await row()).payload;
        expect(
          await repository.deleteAnimal('a'),
          AnimalDeletionResult.needsVerification,
        );
        expect((await row()).payload, before);
        expect(await local.getMovements(), hasLength(2));
        expect((await row('movements', 'first')).isDeleted, false);
      },
    );
  }

  test(
    'cancellation wins and every old animal/movement/photo snapshot becomes unusable',
    () async {
      await local.save(deletionAnimal(photo: '/missing.jpg'));
      await local.saveMovement(deletionMovement('m'));
      final animal = await row();
      final movement = await row('movements', 'm');
      await repository.deleteAnimal('a');
      expect(await db.beginRemotePublish(animal), isNull);
      expect(await db.beginRemotePublish(movement), isNull);
      expect(
        await AnimalPhotoSync(db, storage).push(animal, remote.pushRecord),
        false,
      );
      expect(storage.calls, 0);
      expect(remote.sent, isEmpty);
    },
  );

  test(
    'publish claim wins: UNKNOWN cannot be cancelled even when remote is empty',
    () async {
      await local.save(deletionAnimal());
      final snapshot = await row();
      final results = await Future.wait<Object?>([
        db.beginRemotePublish(snapshot),
        db.deleteAnimalLocally('a', 'owner'),
      ]);
      expect(results.first, isA<PendingRecord>());
      expect(results.last, AnimalLocalDeletion.needsVerification);
      expect((await row()).remotePresence, RemotePresence.unknown);
      expect(
        await repository.deleteAnimal('a'),
        AnimalDeletionResult.needsVerification,
      );
      expect((await row()).isDeleted, false);
    },
  );

  test(
    'concurrent cancellation first prevents claim without publishing',
    () async {
      await local.save(deletionAnimal());
      final snapshot = await row();
      final results = await Future.wait<Object?>([
        db.deleteAnimalLocally('a', 'owner'),
        db.beginRemotePublish(snapshot),
      ]);
      expect(results.first, AnimalLocalDeletion.accepted);
      expect(results.last, isNull);
    },
  );

  test(
    'UNKNOWN positive physical row becomes confirmed then pending DELETE',
    () async {
      await unknown();
      reader.exists = true;
      expect(await repository.deleteAnimal('a'), AnimalDeletionResult.accepted);
      expect((await row()).remotePresence, RemotePresence.confirmed);
      expect((await row()).operation, 'delete');
      expect(await db.pendingCount(), 1);
    },
  );

  for (final kind in [
    'empty',
    'offline',
    'error',
    'account',
    'local-account',
  ]) {
    test(
      'UNKNOWN $kind cannot discard animal or pending photo metadata',
      () async {
        await unknown(photo: '/pending-photo.jpg');
        final before = (await row()).payload;
        if (kind == 'offline') reader.owner = null;
        if (kind == 'error') {
          reader.onProbe = () async => throw const SocketException('offline');
        }
        if (kind == 'account') {
          reader.onProbe = () async {
            reader.owner = 'B';
            reader.exists = true;
          };
        }
        if (kind == 'local-account') {
          reader.onProbe = () async {
            await db.writeSetting('session', jsonEncode({'id': 'B'}));
            reader.exists = true;
          };
        }
        final result = await repository.deleteAnimal('a');
        expect(
          result,
          kind.contains('account')
              ? AnimalDeletionResult.ownershipFailure
              : AnimalDeletionResult.needsVerification,
        );
        expect((await row()).payload, before);
        expect((await row()).remotePresence, RemotePresence.unknown);
      },
    );
  }

  test('other owner is never adopted or deleted', () async {
    await confirmed();
    await db.writeSetting('session', jsonEncode({'id': 'B'}));
    reader.owner = 'B';
    expect(
      await repository.deleteAnimal('a'),
      AnimalDeletionResult.ownershipFailure,
    );
    expect((await row()).isDeleted, false);
    expect(reader.probes, 0);
  });

  test(
    'legacy unowned row needs positive ownership evidence before deleting',
    () async {
      await db.putRecord(
        'animals',
        'a',
        AnimalModel.toJson(deletionAnimal()),
        deletionDate,
        pending: false,
      );
      expect((await row()).ownerId, isNull);
      expect(
        await repository.deleteAnimal('a'),
        AnimalDeletionResult.needsVerification,
      );
      reader.exists = true;
      expect(await repository.deleteAnimal('a'), AnimalDeletionResult.accepted);
      expect((await row()).ownerId, 'owner');
    },
  );

  test(
    'remote tombstone beats pending UPSERT, stale refresh and save',
    () async {
      await local.save(deletionAnimal());
      reader.items = [deletionAnimal().copyWith(name: 'Stale')];
      remote.ledger.add(
        RemoteTombstone(
          collection: 'animals',
          id: 'a',
          ownerId: 'owner',
          deletedAt: deletionDate,
          operationId: 'remote',
        ),
      );
      await repository.refreshAnimals();
      expect(await repository.getAll(), isEmpty);
      expect(await db.pendingCount(), 0);
      await expectLater(repository.save(deletionAnimal()), throwsStateError);
      expect((await row()).isDeleted, true);
    },
  );

  test(
    'refresh response started before local cancellation cannot restore animal',
    () async {
      await local.save(deletionAnimal());
      reader.items = [deletionAnimal()];
      reader.duringRead = () async {
        await repository.deleteAnimal('a');
      };
      expect(await repository.refreshAnimals(), isEmpty);
      expect((await row()).isDeleted, true);
    },
  );

  test(
    'inflight confirmed photo upload cannot publish after tombstone checkpoint',
    () async {
      final file = File('${directory.path}/photo.jpg');
      await file.writeAsBytes([0xff, 0xd8, 0xff, 0xdb, 1, 2, 3]);
      await local.save(deletionAnimal(photo: file.path));
      await db.markRemoteConfirmed('animals', 'a', 'owner');
      final before = await row();
      storage.onUpload = () async {
        await repository.deleteAnimal('a');
      };
      expect(
        await AnimalPhotoSync(db, storage).push(before, remote.pushRecord),
        false,
      );
      expect(remote.sent, isEmpty);
      expect((await row()).isDeleted, true);
      expect((await row()).payload['_photoUpload'], isNotNull);
      expect(await file.exists(), true);
    },
  );

  test(
    'inflight animal publish response cannot ACK or restore pending DELETE',
    () async {
      await confirmed();
      final before = await row();
      remote.duringPush = (_) async {
        await repository.deleteAnimal('a');
      };
      expect(
        await AnimalPhotoSync(db, storage).push(before, remote.pushRecord),
        false,
      );
      expect((await row()).operation, 'delete');
      expect(await db.pendingCount(), 1);
    },
  );

  test(
    'late movement after cancellation fails with no movement persisted',
    () async {
      await local.save(deletionAnimal());
      await repository.deleteAnimal('a');
      await expectLater(
        MoveAnimal(repository)(deletionAnimal(), 'p2', deletionDate),
        throwsStateError,
      );
      await expectLater(
        local.saveMovement(deletionMovement('late')),
        throwsStateError,
      );
      expect(await local.getMovements(), isEmpty);
    },
  );

  test(
    'view model partial refresh publishes local tombstones even if GET fails',
    () async {
      await confirmed();
      final vm = await viewModel();
      remote.ledger.add(
        RemoteTombstone(
          collection: 'animals',
          id: 'a',
          ownerId: 'owner',
          deletedAt: deletionDate,
          operationId: 'r',
        ),
      );
      reader.duringRead = () async => throw const SocketException('offline');
      await expectLater(
        vm.refreshFromRemote(),
        throwsA(isA<SocketException>()),
      );
      expect(
        container!.read(animalViewModelProvider).requireValue.animals,
        isEmpty,
      );
    },
  );

  test(
    'view model double delete shares intent, retains movements and stale save cannot restore state',
    () async {
      await confirmed();
      await local.saveMovement(
        deletionMovement('history'),
        pending: false,
        verifiedRemoteOwner: 'owner',
      );
      final vm = await viewModel();
      final first = vm.deleteAnimal('a');
      final second = vm.deleteAnimal('a');
      expect(identical(first, second), true);
      await first;
      final op = (await row()).operationId;
      expect(
        container!.read(animalViewModelProvider).requireValue.animals,
        isEmpty,
      );
      expect(
        container!.read(animalViewModelProvider).requireValue.movements,
        hasLength(1),
      );
      await expectLater(vm.save(deletionAnimal()), throwsStateError);
      expect(
        container!.read(animalViewModelProvider).requireValue.animals,
        isEmpty,
      );
      expect((await row()).operationId, op);
    },
  );

  test(
    'automatic sync conflict reloads Animals from SQLite without remote recursive refresh',
    () async {
      await confirmed();
      await viewModel();
      remote.fail.add('animals/a');
      remote.ledger.add(
        RemoteTombstone(
          collection: 'animals',
          id: 'a',
          ownerId: 'owner',
          deletedAt: deletionDate,
          operationId: 'r',
        ),
      );
      final vm = container!.read(syncViewModelProvider.notifier);
      vm.setOnline(true);
      await vm.syncPendingIfOnline();
      expect(
        container!.read(animalViewModelProvider).requireValue.animals,
        isEmpty,
      );
      expect(reader.probes, 0);
    },
  );
  test(
    'tombstone-only collection opens offline with zero remote reads',
    () async {
      await local.save(deletionAnimal());
      await repository.deleteAnimal('a');
      reader.duringRead = () async => throw const SocketException('offline');
      await db.close();
      connect();
      expect(await repository.getAll(), isEmpty);
      expect(reader.reads, 0);
    },
  );

  test(
    'historical remote movements still download when animals already exist',
    () async {
      await confirmed();
      reader.movements = [deletionMovement('history')];
      expect(await repository.getMovements(), hasLength(1));
      await repository.deleteAnimal('a');
      expect(await repository.getMovements(), hasLength(1));
    },
  );

  test(
    'batch revalidates SQLite selection; missing animals never move or change paddocks',
    () async {
      await local.save(deletionAnimal());
      await local.save(deletionAnimal(id: 'b'));
      for (final id in ['p1', 'p2']) {
        await PaddockLocalDataSource(db).save(
          Paddock(
            id: id,
            name: id,
            areaHectares: 1,
            status: id == 'p1' ? 'En uso' : 'Disponible',
            createdAt: deletionDate,
            updatedAt: deletionDate,
          ),
        );
      }
      final vm = await viewModel();
      await container!.read(paddockViewModelProvider.future);
      await repository.deleteAnimal(
        'a',
      ); // VM intentionally still has a stale selection.
      final before = (await row('paddocks', 'p1')).payload;
      expect(
        await vm.moveMany(
          [deletionAnimal()],
          'p2',
          deletionDate,
          plannedGrazingDays: 3,
        ),
        0,
      );
      expect((await row('paddocks', 'p1')).payload, before);
      expect(
        await vm.moveMany(
          [deletionAnimal(), deletionAnimal(id: 'b')],
          'p2',
          deletionDate,
          plannedGrazingDays: 3,
        ),
        1,
      );
      expect((await local.getMovements()).single.animalId, 'b');
      expect(
        container!.read(animalViewModelProvider).requireValue.animals.single.id,
        'b',
      );
    },
  );

  test(
    'create edit individual move and multi move persist atomically under C',
    () async {
      await local.save(deletionAnimal());
      await repository.save(deletionAnimal().copyWith(name: 'Editada'));
      await MoveAnimal(repository)(deletionAnimal(), 'p2', deletionDate);
      expect((await repository.getLocal()).single.name, 'Editada');
      expect((await local.getMovements()).single.fromPaddockId, 'p1');
      final current = (await repository.getLocal()).single;
      await db.markDeleted('animals', 'a', 'owner');
      await expectLater(
        repository.saveMove(
          current.copyWith(paddockId: 'p3'),
          Movement(
            id: 'bad',
            animalId: 'a',
            fromPaddockId: 'p2',
            toPaddockId: 'p3',
            date: deletionDate,
          ),
        ),
        throwsStateError,
      );
      expect(await local.getMovements(), hasLength(1));
    },
  );

  test(
    'inconsistent local movement owner refuses cancellation without partial writes',
    () async {
      await local.save(deletionAnimal());
      await local.saveMovement(deletionMovement('m'));
      final m = await row('movements', 'm');
      await db.replaceRecordIfUnchanged(m, {
        ...m.payload,
        '_sync': {...SyncMetadata.read(m.payload), 'ownerId': 'B'},
      }, pending: true);
      expect(
        await repository.deleteAnimal('a'),
        AnimalDeletionResult.needsVerification,
      );
      expect((await row()).isDeleted, false);
      expect((await row('movements', 'm')).isDeleted, false);
    },
  );

  test(
    'save accepted before delete but returning late never reinserts animal in state',
    () async {
      await confirmed();
      final vm = await viewModel();
      final saved = Completer<void>();
      final release = Completer<void>();
      repository.afterSave = () async {
        saved.complete();
        await release.future;
      };
      final saving = vm.save(deletionAnimal().copyWith(name: 'Editada'));
      await saved.future;
      expect(await vm.deleteAnimal('a'), AnimalDeletionResult.accepted);
      final tombstone = await row();
      release.complete();
      await saving;
      expect(
        container!.read(animalViewModelProvider).requireValue.animals,
        isEmpty,
      );
      expect((await row()).operationId, tombstone.operationId);
      expect((await row()).payload['name'], 'Editada');
    },
  );

  test(
    'confirmed photo references and upload metadata survive deletion and ACK',
    () async {
      await local.save(
        deletionAnimal(
          photo: '/private/keep.jpg',
        ).copyWith(remotePhotoPath: 'owner/a/old.jpg'),
      );
      await db.markRemoteConfirmed('animals', 'a', 'owner');
      final before = await row();
      await repository.deleteAnimal('a');
      await sync.pushPendingChanges();
      final after = await row();
      expect(after.payload['remotePhotoPath'], 'owner/a/old.jpg');
      expect(after.payload['localPhotoPath'], '/private/keep.jpg');
      expect(after.payload['_photoUpload'], before.payload['_photoUpload']);
      expect(storage.calls, 0);
      expect(remote.sent, isEmpty);
    },
  );
}
