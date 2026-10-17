import 'package:flutter_test/flutter_test.dart';
import 'package:offline_image/features/chat/models/chat_message.dart';
import 'package:offline_image/features/chat/models/chat_thread.dart';
import 'package:offline_image/features/downloader/models/model_download_state.dart';

void main() {
  group('Data Model Tests', () {
    test('ChatThread serialization and deserialization', () {
      final now = DateTime.now();
      final thread = ChatThread(
        id: 'test-thread-id',
        title: 'Cyberpunk City',
        createdAt: now,
        updatedAt: now,
      );

      final map = thread.toMap();
      expect(map['id'], 'test-thread-id');
      expect(map['title'], 'Cyberpunk City');

      final reconstructed = ChatThread.fromMap(map);
      expect(reconstructed.id, thread.id);
      expect(reconstructed.title, thread.title);
    });

    test('ChatMessage state transitions and progress calculation', () {
      final now = DateTime.now();
      var message = ChatMessage(
        id: 'msg-1',
        chatId: 'thread-1',
        prompt: 'A sunset over mountains',
        status: MessageStatus.generating,
        stepProgress: 10,
        totalSteps: 20,
        createdAt: now,
      );

      expect(message.isGenerating, isTrue);
      expect(message.progressFraction, 0.5);

      message = message.copyWith(
        status: MessageStatus.completed,
        imagePath: '/path/to/image.png',
        durationSeconds: 24.5,
      );

      expect(message.isCompleted, isTrue);
      expect(message.imagePath, '/path/to/image.png');
      expect(message.durationSeconds, 24.5);
    });

    test('ModelDownloadState progress calculation and formatting', () {
      final state = ModelDownloadState(
        status: DownloadStatus.downloading,
        progress: 0.655,
        networkSpeedMBs: 14.2,
        bytesDownloaded: 1500000000,
        totalBytes: 2287474432,
      );

      expect(state.formattedProgress, '65.5%');
      expect(state.isDownloading, isTrue);
      expect(state.networkSpeedMBs, 14.2);
    });
  });
}
