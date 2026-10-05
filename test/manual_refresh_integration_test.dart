import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/core/database/database_provider.dart';
import 'package:mi_finca_app/core/database/sync_metadata.dart';
import 'package:mi_finca_app/core/network/network_status.dart';
import 'package:mi_finca_app/features/animals/data/datasources/animal_remote_datasource.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/domain/entities/movement.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_patch.dart';
import 'package:mi_finca_app/features/animals/domain/value_objects/animal_move_command.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/expenses/data/datasources/expense_local_datasource.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_local_datasource.dart';
import 'package:mi_finca_app/features/paddocks/data/datasources/paddock_remote_datasource.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/value_objects/paddock_patch.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/sync/data/datasources/sync_local_datasource.dart';
import 'package:mi_finca_app/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'expense_delete_repository_test.dart'
    show ExpenseTransport, RemoteExpenses, expense;

Animal animal({String name = 'old', String location = 'A'}) => Animal(
  id: 'a',
  code: 'a',
  name: name,
  type: 'Vaca',
  breed: '',
  sex: 'Hembra',
  paddockId: location,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
Paddock paddock(String id, {String? name}) => Paddock(
  id: id,
  name: name ?? id,
  areaHectares: 1,
  status: 'Disponible',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
Movement movement() => Movement(
  id: 'm',
  animalId: 'a',
  fromPaddockId: 'A',
  toPaddockId: 'B',
  date: DateTime.utc(2026),
);

class AnimalsRemote extends AnimalRemoteDataSource {
  AnimalsRemote(super.client);
  String? owner = 'owner';
  List<Animal> animals = [];
  List<Movement> movements = [];
  Future<void> Function()? duringGet;
  @override
  String? get currentUserId => owner;
  @override
  Future<List<Animal>> getAnimals() async {
    await duringGet?.call();
    return animals;
  }

  @override
  Future<List<Movement>> getMovements() async => movements;
}

class PaddocksRemote extends PaddockRemoteDataSource {
  PaddocksRemote(super.client);
  List<Paddock> items = [];
  @override
  String? get currentUserId => 'owner';
  @override
  Future<List<Paddock>> getAll() async => items;
}

class RefreshTransport extends ExpenseTransport {
  bool failPush = false;
  @override
  Future<void> pushRecord(PendingRecord record) async {
    if (failPush) throw StateError('transient upload failure');
    await super.pushRecord(record);
  }
}

class TombstoneFailureTransport extends ExpenseTransport {
  Future<void> Function()? duringFetch;
  bool unavailable = false;
  @override
  Future<List<RemoteTombstone>> fetchTombstones(String ownerId) async {
    if (unavailable) {
      throw const PostgrestException(message: 'missing', code: '42P01');
    }
    final rows = await super.fetchTombstones(ownerId);
    await duringFetch?.call();
    return rows;
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late AnimalsRemote remote;
  late PaddocksRemote paddockRemote;
  late RemoteExpenses expenseRemote;
  late ExpenseTransport transport;
  late SupabaseClient client;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.writeSetting('session', jsonEncode({'id': 'owner'}));
    client = SupabaseClient('https://example.test', 'test');
    remote = AnimalsRemote(client);
    paddockRemote = PaddocksRemote(client);
    expenseRemote = RemoteExpenses();
    transport = RefreshTransport()..offline = false;
    await db.putRecord(
      'animals',
      'a',
      {
        'id': 'a',
        'code': 'a',
        'name': 'old',
        'type': 'Vaca',
        'breed': '',
        'sex': 'Hembra',
        'paddockId': 'A',
        'createdAt': DateTime.utc(2026).toIso8601String(),
        'updatedAt': DateTime.utc(2026).toIso8601String(),
      },
      DateTime.utc(2026),
      pending: false,
      verifiedRemoteOwner: 'owner',
    );
    for (final id in ['A', 'B']) {
      await PaddockLocalDataSource(
        db,
      ).save(paddock(id), pending: false, verifiedRemoteOwner: 'owner');
    }
    await ExpenseLocalDataSource(
      db,
    ).save(expense('e'), pending: false, verifiedRemoteOwner: 'owner');
    remote.animals = [animal(name: 'remote', location: 'B')];
    remote.movements = [movement()];
    paddockRemote.items = [paddock('A', name: 'remote paddock'), paddock('B')];
    expenseRemote.items = [expense('e', amount: 50), expense('new')];
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncRepositoryProvider.overrideWithValue(
          SyncRepositoryImpl(SyncLocalDataSource(db), transport),
        ),
        animalRemoteDataSourceProvider.overrideWithValue(remote),
        paddockRemoteDataSourceProvider.overrideWithValue(paddockRemote),
        expenseRemoteDataSourceProvider.overrideWithValue(expenseRemote),
        networkStatusProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    container.listen(networkStatusProvider, (_, _) {});
    await container.read(networkStatusProvider.future);
    await container.read(syncViewModelProvider.future);
    await container.read(animalViewModelProvider.future);
    await container.read(paddockViewModelProvider.future);
    await container.read(expenseViewModelProvider.future);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await client.dispose();
  });
  Future<void> refresh() =>
      container.read(syncViewModelProvider.notifier).refreshData();
  void tombstone(String collection, String id) {
    transport.ledger['$collection/$id'] = RemoteTombstone(
      collection: collection,
      id: id,
      ownerId: 'owner',
      operationId: 'delete-$id',
      deletedAt: DateTime.utc(2026),
    );
  }

  test(
    'manual refresh updates all populated providers, MOVE and timestamp',
    () async {
      await refresh();
      final state = container.read(animalViewModelProvider).requireValue;
      expect(state.animals.single.name, 'remote');
      expect(state.animals.single.paddockId, 'B');
      expect(state.movements.single.id, 'm');
      expect(
        container
            .read(paddockViewModelProvider)
            .requireValue
            .firstWhere((p) => p.id == 'A')
            .name,
        'remote paddock',
      );
      expect(
        container
            .read(expenseViewModelProvider)
            .requireValue
            .firstWhere((e) => e.id == 'e')
            .amount,
        50,
      );
      expect(container.read(expenseViewModelProvider).requireValue.length, 2);
      expect(await db.readSetting('last_data_refresh'), isNotNull);
      expect(
        container
            .read(syncViewModelProvider)
            .requireValue
            .refreshResult!
            .complete,
        isTrue,
      );
      await refresh();
      expect(
        container.read(animalViewModelProvider).requireValue.movements.length,
        1,
      );
    },
  );
  test(
    'remote DELETE of every entity is terminal, retains D3 and movements',
    () async {
      await refresh();
      tombstone('paddocks', 'A');
      tombstone('animals', 'a');
      tombstone('expenses', 'e');
      await refresh();
      expect(
        container.read(animalViewModelProvider).requireValue.animals,
        isEmpty,
      );
      expect(
        container.read(animalViewModelProvider).requireValue.movements.length,
        1,
      );
      expect(
        container
            .read(paddockViewModelProvider)
            .requireValue
            .any((p) => p.id == 'A'),
        isFalse,
      );
      final history = (await PaddockLocalDataSource(
        db,
      ).resolveHistory({'A'}))['A']!;
      expect(history.isDeleted, isTrue);
      expect(history.name, 'remote paddock');
      expect(
        container
            .read(expenseViewModelProvider)
            .requireValue
            .any((e) => e.id == 'e'),
        isFalse,
      );
    },
  );
  test(
    'pending animal and paddock patches retain commands and overlays',
    () async {
      await db.applyAnimalPatch(
        'a',
        'owner',
        AnimalPatch({AnimalField.name: 'local animal'}),
      );
      await db.applyPaddockPatch(
        'A',
        'owner',
        PaddockPatch({PaddockField.name: 'local paddock'}),
      );
      final animalCommand = (await db.animalPatches('owner')).single;
      final paddockCommand = (await db.paddockPatches('owner')).single;
      await refresh();
      expect(
        container
            .read(animalViewModelProvider)
            .requireValue
            .animals
            .single
            .name,
        'local animal',
      );
      expect(
        container
            .read(paddockViewModelProvider)
            .requireValue
            .firstWhere((p) => p.id == 'A')
            .name,
        'local paddock',
      );
      expect(
        (await db.animalPatches('owner')).single.payload,
        animalCommand.payload,
      );
      expect(
        (await db.paddockPatches('owner')).single.payload,
        paddockCommand.payload,
      );
      expect(await db.pendingCount(), 2);
    },
  );
  test(
    'pending MOVE keeps projection, provisional history and command without ACK',
    () async {
      await db.createAnimalMove(
        command: AnimalMoveCommand(
          movementId: 'local-m',
          ownerId: 'owner',
          animalId: 'a',
          fromPaddockId: 'A',
          toPaddockId: 'B',
          movedAt: DateTime.utc(2026),
          plannedGrazingDays: 4,
        ),
        movementPayload: {
          'id': 'local-m',
          'animalId': 'a',
          'fromPaddockId': 'A',
          'toPaddockId': 'B',
          'date': DateTime.utc(2026).toIso8601String(),
        },
      );
      final command = (await db.animalMoveCommands('owner')).single;
      final history = await db.readRecord('movements', 'local-m');
      remote.animals = [animal(location: 'A')];
      await refresh();
      expect(
        (await db.animalMoveCommands('owner')).single.payload,
        command.payload,
      );
      expect(
        (await db.readRecord('movements', 'local-m'))!.payload,
        history!.payload,
      );
      expect(
        (await db.readRecord('animals', 'a'))!.payload['_moveProjection'],
        isNotNull,
      );
      expect(
        container
            .read(animalViewModelProvider)
            .requireValue
            .animals
            .single
            .paddockId,
        'B',
      );
    },
  );
  test(
    'pending expense remains durable through successful remote GET',
    () async {
      await ExpenseLocalDataSource(db).save(expense('e', amount: 70));
      (transport as RefreshTransport).failPush = true;
      await refresh();
      final items = await ExpenseLocalDataSource(db).getAll();
      expect(items.firstWhere((e) => e.id == 'e').amount, 70);
      expect(items.any((e) => e.id == 'new'), isTrue);
      expect(await db.pendingCount(), 1);
      expect(await db.readSetting('last_data_refresh'), isNotNull);
      expect(
        container
            .read(syncViewModelProvider)
            .requireValue
            .refreshResult!
            .complete,
        isTrue,
      );
    },
  );

  test(
    'partial active failure retains safe merges and previous successful timestamp',
    () async {
      await refresh();
      final stamp = await db.readSetting('last_data_refresh');
      expenseRemote.fail = true;
      remote.animals = [animal(name: 'later')];
      await refresh();
      expect(
        container
            .read(animalViewModelProvider)
            .requireValue
            .animals
            .single
            .name,
        'later',
      );
      expect(
        container
            .read(expenseViewModelProvider)
            .requireValue
            .firstWhere((e) => e.id == 'e')
            .amount,
        50,
      );
      expect(await db.readSetting('last_data_refresh'), stamp);
      expect(
        container
            .read(syncViewModelProvider)
            .requireValue
            .refreshResult!
            .complete,
        isFalse,
      );
    },
  );
  test(
    'network failure keeps cache and no successful refresh timestamp',
    () async {
      transport.offline = true;
      await refresh();
      expect(
        container
            .read(animalViewModelProvider)
            .requireValue
            .animals
            .single
            .name,
        'old',
      );
      expect(await db.readSetting('last_data_refresh'), isNull);
    },
  );
  test(
    'session changes during GET discard response before any active merge',
    () async {
      remote.duringGet = () async {
        remote.owner = 'other';
        await db.writeSetting('session', jsonEncode({'id': 'other'}));
      };
      await refresh();
      expect((await db.readRecord('animals', 'a'))!.payload['name'], 'old');
      expect(await db.readSetting('last_data_refresh'), isNull);
    },
  );
  test('absence in all active GETs never deletes cached entities', () async {
    remote.animals = [];
    remote.movements = [];
    paddockRemote.items = [];
    expenseRemote.items = [];
    await refresh();
    expect(
      container.read(animalViewModelProvider).requireValue.animals.length,
      1,
    );
    expect(container.read(paddockViewModelProvider).requireValue.length, 2);
    expect(container.read(expenseViewModelProvider).requireValue.length, 1);
  });
  test('missing tombstone infrastructure is a real failure', () async {
    final failed = TombstoneFailureTransport()..unavailable = true;
    final sync = SyncRepositoryImpl(SyncLocalDataSource(db), failed);
    await expectLater(sync.pullRemoteTombstones(), throwsStateError);
  });
  test(
    'same owner relogin during tombstone GET discards old session response',
    () async {
      final changed = TombstoneFailureTransport()..offline = false;
      changed.ledger['a'] = RemoteTombstone(
        collection: 'animals',
        id: 'a',
        ownerId: 'owner',
        operationId: 'delete-a',
        deletedAt: DateTime.utc(2026),
      );
      changed.duringFetch = () async {
        await db.clearAll();
        await db.writeSetting('session', jsonEncode({'id': 'owner'}));
      };
      final sync = SyncRepositoryImpl(SyncLocalDataSource(db), changed);
      await expectLater(sync.pullRemoteTombstones(), throwsStateError);
      expect(await db.readRecord('animals', 'a', includeDeleted: true), isNull);
    },
  );
  test(
    'manual refresh waits for active PUSH and keeps its lock through GET',
    () async {
      final pushEntered = Completer<void>();
      final pushGate = Completer<void>();
      final getEntered = Completer<void>();
      final getGate = Completer<void>();
      transport.beforeDelete = () async {
        pushEntered.complete();
        await pushGate.future;
      };
      remote.duringGet = () async {
        getEntered.complete();
        await getGate.future;
      };
      await ExpenseLocalDataSource(db).markDeleted('e', 'owner');
      final vm = container.read(syncViewModelProvider.notifier);
      final automatic = vm.syncPendingIfOnline();
      await pushEntered.future;
      final manual = vm.refreshData();
      expect(
        container.read(syncViewModelProvider).requireValue.isRefreshing,
        isTrue,
      );
      pushGate.complete();
      await automatic;
      await getEntered.future;
      expect(
        container.read(syncViewModelProvider).requireValue.isRefreshing,
        isTrue,
      );
      expect(identical(manual, vm.refreshData()), isTrue);
      await vm.syncPendingIfOnline();
      expect(transport.deletes.length, 1);
      getGate.complete();
      await manual;
      expect(
        container.read(syncViewModelProvider).requireValue.isRefreshing,
        isFalse,
      );
      expect(
        container
            .read(syncViewModelProvider)
            .requireValue
            .refreshResult!
            .complete,
        isTrue,
      );
    },
  );
}
