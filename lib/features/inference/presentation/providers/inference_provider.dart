import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:offline_image/core/services/storage_service.dart';
import 'package:offline_image/core/services/wakelock_service.dart';
import 'package:offline_image/features/inference/isolate/sd_isolate_protocol.dart';
import 'package:offline_image/features/inference/isolate/sd_isolate_worker.dart';

final sdWorkerProvider = Provider<SdIsolateWorker>((ref) {
  final worker = SdIsolateWorker();
  ref.onDispose(() {
    worker.dispose();
  });
  return worker;
});

class InferenceState {
  final bool isModelLoaded;
  final bool isGenerating;
  final String? activeMessageId;
  final int currentStep;
  final int totalSteps;
  final String? statusText;

  const InferenceState({
    this.isModelLoaded = false,
    this.isGenerating = false,
    this.activeMessageId,
    this.currentStep = 0,
    this.totalSteps = 20,
    this.statusText,
  });

  double get fraction => totalSteps > 0 ? (currentStep / totalSteps).clamp(0.0, 1.0) : 0.0;
  int get percentage => (fraction * 100).toInt();

  InferenceState copyWith({
    bool? isModelLoaded,
    bool? isGenerating,
    String? activeMessageId,
    int? currentStep,
    int? totalSteps,
    String? statusText,
  }) {
    return InferenceState(
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      isGenerating: isGenerating ?? this.isGenerating,
      activeMessageId: activeMessageId ?? this.activeMessageId,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      statusText: statusText ?? this.statusText,
    );
  }
}

final inferenceNotifierProvider =
    StateNotifierProvider<InferenceNotifier, InferenceState>((ref) {
  final worker = ref.watch(sdWorkerProvider);
  return InferenceNotifier(worker);
});

class InferenceNotifier extends StateNotifier<InferenceState> {
  final SdIsolateWorker _worker;

  InferenceNotifier(this._worker) : super(const InferenceState());

  /// Ensures model is initialized into RAM.
  Future<bool> ensureModelLoaded() async {
    if (state.isModelLoaded) {
      debugPrint('[InferenceNotifier] Model is already loaded in RAM.');
      return true;
    }

    final isDownloaded = await StorageService.instance.isModelDownloaded();
    final modelPath = await StorageService.instance.modelFilePath;
    debugPrint('[InferenceNotifier] ensureModelLoaded: isDownloaded=$isDownloaded, modelPath=$modelPath');

    if (!isDownloaded) {
      debugPrint('[InferenceNotifier] ABORT: Model file not downloaded or incomplete.');
      state = state.copyWith(statusText: 'Model file not found on disk. Download required.');
      return false;
    }

    state = state.copyWith(statusText: 'Loading model weights into memory (mmap)...');
    debugPrint('[InferenceNotifier] Calling _worker.loadModel(modelPath: $modelPath)...');
    final success = await _worker.loadModel(modelPath: modelPath);
    debugPrint('[InferenceNotifier] _worker.loadModel returned: $success');

    state = state.copyWith(
      isModelLoaded: success,
      statusText: success ? 'Model ready' : 'Failed to load model weights',
    );
    return success;
  }

  /// Executes text-to-image inference with Wakelock keep-alive and progress streaming.
  Stream<SdResponse> generateImage({
    required String messageId,
    required String prompt,
    String? negativePrompt,
    double cfgScale = 7.0,
    int steps = 20,
    int seed = -1,
  }) async* {
    if (state.isGenerating) {
      debugPrint('[InferenceNotifier] ERROR: Another generation is already in progress.');
      throw StateError('Another generation is already running.');
    }

    debugPrint('[InferenceNotifier] >>> generateImage messageId=$messageId, prompt="$prompt"');

    state = state.copyWith(
      isGenerating: true,
      activeMessageId: messageId,
      currentStep: 0,
      totalSteps: steps,
      statusText: 'Preparing model and hardware environment...',
    );

    // 1. Acquire Wakelock
    await WakelockService.instance.acquire('inference');

    // 2. Stream event subscription during model loading
    yield const SdStageResponse(
      stage: 'loading_weights',
      message: 'Loading 2.18 GB GGUF model weights into RAM...',
    );
    yield SdLogResponse(
      text: '[Inference] Preparing model weights for: "$prompt"',
      stage: 'loading_weights',
    );

    final loadLogs = <SdResponse>[];
    final loadSub = _worker.eventStream.listen((event) {
      if (event is SdLogResponse || event is SdStageResponse) {
        loadLogs.add(event);
      }
    });

    // 3. Ensure model is loaded in memory
    final loaded = await ensureModelLoaded();
    await loadSub.cancel();

    for (final l in loadLogs) {
      yield l;
    }

    if (!loaded) {
      debugPrint('[InferenceNotifier] Model could not be loaded into RAM. Aborting generation.');
      await WakelockService.instance.release('inference');
      yield const SdErrorResponse(
        errorCode: -1,
        errorMessage: 'Unable to load model weights. Please ensure the model is fully downloaded.',
      );
      return;
    }

    // 4. Prepare target image path
    final outputPath = await StorageService.instance.createNewImagePath(messageId);

    yield const SdStageResponse(
      stage: 'prompt_encoding',
      message: 'Encoding prompt text embeddings via CLIP...',
    );

    state = state.copyWith(
      statusText: 'Starting latent diffusion denoising loop...',
    );

    final stream = _worker.generate(
      SdGenerateCommand(
        prompt: prompt,
        negativePrompt: negativePrompt,
        cfgScale: cfgScale,
        sampleSteps: steps,
        seed: seed,
        outputPngPath: outputPath,
      ),
    );

    try {
      await for (final response in stream) {
        if (response is SdLogResponse) {
          state = state.copyWith(statusText: response.text);
          yield response;
        } else if (response is SdStageResponse) {
          state = state.copyWith(statusText: response.message);
          yield response;
        } else if (response is SdProgressResponse) {
          state = state.copyWith(
            currentStep: response.step,
            totalSteps: response.totalSteps,
            statusText: 'Denoising step ${response.step}/${response.totalSteps} (${response.formattedSpeed} • ETA ${response.formattedEta})',
          );
          yield response;
        } else if (response is SdSuccessResponse) {
          state = state.copyWith(
            isGenerating: false,
            activeMessageId: null,
            statusText: 'Generation finished in ${response.durationSeconds.toStringAsFixed(1)}s',
          );
          yield response;
        } else if (response is SdErrorResponse) {
          state = state.copyWith(
            isGenerating: false,
            activeMessageId: null,
            statusText: 'Error: ${response.errorMessage}',
          );
          yield response;
        }
      }
    } finally {
      // Release hardware wakelock unconditionally
      await WakelockService.instance.release('inference');
      state = state.copyWith(isGenerating: false, activeMessageId: null);
    }
  }

  void abort() {
    _worker.abort();
    WakelockService.instance.release('inference');
    state = state.copyWith(isGenerating: false, activeMessageId: null);
  }
}
