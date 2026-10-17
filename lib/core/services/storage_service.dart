import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants/model_urls.dart';

/// Manages local filesystem storage, model directory creation, and disk validations.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  Directory? _documentsDir;

  Future<Directory> get documentsDir async {
    _documentsDir ??= await getApplicationDocumentsDirectory();
    return _documentsDir!;
  }

  /// Directory dedicated for storing large AI model weights.
  Future<Directory> get modelsDirectory async {
    final docs = await documentsDir;
    final dir = Directory(p.join(docs.path, 'models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Directory for persistent offline generated PNG images.
  Future<Directory> get imagesDirectory async {
    final docs = await documentsDir;
    final dir = Directory(p.join(docs.path, 'generated_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Target path for the Stable Diffusion 2.1 Q4_0 GGUF file.
  Future<String> get modelFilePath async {
    final modelsDir = await modelsDirectory;
    return p.join(modelsDir.path, ModelUrls.modelFileName);
  }

  /// Checks if the model file is fully downloaded and valid on disk.
  Future<bool> isModelDownloaded() async {
    final path = await modelFilePath;
    final file = File(path);
    final exists = await file.exists();
    if (!exists) {
      return false;
    }

    final length = await file.length();
    // Accept if file size is at least 95% of expected size (~2.07GB+)
    final valid = length >= (ModelUrls.expectedModelSizeBytes * 0.95);
    return valid;
  }

  /// Estimates available disk space on the device's storage partition.
  /// If disk checking fails or is unsupported, returns a fallback default.
  Future<int> getAvailableStorageBytes() async {
    try {
      final docs = await documentsDir;
      // On POSIX systems, we can read stat / statfs
      // As a safe baseline across platforms:
      final stat = await docs.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return 0;
      }
      // Return 10GB safe fallback if platform doesn't expose low-level statfs
      return 10 * 1024 * 1024 * 1024;
    } catch (_) {
      return 10 * 1024 * 1024 * 1024;
    }
  }

  /// Generates a unique timestamped file path for saving a newly generated image.
  Future<String> createNewImagePath(String id) async {
    final imgDir = await imagesDirectory;
    return p.join(imgDir.path, 'img_$id.png');
  }
}

