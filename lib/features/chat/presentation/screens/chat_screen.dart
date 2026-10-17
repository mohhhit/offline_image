import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:offline_image/core/services/storage_service.dart';
import 'package:offline_image/features/downloader/models/model_download_state.dart';
import 'package:offline_image/features/downloader/presentation/providers/model_download_provider.dart';
import 'package:offline_image/features/downloader/presentation/widgets/model_download_sheet.dart';
import 'package:offline_image/features/inference/presentation/providers/inference_provider.dart';
import 'package:offline_image/features/chat/presentation/providers/chat_providers.dart';
import 'package:offline_image/features/chat/models/chat_thread.dart';
import 'package:offline_image/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:offline_image/features/chat/presentation/widgets/prompt_input_bar.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialModelStatus();
      _ensureInitialChat();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialModelStatus() async {
    final isDownloaded = await StorageService.instance.isModelDownloaded();
    if (!isDownloaded && mounted) {
      ModelDownloadSheet.show(context);
    }
  }

  Future<void> _ensureInitialChat() async {
    try {
      final activeId = ref.read(activeChatIdProvider);
      if (activeId == null) {
        final chats = await ref.read(chatRepositoryProvider).getAllChats();
        if (!mounted) return;
        if (chats.isNotEmpty) {
          ref.read(activeChatIdProvider.notifier).state = chats.first.id;
        } else {
          final newChat = await ref.read(chatListProvider.notifier).createNewChat();
          if (!mounted) return;
          ref.read(activeChatIdProvider.notifier).state = newChat.id;
        }
      }
    } catch (e) {
      debugPrint('[ChatScreen] Initial chat setup: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeChatId = ref.watch(activeChatIdProvider);
    final chatList = ref.watch(chatListProvider);
    final messages = ref.watch(activeChatMessagesProvider);
    final inferenceState = ref.watch(inferenceNotifierProvider);
    final downloadState = ref.watch(modelDownloadProvider);

    final ChatThread? currentChat = chatList.where((c) => c.id == activeChatId).firstOrNull ??
        (chatList.isNotEmpty ? chatList.first : null);
    final String displayTitle = currentChat?.title ?? 'Offline Image Session';

    // Auto scroll when messages count changes
    ref.listen(activeChatMessagesProvider, (prev, next) {
      if (prev?.length != next.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            _buildModelStatusSubtitle(context, downloadState),
          ],
        ),
        actions: [
          if (inferenceState.isGenerating)
            IconButton(
              icon: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent),
              tooltip: 'Stop Generation',
              onPressed: () {
                ref.read(activeChatMessagesProvider.notifier).abortGeneration();
              },
            ),
          IconButton(
            icon: const Icon(Icons.add_comment_rounded),
            tooltip: 'New Chat Session',
            onPressed: () async {
              final newChat =
                  await ref.read(chatListProvider.notifier).createNewChat();
              ref.read(activeChatIdProvider.notifier).state = newChat.id;
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context, chatList, activeChatId),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return ChatBubble(
                        message: message,
                        onRetry: () {
                          ref
                              .read(activeChatMessagesProvider.notifier)
                              .retryMessage(message);
                        },
                        onStop: () {
                          ref
                              .read(activeChatMessagesProvider.notifier)
                              .abortGeneration();
                        },
                      );
                    },
                  ),
          ),
          PromptInputBar(
            isGenerating: inferenceState.isGenerating,
            onStop: () {
              ref.read(activeChatMessagesProvider.notifier).abortGeneration();
            },
            onSubmit: ({
              required String prompt,
              String? negativePrompt,
              double cfgScale = 7.0,
              int steps = 20,
              int seed = -1,
            }) async {
              final isDownloaded = await StorageService.instance.isModelDownloaded();
              if (!isDownloaded && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Model file not found on disk. Please download the 2.1 GB model weights first.'),
                    duration: Duration(seconds: 4),
                  ),
                );
                ModelDownloadSheet.show(context);
                return;
              }

              ref.read(activeChatMessagesProvider.notifier).submitPrompt(
                    prompt: prompt,
                    negativePrompt: negativePrompt,
                    cfgScale: cfgScale,
                    steps: steps,
                    seed: seed,
                  );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModelStatusSubtitle(
    BuildContext context,
    ModelDownloadState downloadState,
  ) {
    final theme = Theme.of(context);

    if (downloadState.isDone) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '100% Offline SD 2.1 Ready',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.greenAccent,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (downloadState.isDownloading) {
      return InkWell(
        onTap: () => ModelDownloadSheet.show(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Downloading Model (${downloadState.formattedProgress})',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => ModelDownloadSheet.show(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 10, color: Colors.amber),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Model Missing (Tap to Download)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.amber,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    List chatList,
    String? activeChatId,
  ) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.photo_library_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Offline SD 2.1',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('New Session'),
              onTap: () async {
                Navigator.of(context).pop();
                final newChat =
                    await ref.read(chatListProvider.notifier).createNewChat();
                ref.read(activeChatIdProvider.notifier).state = newChat.id;
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: chatList.length,
                itemBuilder: (context, index) {
                  final chat = chatList[index];
                  final isSelected = chat.id == activeChatId;

                  return ListTile(
                    selected: isSelected,
                    leading: const Icon(Icons.chat_bubble_outline_rounded),
                    title: Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () async {
                        await ref
                            .read(chatListProvider.notifier)
                            .deleteChat(chat.id);
                        if (chat.id == activeChatId) {
                          _ensureInitialChat();
                        }
                      },
                    ),
                    onTap: () {
                      ref.read(activeChatIdProvider.notifier).state = chat.id;
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Manage Model File'),
              subtitle: const Text('2.13 GB GGUF'),
              onTap: () {
                Navigator.of(context).pop();
                ModelDownloadSheet.show(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = [
      'A cinematic astronaut riding a horse on Mars, 8k resolution, dramatic lighting',
      'A cozy wooden cabin during a gentle snowstorm at twilight, warm window glow',
      'A cyberpunk samurai cat standing on a rain-slicked neon street',
      'An oil painting of a vintage cafe in Paris in autumn, vibrant colors',
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Offline Stable Diffusion',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All image synthesis runs 100% on your device hardware without internet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Sample Prompts',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...suggestions.map(
              (prompt) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    ref.read(activeChatMessagesProvider.notifier).submitPrompt(
                          prompt: prompt,
                        );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      prompt,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
