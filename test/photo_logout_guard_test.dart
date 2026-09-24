import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/core/database/app_database.dart';
import 'package:mi_finca_app/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:mi_finca_app/features/auth/data/datasources/supabase_auth_datasource.dart';
import 'package:mi_finca_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mi_finca_app/features/auth/domain/entities/user_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRemote extends SupabaseAuthDatasource {
  AuthRemote() : super(SupabaseClient('https://test.supabase.co', 'key'));
  int calls = 0;
  Future<void> Function()? action;
  @override
  Future<void> signOut() async {
    calls++;
    await action?.call();
  }
}

void main() {
  late AppDatabase db;
  late AuthRemote remote;
  late AuthRepositoryImpl auth;
  var cleaned = 0;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    remote = AuthRemote();
    cleaned = 0;
    auth = AuthRepositoryImpl(
      local: AuthLocalDataSource(db),
      remote: remote,
      clearLocalPhotos: (owner) async {
        expect(owner, 'u');
        cleaned++;
      },
    );
    await auth.saveSession(
      const UserSession(id: 'u', name: 'Ana', email: 'a@b.co'),
    );
  });
  tearDown(() => db.close());
  test(
    'legacy local photo prevents logout even when row is marked synced',
    () async {
      await db.putRecord(
        'animals',
        'a',
        {'photoPath': '/local/photo.jpg'},
        DateTime.now(),
        pending: false,
      );
      await expectLater(auth.signOut(), throwsA(isA<PendingSessionChanges>()));
      expect(remote.calls, 0);
      expect(cleaned, 0);
      expect(await db.readSetting('session'), isNotNull);
      expect(db.isClosingSession, false);
    },
  );
  test('checkpoint not yet published prevents logout', () async {
    await db.putRecord(
      'animals',
      'a',
      {
        '_photoUpload': {'status': 'uploaded'},
      },
      DateTime.now(),
      pending: false,
    );
    await expectLater(auth.signOut(), throwsA(isA<PendingSessionChanges>()));
    expect(remote.calls, 0);
    expect(cleaned, 0);
  });
  test('remote logout failure preserves local session and photos', () async {
    remote.action = () async => throw StateError('offline');
    await expectLater(auth.signOut(), throwsStateError);
    expect(await db.readSetting('session'), isNotNull);
    expect(cleaned, 0);
    expect(db.isClosingSession, false);
  });
  test(
    'logout blocks concurrent saves and clears only after remote success',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      remote.action = () {
        started.complete();
        return gate.future;
      };
      final logout = auth.signOut();
      await started.future;
      await expectLater(
        db.putRecord('animals', 'a', {}, DateTime.now()),
        throwsStateError,
      );
      await expectLater(db.writeSetting('session', 'stale'), throwsStateError);
      expect(cleaned, 0);
      gate.complete();
      await logout;
      expect(cleaned, 1);
      expect(await db.readSetting('session'), isNull);
      expect(db.isClosingSession, false);
    },
  );
}
