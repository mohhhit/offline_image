enum MessageStatus {
  pending,
  generating,
  completed,
  failed,
}

class ChatMessage {
  final String id;
  final String chatId;
  final String prompt;
  final String? negativePrompt;
  final String? imagePath;
  final MessageStatus status;
  final int stepProgress;
  final int totalSteps;
  final int seed;
  final double cfgScale;
  final double? durationSeconds;
  final String? errorMessage;
  final DateTime createdAt;

  // Real-time terminal logs and pipeline stage indicators
  final String? statusMessage;
  final String? stage; // 'loading_weights', 'prompt_encoding', 'denoising', 'decoding_vae', 'saving_image'
  final List<String> logs;
  final double? etaSeconds;
  final double? itPerSec;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.prompt,
    this.negativePrompt,
    this.imagePath,
    this.status = MessageStatus.pending,
    this.stepProgress = 0,
    this.totalSteps = 20,
    this.seed = -1,
    this.cfgScale = 7.0,
    this.durationSeconds,
    this.errorMessage,
    required this.createdAt,
    this.statusMessage,
    this.stage,
    this.logs = const [],
    this.etaSeconds,
    this.itPerSec,
  });

  bool get isGenerating => status == MessageStatus.generating;
  bool get isCompleted => status == MessageStatus.completed;
  bool get isFailed => status == MessageStatus.failed;

  double get progressFraction =>
      totalSteps > 0 ? (stepProgress / totalSteps).clamp(0.0, 1.0) : 0.0;

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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'prompt': prompt,
      'negative_prompt': negativePrompt,
      'image_path': imagePath,
      'status': status.name,
      'step_progress': stepProgress,
      'total_steps': totalSteps,
      'seed': seed,
      'cfg_scale': cfgScale,
      'duration_seconds': durationSeconds,
      'error_message': errorMessage,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      prompt: map['prompt'] as String,
      negativePrompt: map['negative_prompt'] as String?,
      imagePath: map['image_path'] as String?,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.pending,
      ),
      stepProgress: map['step_progress'] as int? ?? 0,
      totalSteps: map['total_steps'] as int? ?? 20,
      seed: map['seed'] as int? ?? -1,
      cfgScale: (map['cfg_scale'] as num?)?.toDouble() ?? 7.0,
      durationSeconds: (map['duration_seconds'] as num?)?.toDouble(),
      errorMessage: map['error_message'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      statusMessage: null,
      stage: null,
      logs: const [],
      etaSeconds: null,
      itPerSec: null,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? prompt,
    String? negativePrompt,
    String? imagePath,
    MessageStatus? status,
    int? stepProgress,
    int? totalSteps,
    int? seed,
    double? cfgScale,
    double? durationSeconds,
    String? errorMessage,
    DateTime? createdAt,
    String? statusMessage,
    String? stage,
    List<String>? logs,
    double? etaSeconds,
    double? itPerSec,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      imagePath: imagePath ?? this.imagePath,
      status: status ?? this.status,
      stepProgress: stepProgress ?? this.stepProgress,
      totalSteps: totalSteps ?? this.totalSteps,
      seed: seed ?? this.seed,
      cfgScale: cfgScale ?? this.cfgScale,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      statusMessage: statusMessage ?? this.statusMessage,
      stage: stage ?? this.stage,
      logs: logs ?? this.logs,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      itPerSec: itPerSec ?? this.itPerSec,
    );
  }
}
