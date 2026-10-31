import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'ffi_safe_string.dart';

export 'ffi_safe_string.dart';

// Native function typedefs for FFI mapping
typedef SdBridgeProgressCbNative = Void Function(
  Int32 step,
  Int32 totalSteps,
  Float elapsedSeconds,
);
typedef SdBridgeProgressCbDart = void Function(
  int step,
  int totalSteps,
  double elapsedSeconds,
);

// sd_bridge_init
typedef NativeInit = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  Int32 nThreads,
  Bool vaeTiling,
  Bool useMetal,
);
typedef DartInit = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  int nThreads,
  bool vaeTiling,
  bool useMetal,
);

// sd_bridge_txt2img_to_file
typedef NativeTxt2ImgToFile = Int32 Function(
  Pointer<Void> ctx,
  Pointer<Utf8> prompt,
  Pointer<Utf8> negativePrompt,
  Float cfgScale,
  Int32 width,
  Int32 height,
  Int32 sampleMethod,
  Int32 sampleSteps,
  Int64 seed,
  Pointer<Utf8> outputPngPath,
  Pointer<NativeFunction<SdBridgeProgressCbNative>> progressCb,
);
typedef DartTxt2ImgToFile = int Function(
  Pointer<Void> ctx,
  Pointer<Utf8> prompt,
  Pointer<Utf8> negativePrompt,
  double cfgScale,
  int width,
  int height,
  int sampleMethod,
  int sampleSteps,
  int seed,
  Pointer<Utf8> outputPngPath,
  Pointer<NativeFunction<SdBridgeProgressCbNative>> progressCb,
);

// sd_bridge_txt2img_async
typedef SdBridgeCompletionCbNative = Void Function(
  Int32 statusCode,
  Pointer<Utf8> messageOrPath,
);
typedef SdBridgeCompletionCbDart = void Function(
  int statusCode,
  Pointer<Utf8> messageOrPath,
);

typedef NativeTxt2ImgAsync = Int32 Function(
  Pointer<Void> ctx,
  Pointer<Utf8> prompt,
  Pointer<Utf8> negativePrompt,
  Float cfgScale,
  Int32 width,
  Int32 height,
  Int32 sampleMethod,
  Int32 sampleSteps,
  Int64 seed,
  Pointer<Utf8> outputPngPath,
  Pointer<NativeFunction<SdBridgeProgressCbNative>> progressCb,
  Pointer<NativeFunction<SdBridgeCompletionCbNative>> completionCb,
);
typedef DartTxt2ImgAsync = int Function(
  Pointer<Void> ctx,
  Pointer<Utf8> prompt,
  Pointer<Utf8> negativePrompt,
  double cfgScale,
  int width,
  int height,
  int sampleMethod,
  int sampleSteps,
  int seed,
  Pointer<Utf8> outputPngPath,
  Pointer<NativeFunction<SdBridgeProgressCbNative>> progressCb,
  Pointer<NativeFunction<SdBridgeCompletionCbNative>> completionCb,
);

// sd_bridge_abort
typedef NativeAbort = Void Function(Pointer<Void> ctx);
typedef DartAbort = void Function(Pointer<Void> ctx);

// sd_bridge_free
typedef NativeFree = Void Function(Pointer<Void> ctx);
typedef DartFree = void Function(Pointer<Void> ctx);

// sd_bridge_get_system_info
typedef NativeGetSystemInfo = Pointer<Utf8> Function();
typedef DartGetSystemInfo = Pointer<Utf8> Function();

// sd_bridge_set_log_callback
typedef SdBridgeLogCbNative = Void Function(Int32 level, Pointer<Utf8> text);
typedef SdBridgeLogCbDart = void Function(int level, Pointer<Utf8> text);

typedef NativeSetLogCallback = Void Function(
  Pointer<NativeFunction<SdBridgeLogCbNative>> logCb,
);
typedef DartSetLogCallback = void Function(
  Pointer<NativeFunction<SdBridgeLogCbNative>> logCb,
);

/// Typed Dart FFI wrapper interfacing with the native C++ library.
class SdBindings {
  final DynamicLibrary _lib;

  late final DartInit _init;
  late final DartTxt2ImgToFile _txt2imgToFile;
  late final DartTxt2ImgAsync _txt2imgAsync;
  late final DartAbort _abort;
  late final DartFree _free;
  late final DartGetSystemInfo _getSystemInfo;
  late final DartSetLogCallback _setLogCallback;

  SdBindings(this._lib) {
    _init = _lib
        .lookup<NativeFunction<NativeInit>>('sd_bridge_init')
        .asFunction<DartInit>();

    _txt2imgToFile = _lib
        .lookup<NativeFunction<NativeTxt2ImgToFile>>('sd_bridge_txt2img_to_file')
        .asFunction<DartTxt2ImgToFile>();

    _txt2imgAsync = _lib
        .lookup<NativeFunction<NativeTxt2ImgAsync>>('sd_bridge_txt2img_async')
        .asFunction<DartTxt2ImgAsync>();

    _abort = _lib
        .lookup<NativeFunction<NativeAbort>>('sd_bridge_abort')
        .asFunction<DartAbort>();

    _free = _lib
        .lookup<NativeFunction<NativeFree>>('sd_bridge_free')
        .asFunction<DartFree>();

    _getSystemInfo = _lib
        .lookup<NativeFunction<NativeGetSystemInfo>>('sd_bridge_get_system_info')
        .asFunction<DartGetSystemInfo>();

    _setLogCallback = _lib
        .lookup<NativeFunction<NativeSetLogCallback>>('sd_bridge_set_log_callback')
        .asFunction<DartSetLogCallback>();
  }

  /// Registers a native log callback to receive live C++ and GGML engine logs.
  void setLogCallback(Pointer<NativeFunction<SdBridgeLogCbNative>> logCb) {
    _setLogCallback(logCb);
  }

  /// Initialize context. Returns null pointer on failure.
  Pointer<Void> init({
    required String modelPath,
    required int nThreads,
    bool vaeTiling = true,
    bool useMetal = true,
  }) {
    final nativePath = modelPath.toNativeUtf8();
    try {
      return _init(nativePath, nThreads, vaeTiling, useMetal);
    } finally {
      calloc.free(nativePath);
    }
  }

  /// Run text-to-image and output PNG file directly to disk.
  int txt2imgToFile({
    required Pointer<Void> ctx,
    required String prompt,
    String? negativePrompt,
    double cfgScale = 7.0,
    int width = 512,
    int height = 512,
    int sampleMethod = 0,
    int sampleSteps = 20,
    int seed = -1,
    required String outputPngPath,
    Pointer<NativeFunction<SdBridgeProgressCbNative>>? progressCb,
  }) {
    final nativePrompt = prompt.toNativeUtf8();
    final nativeNegativePrompt =
        (negativePrompt ?? '').toNativeUtf8();
    final nativeOutputPath = outputPngPath.toNativeUtf8();

    try {
      return _txt2imgToFile(
        ctx,
        nativePrompt,
        nativeNegativePrompt,
        cfgScale,
        width,
        height,
        sampleMethod,
        sampleSteps,
        seed,
        nativeOutputPath,
        progressCb ?? nullptr,
      );
    } finally {
      calloc.free(nativePrompt);
      calloc.free(nativeNegativePrompt);
      calloc.free(nativeOutputPath);
    }
  }

  /// Performs Text-to-Image generation asynchronously in a native background thread.
  /// Yields progress and completion callbacks without blocking the Dart event loop.
  int txt2imgAsync({
    required Pointer<Void> ctx,
    required String prompt,
    String? negativePrompt,
    double cfgScale = 7.0,
    int width = 512,
    int height = 512,
    int sampleMethod = 0,
    int sampleSteps = 20,
    int seed = -1,
    required String outputPngPath,
    required Pointer<NativeFunction<SdBridgeProgressCbNative>> progressCb,
    required Pointer<NativeFunction<SdBridgeCompletionCbNative>> completionCb,
  }) {
    final nativePrompt = prompt.toNativeUtf8();
    final nativeNegativePrompt =
        (negativePrompt ?? '').toNativeUtf8();
    final nativeOutputPath = outputPngPath.toNativeUtf8();

    try {
      return _txt2imgAsync(
        ctx,
        nativePrompt,
        nativeNegativePrompt,
        cfgScale,
        width,
        height,
        sampleMethod,
        sampleSteps,
        seed,
        nativeOutputPath,
        progressCb,
        completionCb,
      );
    } finally {
      calloc.free(nativePrompt);
      calloc.free(nativeNegativePrompt);
      calloc.free(nativeOutputPath);
    }
  }

  /// Aborts active generation.
  void abort(Pointer<Void> ctx) => _abort(ctx);

  /// Frees context and releases weights from RAM.
  void freeContext(Pointer<Void> ctx) => _free(ctx);

  /// Hardware and runtime info.
  String getSystemInfo() {
    final ptr = _getSystemInfo();
    if (ptr == nullptr) return 'Unknown';
    try {
      final info = ptr.toSafeDartString();
      return info.isNotEmpty ? info : 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }
}

