import 'dart:isolate';

/// Commands sent from the UI isolate to the worker isolate.
sealed class SdCommand {
  const SdCommand();
}

class SdInitCommand extends SdCommand {
  final String modelPath;
  final int nThreads;
  final bool vaeTiling;

  const SdInitCommand({
    required this.modelPath,
    this.nThreads = 4,
    this.vaeTiling = true,
  });
}

class SdGenerateCommand extends SdCommand {
  final String prompt;
  final String? negativePrompt;
  final double cfgScale;
  final int width;
  final int height;
  final int sampleMethod;
  final int sampleSteps;
  final int seed;
  final String outputPngPath;

  const SdGenerateCommand({
    required this.prompt,
    this.negativePrompt,
    this.cfgScale = 7.0,
    this.width = 512,
    this.height = 512,
    this.sampleMethod = -1,
    this.sampleSteps = 20,
    this.seed = -1,
    required this.outputPngPath,
  });
}

class SdAbortCommand extends SdCommand {
  const SdAbortCommand();
}

class SdDisposeCommand extends SdCommand {
  const SdDisposeCommand();
}

/// Messages sent from the worker isolate back to the UI isolate.
sealed class SdResponse {
  const SdResponse();
}

class SdWorkerReadyResponse extends SdResponse {
  final SendPort sendPort;
  const SdWorkerReadyResponse(this.sendPort);
}

class SdInitResponse extends SdResponse {
  final bool success;
  final String? systemInfo;
  final String? error;

  const SdInitResponse({
    required this.success,
    this.systemInfo,
    this.error,
  });
}

class SdLogResponse extends SdResponse {
  final String text;
  final String? stage;
  final DateTime timestamp;

  SdLogResponse({
    required this.text,
    this.stage,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class SdStageResponse extends SdResponse {
  final String stage;
  final String message;

  const SdStageResponse({
    required this.stage,
    required this.message,
  });
}

class SdProgressResponse extends SdResponse {
  final int step;
  final int totalSteps;
  final double elapsedSeconds;
  final double? etaSeconds;
  final double? itPerSec;

  const SdProgressResponse({
    required this.step,
    required this.totalSteps,
    required this.elapsedSeconds,
    this.etaSeconds,
    this.itPerSec,
  });

  double get fraction => totalSteps > 0 ? (step / totalSteps).clamp(0.0, 1.0) : 0.0;
  int get percentage => (fraction * 100).toInt();

  String get formattedSpeed {
    if (itPerSec != null && itPerSec! > 0) {
      if (itPerSec! >= 1.0) {
        return '${itPerSec!.toStringAsFixed(1)} it/s';
      } else {
        return '${(1.0 / itPerSec!).toStringAsFixed(1)}s/it';
      }
    }
    return '';
  }

  String get formattedEta {
    if (etaSeconds == null || etaSeconds! <= 0) return '';
    final mins = (etaSeconds! / 60).floor();
    final secs = (etaSeconds! % 60).round();
    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
  }
}

class SdSuccessResponse extends SdResponse {
  final String outputPngPath;
  final double durationSeconds;

  const SdSuccessResponse({
    required this.outputPngPath,
    required this.durationSeconds,
  });
}

class SdErrorResponse extends SdResponse {
  final int errorCode;
  final String errorMessage;

  const SdErrorResponse({
    required this.errorCode,
    required this.errorMessage,
  });
}

