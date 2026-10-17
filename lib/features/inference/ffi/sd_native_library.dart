import 'dart:ffi';
import 'dart:io';

/// Platform-agnostic loader for the native shared library.
class SdNativeLibrary {
  static DynamicLibrary load() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libstable_diffusion_bridge.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      // On iOS and macOS, native symbols statically or dynamically linked in the app image
      // are resolved via DynamicLibrary.process().
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('stable_diffusion_bridge.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libstable_diffusion_bridge.so');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

