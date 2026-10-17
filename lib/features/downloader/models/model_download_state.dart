enum DownloadStatus {
  notStarted,
  checkingStorage,
  downloading,
  paused,
  completed,
  failed,
}

class ModelDownloadState {
  final DownloadStatus status;
  final double progress; // 0.0 to 1.0
  final double networkSpeedMBs; // MB/s
  final Duration? timeRemaining;
  final int bytesDownloaded;
  final int totalBytes;
  final String? errorMessage;
  final String? localFilePath;

  const ModelDownloadState({
    required this.status,
    this.progress = 0.0,
    this.networkSpeedMBs = 0.0,
    this.timeRemaining,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.localFilePath,
  });

  factory ModelDownloadState.initial() => const ModelDownloadState(
        status: DownloadStatus.notStarted,
      );

  factory ModelDownloadState.completed(String path) => ModelDownloadState(
        status: DownloadStatus.completed,
        progress: 1.0,
        localFilePath: path,
      );

  factory ModelDownloadState.failed(String error) => ModelDownloadState(
        status: DownloadStatus.failed,
        errorMessage: error,
      );

  ModelDownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    double? networkSpeedMBs,
    Duration? timeRemaining,
    int? bytesDownloaded,
    int? totalBytes,
    String? errorMessage,
    String? localFilePath,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      networkSpeedMBs: networkSpeedMBs ?? this.networkSpeedMBs,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      localFilePath: localFilePath ?? this.localFilePath,
    );
  }

  bool get isDone => status == DownloadStatus.completed;
  bool get isDownloading => status == DownloadStatus.downloading;
  bool get hasFailed => status == DownloadStatus.failed;

  String get formattedProgress => '${(progress * 100).toStringAsFixed(1)}%';

  String get formattedDownloadedSize {
    final mb = bytesDownloaded / (1024 * 1024);
    final totalMb = totalBytes / (1024 * 1024);
    if (totalBytes > 0) {
      return '${mb.toStringAsFixed(1)} MB / ${totalMb.toStringAsFixed(1)} MB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}

