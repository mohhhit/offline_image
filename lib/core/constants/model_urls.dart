/// Model download URLs and filesystem identifiers.
class ModelUrls {
  ModelUrls._();

  /// User-provided HuggingFace web page URL
  static const String huggingFaceWebUrl =
      'https://huggingface.co/gpustack/stable-diffusion-v2-1-GGUF/blob/main/stable-diffusion-v2-1-Q4_0.gguf';

  /// Direct raw binary endpoint supporting HTTP 206 Partial Content Range requests
  static const String modelDownloadRawUrl =
      'https://huggingface.co/gpustack/stable-diffusion-v2-1-GGUF/resolve/main/stable-diffusion-v2-1-Q4_0.gguf?download=true';

  /// Standard filename for the quantized model
  static const String modelFileName = 'stable-diffusion-v2-1-Q4_0.gguf';

  /// Exact file size in bytes (~2.185 GB) from HuggingFace LFS
  static const int expectedModelSizeBytes = 2185459424;

  /// Minimum required storage buffer before allowing download (5.0 GB)
  static const int minRequiredStorageBytes = 5 * 1024 * 1024 * 1024;
}

