import 'dart:convert';
import 'package:uuid/uuid.dart';

class AppEvent {
  final String id;
  final String entityType;
  final String entityId;
  final String eventType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  AppEvent({
    String? id,
    required this.entityType,
    required this.entityId,
    required this.eventType,
    this.payload = const {},
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'event_type': eventType,
      'payload_json': jsonEncode(payload),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AppEvent.fromMap(Map<String, dynamic> map) {
    final payloadRaw = map['payload_json'] as String?;
    return AppEvent(
      id: map['id'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      eventType: map['event_type'] as String,
      payload: payloadRaw == null || payloadRaw.isEmpty
          ? const {}
          : Map<String, dynamic>.from(jsonDecode(payloadRaw) as Map),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
