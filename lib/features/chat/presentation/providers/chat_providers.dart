import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:offline_image/features/chat/models/chat_message.dart';
import 'package:offline_image/features/chat/models/chat_thread.dart';
import 'package:offline_image/features/chat/repository/chat_repository.dart';
import 'package:offline_image/features/inference/isolate/sd_isolate_protocol.dart';
import 'package:offline_image/features/inference/presentation/providers/inference_provider.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository();
});

/// List of all chat threads.
final chatListProvider =
    StateNotifierProvider<ChatListNotifier, List<ChatThread>>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  return ChatListNotifier(repo);
});

class ChatListNotifier extends StateNotifier<List<ChatThread>> {
  final ChatRepository _repo;

  ChatListNotifier(this._repo) : super([]) {
    loadChats();
  }

  Future<void> loadChats() async {
    final chats = await _repo.getAllChats();
    state = chats;
  }

  Future<ChatThread> createNewChat([String? title]) async {
    final chat = await _repo.createChat(title: title);
    state = [chat, ...state];
    return chat;
  }

  Future<void> deleteChat(String chatId) async {
    await _repo.deleteChat(chatId);
    state = state.where((c) => c.id != chatId).toList();
  }

  Future<void> renameChat(String chatId, String newTitle) async {
    await _repo.updateChatTitle(chatId, newTitle);
    state = [
      for (final c in state)
        if (c.id == chatId) c.copyWith(title: newTitle) else c
    ];
  }
}

/// Currently active chat ID.
final activeChatIdProvider = StateProvider<String?>((ref) => null);

/// Messages for the active chat thread.
final activeChatMessagesProvider =
    StateNotifierProvider<ActiveChatMessagesNotifier, List<ChatMessage>>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  final chatId = ref.watch(activeChatIdProvider);
  final inferenceNotifier = ref.read(inferenceNotifierProvider.notifier);
  return ActiveChatMessagesNotifier(repo, chatId, inferenceNotifier, ref);
});

class ActiveChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final ChatRepository _repo;
  final String? _chatId;
  final InferenceNotifier _inferenceNotifier;
  final Ref _ref;
  final _uuid = const Uuid();

  ActiveChatMessagesNotifier(
    this._repo,
    this._chatId,
    this._inferenceNotifier,
    this._ref,
  ) : super([]) {
    if (_chatId != null) {
      loadMessages();
    }
  }

  Future<void> loadMessages() async {
    if (_chatId == null) return;
    final messages = await _repo.getMessagesForChat(_chatId);
    state = messages;
  }

  /// Submits a prompt, inserts placeholder, and streams generation.
  Future<void> submitPrompt({
    required String prompt,
    String? negativePrompt,
    double cfgScale = 7.0,
    int steps = 20,
    int seed = -1,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      debugPrint('[Chat] submitPrompt ignored: prompt is empty');
      return;
    }

    // Ensure active chat ID exists even if user typed before first chat was selected
    String targetChatId = _chatId ?? _ref.read(activeChatIdProvider) ?? '';
    if (targetChatId.isEmpty) {
      debugPrint('[Chat] No active chat found. Auto-creating initial chat thread...');
      final newChat = await _ref.read(chatListProvider.notifier).createNewChat();
      _ref.read(activeChatIdProvider.notifier).state = newChat.id;
      targetChatId = newChat.id;
    }

    debugPrint('[Chat] >>> submitPrompt initiated: chatId=$targetChatId, prompt="$cleanPrompt", steps=$steps, cfg=$cfgScale');

    final messageId = _uuid.v4();
    final now = DateTime.now();

    final placeholder = ChatMessage(
      id: messageId,
      chatId: targetChatId,
      prompt: cleanPrompt,
      negativePrompt: negativePrompt?.trim(),
      status: MessageStatus.generating,
      stepProgress: 0,
      totalSteps: steps,
      seed: seed,
      cfgScale: cfgScale,
      createdAt: now,
    );

    // 1. Optimistic UI insertion & DB persistence
    await _repo.insertMessage(placeholder);
    state = [...state, placeholder];

    // Auto-update thread title if this is the first message
    if (state.length == 1) {
      final truncatedTitle = cleanPrompt.length > 28
          ? '${cleanPrompt.substring(0, 28)}...'
          : cleanPrompt;
      await _repo.updateChatTitle(targetChatId, truncatedTitle);
      _ref.read(chatListProvider.notifier).loadChats();
    }

    // 2. Stream generation via InferenceNotifier
    debugPrint('[Chat] Calling _inferenceNotifier.generateImage for message $messageId...');
    final stream = _inferenceNotifier.generateImage(
      messageId: messageId,
      prompt: cleanPrompt,
      negativePrompt: negativePrompt,
      cfgScale: cfgScale,
      steps: steps,
      seed: seed,
    );

    await for (final response in stream) {
      if (response is SdStageResponse) {
        state = [
          for (final m in state)
            if (m.id == messageId)
              m.copyWith(
                stage: response.stage,
                statusMessage: response.message,
                logs: [...m.logs, response.message],
              )
            else
              m
        ];
      } else if (response is SdLogResponse) {
        state = [
          for (final m in state)
            if (m.id == messageId)
              m.copyWith(
                stage: response.stage ?? m.stage,
                statusMessage: response.text,
                logs: m.logs.length > 50
                    ? [...m.logs.sublist(m.logs.length - 49), response.text]
                    : [...m.logs, response.text],
              )
            else
              m
        ];
      } else if (response is SdProgressResponse) {
        state = [
          for (final m in state)
            if (m.id == messageId)
              m.copyWith(
                stage: 'denoising',
                stepProgress: response.step,
                totalSteps: response.totalSteps,
                etaSeconds: response.etaSeconds,
                itPerSec: response.itPerSec,
                statusMessage: 'Denoising Step ${response.step}/${response.totalSteps} (${response.formattedSpeed} • ETA ${response.formattedEta})',
                logs: [...m.logs, '[STEP] Step ${response.step}/${response.totalSteps} (${response.elapsedSeconds.toStringAsFixed(1)}s, ${response.formattedSpeed})'],
              )
            else
              m
        ];
      } else if (response is SdSuccessResponse) {
        await _repo.markMessageCompleted(
          messageId,
          response.outputPngPath,
          response.durationSeconds,
        );

        state = [
          for (final m in state)
            if (m.id == messageId)
              m.copyWith(
                status: MessageStatus.completed,
                imagePath: response.outputPngPath,
                durationSeconds: response.durationSeconds,
                stepProgress: steps,
                statusMessage: 'Completed in ${response.durationSeconds.toStringAsFixed(1)}s',
                logs: [...m.logs, '[DONE] Image successfully generated and saved!'],
              )
            else
              m
        ];
      } else if (response is SdErrorResponse) {
        await _repo.markMessageFailed(messageId, response.errorMessage);

        state = [
          for (final m in state)
            if (m.id == messageId)
              m.copyWith(
                status: MessageStatus.failed,
                errorMessage: response.errorMessage,
                statusMessage: 'Failed: ${response.errorMessage}',
                logs: [...m.logs, '[ERROR] ${response.errorMessage}'],
              )
            else
              m
        ];
      }
    }
  }

  /// Aborts active generation in progress.
  void abortGeneration() {
    debugPrint('[Chat] abortGeneration requested by user.');
    _inferenceNotifier.abort();

    state = [
      for (final m in state)
        if (m.isGenerating)
          m.copyWith(
            status: MessageStatus.failed,
            errorMessage: 'Generation stopped by user.',
            statusMessage: 'Stopped by user',
            logs: [...m.logs, '[ABORT] Inference stopped by user.'],
          )
        else
          m
    ];
  }

  Future<void> retryMessage(ChatMessage message) async {
    await submitPrompt(
      prompt: message.prompt,
      negativePrompt: message.negativePrompt,
      cfgScale: message.cfgScale,
      steps: message.totalSteps,
      seed: message.seed,
    );
  }
}
