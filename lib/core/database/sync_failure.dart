import 'package:supabase_flutter/supabase_flutter.dart';

enum SyncFailureKind {
  transient,
  businessConflict,
  terminalEvidenceRequired,
  authorizationFatal,
}

/// A terminal error is NOT an ACK. Only validated terminal evidence can
/// confirm a deletion.
abstract final class SyncFailure {
  static const _businessConflicts = <String>{
    'SYNC_PADDOCK_OCCUPIED',
    'SYNC_MOVE_SOURCE_CONFLICT',
    'SYNC_PADDOCK_NOT_AVAILABLE',
    'SYNC_GRAZING_DAYS_REQUIRED',
    'SYNC_MOVE_ID_CONFLICT',
    'SYNC_MOVE_LEGACY_CONFLICT',
  };

  static SyncFailureKind classify(Object error) {
    if (error is AuthException) {
      return SyncFailureKind.authorizationFatal;
    }

    if (error is! PostgrestException) {
      return SyncFailureKind.transient;
    }

    final message = error.message;

    if ((error.code == 'P0001' || error.code == '22023') &&
        _businessConflicts.contains(message)) {
      return SyncFailureKind.businessConflict;
    }

    if (error.code == 'P0001' && message == 'SYNC_ENTITY_DELETED') {
      return SyncFailureKind.terminalEvidenceRequired;
    }

    if (error.code == '42501' ||
        error.code == '28000' ||
        message.contains('SYNC_NOT_AUTHORIZED')) {
      return SyncFailureKind.authorizationFatal;
    }

    return SyncFailureKind.transient;
  }
}
