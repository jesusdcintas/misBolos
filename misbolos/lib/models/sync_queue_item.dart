import 'dart:convert';
import 'package:uuid/uuid.dart';

enum SyncEntityType { gig, invoice }

enum SyncOperation { create, update, delete, statusChange }

extension SyncEntityTypeExtension on SyncEntityType {
  String get dbValue => name;

  static SyncEntityType fromDb(String value) => SyncEntityType.values
      .firstWhere((e) => e.dbValue == value, orElse: () => SyncEntityType.gig);
}

extension SyncOperationExtension on SyncOperation {
  String get dbValue => switch (this) {
    SyncOperation.statusChange => 'status_change',
    _ => name,
  };

  static SyncOperation fromDb(String value) => switch (value) {
    'create' => SyncOperation.create,
    'update' => SyncOperation.update,
    'delete' => SyncOperation.delete,
    'status_change' => SyncOperation.statusChange,
    _ => SyncOperation.update,
  };
}

class SyncQueueItem {
  final String id;
  final SyncEntityType entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  SyncQueueItem({
    String? id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    this.attempts = 0,
    this.lastError,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'entity_type': entityType.dbValue,
    'entity_id': entityId,
    'operation': operation.dbValue,
    'payload_json': jsonEncode(payload),
    'attempts': attempts,
    'last_error': lastError,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) => SyncQueueItem(
    id: map['id'] as String,
    entityType: SyncEntityTypeExtension.fromDb(map['entity_type'] as String),
    entityId: map['entity_id'] as String,
    operation: SyncOperationExtension.fromDb(map['operation'] as String),
    payload: jsonDecode(map['payload_json'] as String) as Map<String, dynamic>,
    attempts: map['attempts'] as int,
    lastError: map['last_error'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );
}
