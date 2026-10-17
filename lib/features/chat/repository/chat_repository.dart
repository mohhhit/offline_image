import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';

/// Persistence repository for ChatThreads and ChatMessages.
class ChatRepository {
  final AppDatabase _dbHelper;
  final _uuid = const Uuid();

  ChatRepository([AppDatabase? dbHelper])
      : _dbHelper = dbHelper ?? AppDatabase.instance;

  Future<Database> get _db => _dbHelper.database;

  /// Retrieves all chat sessions ordered by most recently updated.
  Future<List<ChatThread>> getAllChats() async {
    final db = await _db;
    final results = await db.query(
      'chats',
      orderBy: 'updated_at DESC',
    );
    return results.map(ChatThread.fromMap).toList();
  }

  /// Creates a new chat thread.
  Future<ChatThread> createChat({String? title}) async {
    final db = await _db;
    final now = DateTime.now();
    final thread = ChatThread(
      id: _uuid.v4(),
      title: title ?? 'New Image Session',
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('chats', thread.toMap());
    return thread;
  }

  /// Updates thread title and bump updatedAt timestamp.
  Future<void> updateChatTitle(String chatId, String title) async {
    final db = await _db;
    await db.update(
      'chats',
      {
        'title': title,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  /// Deletes a thread, cascades delete to messages, and unlinks disk images.
  Future<void> deleteChat(String chatId) async {
    final db = await _db;
    // Retrieve image paths before deletion to clean up physical storage
    final messages = await getMessagesForChat(chatId);
    for (final m in messages) {
      if (m.imagePath != null && m.imagePath!.isNotEmpty) {
        final f = File(m.imagePath!);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }

    await db.delete('chats', where: 'id = ?', whereArgs: [chatId]);
  }

  /// Fetches all messages in a specific chat ordered chronologically.
  Future<List<ChatMessage>> getMessagesForChat(String chatId) async {
    final db = await _db;
    final results = await db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );
    return results.map(ChatMessage.fromMap).toList();
  }

  /// Inserts a new chat message into SQLite.
  Future<void> insertMessage(ChatMessage message) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('messages', message.toMap());
      await txn.update(
        'chats',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [message.chatId],
      );
    });
  }

  /// Updates generation progress step in SQLite.
  Future<void> updateMessageProgress(
    String messageId,
    int step,
    int totalSteps,
  ) async {
    final db = await _db;
    await db.update(
      'messages',
      {
        'step_progress': step,
        'total_steps': totalSteps,
        'status': MessageStatus.generating.name,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Marks a message completed and records the saved PNG path.
  Future<void> markMessageCompleted(
    String messageId,
    String imagePath,
    double durationSeconds,
  ) async {
    final db = await _db;
    await db.update(
      'messages',
      {
        'status': MessageStatus.completed.name,
        'image_path': imagePath,
        'duration_seconds': durationSeconds,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Marks a message failed with error details.
  Future<void> markMessageFailed(String messageId, String error) async {
    final db = await _db;
    await db.update(
      'messages',
      {
        'status': MessageStatus.failed.name,
        'error_message': error,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }
}

