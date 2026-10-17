import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/model_urls.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/wakelock_service.dart';
import '../models/model_download_state.dart';

/// Production download service leveraging native OS background services (WorkManager / NSURLSession).
/// Supports HTTP 206 Partial Content range requests, automatic byte resumption, and wakelock control.
class ModelDownloaderService {
  ModelDownloaderService._();
  static final ModelDownloaderService instance = ModelDownloaderService._();

  DownloadTask? _activeTask;
  StreamSubscription<TaskUpdate>? _updatesSubscription;
  final StreamController<ModelDownloadState> _stateController =
      StreamController<ModelDownloadState>.broadcast();

  Stream<ModelDownloadState> get stateStream => _stateController.stream;
  ModelDownloadState _currentState = ModelDownloadState.initial();
  ModelDownloadState get currentState => _currentState;

  /// Initializes the background downloader callbacks.
  Future<void> initialize() async {
    // Check if model already exists on disk
    final isDownloaded = await StorageService.instance.isModelDownloaded();
    if (isDownloaded) {
      final path = await StorageService.instance.modelFilePath;
      _updateState(ModelDownloadState.completed(path));
      return;
    }

    // Configure OS-level notification for background download visibility
    FileDownloader().configureNotification(
      running: const TaskNotification(
        'Downloading Stable Diffusion Model',
        'Progress: {progress} ({networkSpeed})',
      ),
      complete: const TaskNotification(
        'Model Ready',
        'Stable Diffusion 2.1 Q4_0 model is ready for offline generation.',
      ),
      error: const TaskNotification(
        'Download Failed',
        'Network interrupted. Tap to resume download.',
      ),
      progressBar: true,
    );

    // Listen to native updates
    _updatesSubscription?.cancel();
    _updatesSubscription = FileDownloader().updates.listen(_handleTaskUpdate);
  }

  /// Initiates or resumes the GGUF model download.
  Future<void> startOrResumeDownload() async {
    _updateState(_currentState.copyWith(status: DownloadStatus.checkingStorage));

    // 1. Storage pre-flight check
    final freeSpace = await StorageService.instance.getAvailableStorageBytes();
    if (freeSpace < ModelUrls.minRequiredStorageBytes) {
      _updateState(
        ModelDownloadState.failed(
          'Insufficient disk storage. At least 5.0 GB free space required.',
        ),
      );
      return;
    }

    // 2. Prepare destination directory
    await StorageService.instance.modelsDirectory;

    // 3. Acquire hardware wakelock
    await WakelockService.instance.acquire('model_download');

    // 4. Create or reuse background resumable download task
    _activeTask ??= DownloadTask(
      taskId: 'sd_v2_1_q4_0_model_task',
      url: ModelUrls.modelDownloadRawUrl,
      filename: ModelUrls.modelFileName,
      baseDirectory: BaseDirectory.applicationDocuments,
      directory: 'models',
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 10, // Resilient retry policy for flaky mobile networks
    );

    _updateState(
      _currentState.copyWith(
        status: DownloadStatus.downloading,
        totalBytes: ModelUrls.expectedModelSizeBytes,
      ),
    );

    // 5. Enqueue with native background execution engine
    final enqueued = await FileDownloader().enqueue(_activeTask!);
    if (!enqueued) {
      await WakelockService.instance.release('model_download');
      _updateState(
        ModelDownloadState.failed('Failed to enqueue download task into OS engine.'),
      );
    }
  }

  /// Pauses the active download. Preserves current byte offset for range resumption.
  Future<void> pauseDownload() async {
    if (_activeTask != null) {
      await FileDownloader().pause(_activeTask!);
      await WakelockService.instance.release('model_download');
      _updateState(_currentState.copyWith(status: DownloadStatus.paused));
    }
  }

  /// Resumes a paused download from the exact byte where it paused.
  Future<void> resumeDownload() async {
    if (_activeTask != null) {
      await WakelockService.instance.acquire('model_download');
      final resumed = await FileDownloader().resume(_activeTask!);
      if (resumed) {
        _updateState(_currentState.copyWith(status: DownloadStatus.downloading));
      } else {
        // Fallback: enqueue again (HTTP Range will automatically be requested)
        await FileDownloader().enqueue(_activeTask!);
      }
    } else {
      await startOrResumeDownload();
    }
  }

  /// Cancels and deletes incomplete partial downloads.
  Future<void> cancelDownload() async {
    if (_activeTask != null) {
      await FileDownloader().cancelTaskWithId(_activeTask!.taskId);
      await WakelockService.instance.release('model_download');
      _activeTask = null;
      _updateState(ModelDownloadState.initial());
    }
  }

  void _handleTaskUpdate(TaskUpdate update) async {
    if (update is TaskProgressUpdate) {
      final progress = update.progress.clamp(0.0, 1.0);
      final expected = update.expectedFileSize > 0
          ? update.expectedFileSize
          : ModelUrls.expectedModelSizeBytes;
      final bytesDownloaded = (progress * expected).toInt();

      _updateState(
        _currentState.copyWith(
          status: DownloadStatus.downloading,
          progress: progress,
          networkSpeedMBs: update.networkSpeed, // in MB/s
          timeRemaining: update.timeRemaining,
          bytesDownloaded: bytesDownloaded,
          totalBytes: expected,
        ),
      );
    } else if (update is TaskStatusUpdate) {
      debugPrint('[Downloader] TaskStatusUpdate: ${update.status}');
      switch (update.status) {
        case TaskStatus.complete:
          await WakelockService.instance.release('model_download');
          final docs = await StorageService.instance.documentsDir;
          final finalPath = p.join(docs.path, 'models', ModelUrls.modelFileName);

          // Verify file actually exists and has content
          final file = File(finalPath);
          if (await file.exists() && await file.length() > 1000000) {
            _updateState(ModelDownloadState.completed(finalPath));
          } else {
            _updateState(
              ModelDownloadState.failed(
                'Download reported complete but file is missing or corrupted.',
              ),
            );
          }
          break;

        case TaskStatus.paused:
          await WakelockService.instance.release('model_download');
          _updateState(_currentState.copyWith(status: DownloadStatus.paused));
          break;

        case TaskStatus.canceled:
          await WakelockService.instance.release('model_download');
          _updateState(ModelDownloadState.initial());
          break;

        case TaskStatus.failed:
          await WakelockService.instance.release('model_download');
          _updateState(
            ModelDownloadState.failed(
              'Download interrupted or network connection lost.',
            ),
          );
          break;

        default:
          break;
      }
    }
  }

  void _updateState(ModelDownloadState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void dispose() {
    _updatesSubscription?.cancel();
    _stateController.close();
  }
}
