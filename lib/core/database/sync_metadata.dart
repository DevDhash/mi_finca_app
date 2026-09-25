import 'package:uuid/uuid.dart';

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
