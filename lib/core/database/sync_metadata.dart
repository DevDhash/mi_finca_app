import 'package:uuid/uuid.dart';

enum RemotePresence { localOnly, unknown, confirmed }

/// Internal protocol. Never serialized to a domain table by its upsert writer.
abstract final class SyncMetadata {
  static const key = '_sync';
  static const collections = {
    'farms',
    'paddocks',
    'animals',
    'movements',
    'expenses',
  };

  static Map<String, Object?> read(Map<String, Object?> payload) {
    final raw = payload[key];
    return raw is Map ? Map<String, Object?>.from(raw) : {};
  }

  static bool isDeleted(Map<String, Object?> payload) =>
      read(payload)['tombstone'] == true;
  static String? owner(Map<String, Object?> payload) =>
      read(payload)['ownerId'] as String?;

  static RemotePresence presence(Map<String, Object?> payload) =>
      switch (read(payload)['remotePresence']) {
        'local_only' => RemotePresence.localOnly,
        'confirmed' => RemotePresence.confirmed,
        _ => RemotePresence.unknown,
      };

  static String presenceValue(RemotePresence value) => switch (value) {
    RemotePresence.localOnly => 'local_only',
    RemotePresence.unknown => 'unknown',
    RemotePresence.confirmed => 'confirmed',
  };

  // Existence evidence is independent from the business operation being ACKed.
  // No other metadata (owner, revision, operationId, tombstone) is ignored.
  static bool sameOperation(Map<String, Object?> a, Map<String, Object?> b) {
    Map<String, Object?> withoutPresence(Map<String, Object?> value) {
      final meta = read(value)..remove('remotePresence');
      return {...value, if (meta.isNotEmpty) key: meta}
        ..removeWhere((k, v) => k == key && meta.isEmpty);
    }

    bool equalJson(Object? left, Object? right) {
      if (left is Map && right is Map) {
        return left.length == right.length &&
            left.keys.every(
              (key) =>
                  right.containsKey(key) && equalJson(left[key], right[key]),
            );
      }
      if (left is List && right is List) {
        if (left.length != right.length) return false;
        for (var i = 0; i < left.length; i++) {
          if (!equalJson(left[i], right[i])) return false;
        }
        return true;
      }
      return left == right;
    }

    return equalJson(withoutPresence(a), withoutPresence(b));
  }

  static Map<String, Object?> operation({
    required String? ownerId,
    required String operation,
    required int revision,
    required DateTime requestedAt,
  }) => {
    'ownerId': ownerId,
    'ownership': ownerId == null ? 'legacy_unverified' : 'verified',
    'operation': operation,
    'operationId': const Uuid().v4(),
    'revision': revision,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
    'tombstone': operation == 'delete',
  };
}

class RemoteTombstone {
  const RemoteTombstone({
    required this.collection,
    required this.id,
    required this.ownerId,
    required this.deletedAt,
    required this.operationId,
  });
  final String collection;
  final String id;
  final String ownerId;
  final DateTime deletedAt;
  final String operationId;

  factory RemoteTombstone.fromJson(Map<String, dynamic> json) =>
      RemoteTombstone(
        collection: json['collection'] as String,
        id: json['entity_id'] as String,
        ownerId: json['user_id'] as String,
        deletedAt: DateTime.parse(json['deleted_at'] as String),
        operationId: json['operation_id'] as String,
      );
}
