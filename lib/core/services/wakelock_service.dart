import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Reference-counted Wakelock manager.
/// Ensures the CPU and display remain active during heavy background operations
/// (e.g. downloading 2.1GB GGUF model or running 60s diffusion inference passes).
class WakelockService {
  WakelockService._();
  static final WakelockService instance = WakelockService._();

  final Set<String> _activeHolders = <String>{};

  /// Acquires a wakelock for a specific tag (e.g. 'download', 'inference').
  Future<void> acquire(String tag) async {
    final wasEmpty = _activeHolders.isEmpty;
    _activeHolders.add(tag);

    if (wasEmpty) {
      debugPrint('[WakelockService] Enabling hardware wakelock for tag: $tag');
      try {
        await WakelockPlus.enable();
      } catch (e) {
        debugPrint('[WakelockService] Failed to enable wakelock: $e');
      }
    } else {
      debugPrint('[WakelockService] Tag added ($tag). Active tags: $_activeHolders');
    }
  }

  /// Releases a wakelock for a specific tag.
  Future<void> release(String tag) async {
    final removed = _activeHolders.remove(tag);
    if (!removed) return;

    debugPrint('[WakelockService] Tag released ($tag). Remaining: $_activeHolders');

    if (_activeHolders.isEmpty) {
      debugPrint('[WakelockService] Releasing hardware wakelock completely.');
      try {
        await WakelockPlus.disable();
      } catch (e) {
        debugPrint('[WakelockService] Failed to disable wakelock: $e');
      }
    }
  }

  /// Forces all active locks to release (e.g., during app shutdown or error recovery).
  Future<void> forceReleaseAll() async {
    _activeHolders.clear();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  bool get isLocked => _activeHolders.isNotEmpty;
  Set<String> get activeTags => Set.unmodifiable(_activeHolders);
}

