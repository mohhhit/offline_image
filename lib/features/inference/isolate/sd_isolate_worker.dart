import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../ffi/sd_bindings.dart';
import '../ffi/sd_native_library.dart';
import 'sd_isolate_protocol.dart';

/// Worker manager that runs the heavy C++ inference inside a dedicated background isolate.
/// Prevents main UI frame drops, ANR dialogs, and watchdog termination.
class SdIsolateWorker {
  Isolate? _isolate;
  SendPort? _commandsSendPort;
  ReceivePort? _responsesReceivePort;
  StreamSubscription? _responsesSubscription;

  Completer<bool>? _initCompleter;
  StreamController<SdResponse>? _generationStreamController;
  final StreamController<SdResponse> _eventBroadcastController =
      StreamController<SdResponse>.broadcast();

  Stream<SdResponse> get eventStream => _eventBroadcastController.stream;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Starts the background isolate and waits for the handshake.
  Future<void> start() async {
    if (_isolate != null) return;

    debugPrint('[SdIsolateWorker] Spawning background worker isolate...');
    _responsesReceivePort = ReceivePort();
    final readyCompleter = Completer<SendPort>();

    _responsesSubscription = _responsesReceivePort!.listen((message) {
      if (message is SdWorkerReadyResponse) {
        debugPrint('[SdIsolateWorker] Worker isolate ready handshake received.');
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete(message.sendPort);
        }
      } else if (message is SdInitResponse) {
        debugPrint('[SdIsolateWorker] SdInitResponse received: success=${message.success}, info=${message.systemInfo}, error=${message.error}');
        _isInitialized = message.success;
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.complete(message.success);
        }
      } else if (message is SdResponse) {
        _eventBroadcastController.add(message);
        _generationStreamController?.add(message);
        if (message is SdSuccessResponse || message is SdErrorResponse) {
          _generationStreamController?.close();
          _generationStreamController = null;
        }
      }
    });

    _isolate = await Isolate.spawn(
      _sdWorkerEntryPoint,
      _responsesReceivePort!.sendPort,
      debugName: 'StableDiffusionInferenceWorker',
    );

    _commandsSendPort = await readyCompleter.future;
    debugPrint('[SdIsolateWorker] Background isolate connected.');
  }

  /// Loads the GGUF model weights into RAM inside the worker isolate.
  Future<bool> loadModel({
    required String modelPath,
    int? nThreads,
    bool vaeTiling = true,
  }) async {
    if (_commandsSendPort == null) {
      await start();
    }

    // Default threads to max(1, min(cores - 1, 4))
    final cores = Platform.numberOfProcessors;
    final threads = nThreads ?? (cores > 1 ? (cores - 1).clamp(1, 4) : 1);

    debugPrint('[SdIsolateWorker] loadModel dispatching command to isolate: path=$modelPath, threads=$threads');
    _initCompleter = Completer<bool>();
    _commandsSendPort!.send(
      SdInitCommand(
        modelPath: modelPath,
        nThreads: threads,
        vaeTiling: vaeTiling,
      ),
    );

    return _initCompleter!.future;
  }

  /// Dispatches an image generation command.
  /// Yields progress updates, live terminal logs, and terminates with success or error.
  Stream<SdResponse> generate(SdGenerateCommand command) {
    if (_commandsSendPort == null) {
      throw StateError('Worker isolate is not running. Call start() first.');
    }

    _generationStreamController?.close();
    _generationStreamController = StreamController<SdResponse>.broadcast();

    _commandsSendPort!.send(command);
    return _generationStreamController!.stream;
  }

  /// Requests aborting active generation.
  void abort() {
    _commandsSendPort?.send(const SdAbortCommand());
  }

  /// Releases model weights and kills the worker isolate.
  Future<void> dispose() async {
    _commandsSendPort?.send(const SdDisposeCommand());
    await _responsesSubscription?.cancel();
    _responsesReceivePort?.close();
    _eventBroadcastController.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandsSendPort = null;
    _responsesReceivePort = null;
    _isInitialized = false;
  }

  /// Incurs the current pipeline stage from raw engine log strings.
  static String? _inferStageFromLog(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('loader') ||
        lower.contains('loading weights') ||
        lower.contains('gguf file') ||
        lower.contains('building ggml')) {
      return 'loading_weights';
    }
    if (lower.contains('tokeniz') ||
        lower.contains('clip') ||
        lower.contains('prompt') ||
        lower.contains('conditioning')) {
      return 'prompt_encoding';
    }
    if (lower.contains('step') ||
        lower.contains('denois') ||
        lower.contains('sampling') ||
        lower.contains('get_learned_condition completed')) {
      return 'denoising';
    }
    if (lower.contains('vae') ||
        lower.contains('decode complete') ||
        lower.contains('decoding latents')) {
      return 'decoding_vae';
    }
    if (lower.contains('png') ||
        lower.contains('stbi') ||
        lower.contains('compressing png') ||
        lower.contains('written to disk')) {
      return 'saving_image';
    }
    return null;
  }

  /// Isolate entry point.
  static void _sdWorkerEntryPoint(SendPort uiSendPort) {
    debugPrint('[WorkerIsolate] Entry point running in background thread.');
    final workerReceivePort = ReceivePort();
    uiSendPort.send(SdWorkerReadyResponse(workerReceivePort.sendPort));

    late final SdBindings bindings;
    try {
      debugPrint('[WorkerIsolate] Loading native library via SdNativeLibrary.load()...');
      final lib = SdNativeLibrary.load();
      bindings = SdBindings(lib);
      debugPrint('[WorkerIsolate] Native library loaded successfully.');
    } catch (e) {
      debugPrint('[WorkerIsolate] ERROR: Failed to load native library: $e');
      uiSendPort.send(
        SdInitResponse(
          success: false,
          error: 'Failed to load native library: $e',
        ),
      );
      return;
    }

    // Register live native engine log forwarder to Dart UI isolate
    NativeCallable<SdBridgeLogCbNative>? logCallable;
    try {
      logCallable = NativeCallable<SdBridgeLogCbNative>.listener(
        (int level, Pointer<Utf8> textPtr) {
          if (textPtr != nullptr) {
            final line = textPtr.toDartString().trim();
            if (line.isNotEmpty) {
              final stage = _inferStageFromLog(line);
              uiSendPort.send(SdLogResponse(text: line, stage: stage));
            }
          }
        },
      );
      bindings.setLogCallback(logCallable.nativeFunction);
      debugPrint('[WorkerIsolate] Native log callback registered.');
    } catch (e) {
      debugPrint('[WorkerIsolate] Warning: could not register native log callback: $e');
    }

    Pointer<Void> ctx = nullptr;

    workerReceivePort.listen((message) async {
      if (message is SdInitCommand) {
        debugPrint('[WorkerIsolate] >>> Handling SdInitCommand for path: ${message.modelPath}');
        if (ctx != nullptr) {
          debugPrint('[WorkerIsolate] Freeing existing context before reallocating...');
          bindings.freeContext(ctx);
          ctx = nullptr;
        }

        try {
          final file = File(message.modelPath);
          final exists = file.existsSync();
          final size = exists ? file.lengthSync() : 0;
          debugPrint('[WorkerIsolate] Model file check: exists=$exists, size=$size bytes (${(size / (1024 * 1024)).toStringAsFixed(1)} MB)');

          if (!exists || size < 1000000) {
            debugPrint('[WorkerIsolate] ERROR: Model file does not exist or is too small!');
            uiSendPort.send(
              SdInitResponse(
                success: false,
                error: 'Model file does not exist on disk at path: ${message.modelPath}',
              ),
            );
            return;
          }

          uiSendPort.send(
            SdLogResponse(
              text: '[LOADER] Opening 2.18 GB GGUF model file on flash storage...',
              stage: 'loading_weights',
            ),
          );

          debugPrint('[WorkerIsolate] Calling bindings.init(threads=${message.nThreads}, vaeTiling=${message.vaeTiling})...');
          ctx = bindings.init(
            modelPath: message.modelPath,
            nThreads: message.nThreads,
            vaeTiling: message.vaeTiling,
          );

          if (ctx == nullptr) {
            debugPrint('[WorkerIsolate] ERROR: bindings.init returned nullptr! (OOM or invalid model header)');
            uiSendPort.send(
              const SdInitResponse(
                success: false,
                error: 'Failed to allocate Stable Diffusion context (OOM or invalid GGUF format)',
              ),
            );
          } else {
            final info = bindings.getSystemInfo();
            debugPrint('[WorkerIsolate] SUCCESS: Stable Diffusion context created: $ctx. System info: $info');
            uiSendPort.send(
              SdInitResponse(
                success: true,
                systemInfo: info,
              ),
            );
          }
        } catch (e, stack) {
          debugPrint('[WorkerIsolate] Exception during model initialization: $e\n$stack');
          uiSendPort.send(
            SdInitResponse(
              success: false,
              error: 'Exception during model initialization: $e',
            ),
          );
        }
      } else if (message is SdGenerateCommand) {
        debugPrint('[WorkerIsolate] >>> Handling SdGenerateCommand: prompt="${message.prompt}", steps=${message.sampleSteps}, cfg=${message.cfgScale}, out="${message.outputPngPath}"');
        if (ctx == nullptr) {
          debugPrint('[WorkerIsolate] ERROR: Model context is nullptr! Cannot generate.');
          uiSendPort.send(
            const SdErrorResponse(
              errorCode: -1,
              errorMessage: 'Model context is not initialized.',
            ),
          );
          return;
        }

        final stopwatch = Stopwatch()..start();
        final completer = Completer<void>();

        // Native callable for receiving step callbacks from C++
        late final NativeCallable<SdBridgeProgressCbNative> progressCallable;
        late final NativeCallable<SdBridgeCompletionCbNative> completionCallable;

        progressCallable = NativeCallable<SdBridgeProgressCbNative>.listener(
          (int step, int totalSteps, double elapsedSeconds) {
            final double stepDuration = step > 0 ? (elapsedSeconds / step) : elapsedSeconds;
            final int remainingSteps = (totalSteps - step).clamp(0, totalSteps);
            final double eta = stepDuration * remainingSteps;
            final double itPerSec = stepDuration > 0 ? (1.0 / stepDuration) : 0.0;

            debugPrint('[WorkerIsolate] Step callback: $step/$totalSteps (${elapsedSeconds.toStringAsFixed(1)}s, ${itPerSec.toStringAsFixed(2)} it/s, ETA: ${eta.toStringAsFixed(0)}s)');

            uiSendPort.send(
              SdProgressResponse(
                step: step,
                totalSteps: totalSteps,
                elapsedSeconds: elapsedSeconds,
                etaSeconds: eta,
                itPerSec: itPerSec,
              ),
            );
          },
        );

        completionCallable = NativeCallable<SdBridgeCompletionCbNative>.listener(
          (int statusCode, Pointer<Utf8> msgOrPathPtr) {
            stopwatch.stop();
            final msgOrPath = msgOrPathPtr != nullptr ? msgOrPathPtr.toDartString() : '';
            debugPrint('[WorkerIsolate] Completion callback: statusCode=$statusCode, msgOrPath=$msgOrPath in ${stopwatch.elapsedMilliseconds}ms');

            if (statusCode == 0) {
              debugPrint('[WorkerIsolate] Generation SUCCESS! Output file: ${message.outputPngPath}');
              uiSendPort.send(
                SdSuccessResponse(
                  outputPngPath: message.outputPngPath,
                  durationSeconds: stopwatch.elapsedMilliseconds / 1000.0,
                ),
              );
            } else if (statusCode == 1) {
              debugPrint('[WorkerIsolate] Generation CANCELLED by user.');
              uiSendPort.send(
                const SdErrorResponse(
                  errorCode: 1,
                  errorMessage: 'Generation was stopped by user.',
                ),
              );
            } else {
              final errorMsg = _mapErrorCodeToMessage(statusCode);
              debugPrint('[WorkerIsolate] Generation FAILED with code $statusCode: $errorMsg ($msgOrPath)');
              uiSendPort.send(
                SdErrorResponse(
                  errorCode: statusCode,
                  errorMessage: '$errorMsg ($msgOrPath)',
                ),
              );
            }

            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        );

        try {
          uiSendPort.send(
            SdLogResponse(
              text: '[INFERENCE] Parsing prompt and preparing latent space...',
              stage: 'prompt_encoding',
            ),
          );

          debugPrint('[WorkerIsolate] Invoking bindings.txt2imgAsync...');
          final startResult = bindings.txt2imgAsync(
            ctx: ctx,
            prompt: message.prompt,
            negativePrompt: message.negativePrompt,
            cfgScale: message.cfgScale,
            width: message.width,
            height: message.height,
            sampleMethod: message.sampleMethod,
            sampleSteps: message.sampleSteps,
            seed: message.seed,
            outputPngPath: message.outputPngPath,
            progressCb: progressCallable.nativeFunction,
            completionCb: completionCallable.nativeFunction,
          );

          if (startResult != 0) {
            stopwatch.stop();
            final errorMsg = _mapErrorCodeToMessage(startResult);
            debugPrint('[WorkerIsolate] txt2imgAsync start failed with code $startResult: $errorMsg');
            uiSendPort.send(
              SdErrorResponse(
                errorCode: startResult,
                errorMessage: errorMsg,
              ),
            );
            progressCallable.close();
            completionCallable.close();
            return;
          }

          // Await asynchronous completion without blocking the isolate event loop
          await completer.future;
        } catch (e, stack) {
          stopwatch.stop();
          debugPrint('[WorkerIsolate] Native execution crash: $e\n$stack');
          uiSendPort.send(
            SdErrorResponse(
              errorCode: -99,
              errorMessage: 'Native execution crash: $e',
            ),
          );
        } finally {
          progressCallable.close();
          completionCallable.close();
        }
      } else if (message is SdAbortCommand) {
        debugPrint('[WorkerIsolate] Handling SdAbortCommand: aborting active generation immediately!');
        if (ctx != nullptr) {
          bindings.abort(ctx);
        }
      } else if (message is SdDisposeCommand) {
        debugPrint('[WorkerIsolate] Handling SdDisposeCommand');
        if (ctx != nullptr) {
          bindings.freeContext(ctx);
          ctx = nullptr;
        }
        logCallable?.close();
        workerReceivePort.close();
      }
    });
  }

  static String _mapErrorCodeToMessage(int code) {
    switch (code) {
      case -1:
        return 'Context pointer is null.';
      case -2:
        return 'Invalid or empty prompt.';
      case -3:
        return 'Invalid output destination path.';
      case -4:
        return 'Inference failed: Out of Memory (OOM) or tensor allocation failed.';
      case -5:
        return 'Pixel buffer is empty or dimensions are 0.';
      case -6:
        return 'Failed to encode or write PNG to disk.';
      case -10:
        return 'Fatal Out of Memory (OOM) during UNet/VAE pass.';
      default:
        return 'Native execution error (code: $code).';
    }
  }
}
