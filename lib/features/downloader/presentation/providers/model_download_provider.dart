import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/model_download_state.dart';
import '../../services/model_downloader_service.dart';

final modelDownloadProvider =
    StateNotifierProvider<ModelDownloadNotifier, ModelDownloadState>((ref) {
  return ModelDownloadNotifier();
});

class ModelDownloadNotifier extends StateNotifier<ModelDownloadState> {
  StreamSubscription<ModelDownloadState>? _subscription;

  ModelDownloadNotifier() : super(ModelDownloadState.initial()) {
    _init();
  }

  Future<void> _init() async {
    final service = ModelDownloaderService.instance;
    await service.initialize();
    state = service.currentState;

    _subscription = service.stateStream.listen((newState) {
      state = newState;
    });
  }

  Future<void> startOrResume() async {
    await ModelDownloaderService.instance.startOrResumeDownload();
  }

  Future<void> pause() async {
    await ModelDownloaderService.instance.pauseDownload();
  }

  Future<void> resume() async {
    await ModelDownloaderService.instance.resumeDownload();
  }

  Future<void> cancel() async {
    await ModelDownloaderService.instance.cancelDownload();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

