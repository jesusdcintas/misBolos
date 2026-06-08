import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/ai_assistant.dart';

class AiChatRepository {
  static final AiChatRepository instance = AiChatRepository._();
  AiChatRepository._();

  Future<AiChat> getOrCreateActiveChat() async {
    final active = await getActiveChat();
    if (active != null) return active;
    return createChat(title: 'Nuevo chat');
  }

  Future<AiChat?> getActiveChat() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'ai_chats',
      where: 'is_active = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return AiChat.fromMap(maps.first);
  }

  Future<List<AiChat>> getChats({int limit = 30}) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'ai_chats',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return maps.map(AiChat.fromMap).toList();
  }

  Future<AiChat> createChat({required String title}) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final chat = AiChat(
      title: title,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    await db.transaction((txn) async {
      await txn.update('ai_chats', {'is_active': 0});
      await txn.insert(
        'ai_chats',
        chat.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return chat;
  }

  Future<void> setActiveChat(String chatId) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.update('ai_chats', {'is_active': 0});
      await txn.update(
        'ai_chats',
        {'is_active': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [chatId],
      );
    });
  }

  Future<List<AiAssistantMessage>> getMessages(String chatId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'ai_chat_messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );
    return maps.map((map) {
      final metadata = _decodeMetadata(map['metadata_json']);
      final action = aiActionFromMetadata(metadata);
      final preview = aiPreviewFromMetadata(metadata);
      return AiAssistantMessage(
        id: map['id'] as String,
        role: AiAssistantMessageRole.fromDb(map['role'] as String),
        text: map['content'] as String,
        action: action,
        preview: preview,
        metadata: metadata,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
    }).toList();
  }

  Future<void> addMessage({
    required String chatId,
    required AiAssistantMessage message,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final metadata = message.metadata;
    await db.transaction((txn) async {
      await txn.insert('ai_chat_messages', {
        'id': message.id,
        'chat_id': chatId,
        'role': message.role.name,
        'content': message.text,
        'created_at': message.createdAt.toIso8601String(),
        'metadata_json': metadata == null || metadata.isEmpty
            ? null
            : jsonEncode(metadata),
      });
      await txn.update(
        'ai_chats',
        {
          'updated_at': message.createdAt.toIso8601String(),
          if (message.role == AiAssistantMessageRole.user)
            'title': _titleFromMessage(message.text),
        },
        where: 'id = ?',
        whereArgs: [chatId],
      );
    });
  }

  Future<void> updateMessageMetadata({
    required String messageId,
    required Map<String, dynamic> metadata,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'ai_chat_messages',
      {
        'metadata_json': metadata.isEmpty ? null : jsonEncode(metadata),
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Map<String, dynamic>? _decodeMetadata(Object? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value.toString());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  String _titleFromMessage(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'Nuevo chat';
    if (cleaned.length <= 42) return cleaned;
    return '${cleaned.substring(0, 42)}...';
  }
}
