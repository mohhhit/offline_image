import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// Extension providing robust string decoding from native C strings (`Pointer<Utf8>`).
///
/// Standard [Utf8Pointer.toDartString] uses strict [utf8.decode] without `allowMalformed: true`.
/// If a C/C++ engine (like ggml or stable-diffusion.cpp) outputs non-standard characters,
/// progress spinners, terminal escapes, or non-UTF-8 bytes, [Utf8Pointer.toDartString]
/// throws a fatal [FormatException] (e.g. "Unexpected extension byte (at offset 0)").
///
/// This extension prevents VM/isolate crashes by:
/// 1. Handling `nullptr` gracefully (returns empty string `''`).
/// 2. Scanning length up to a safe upper bound [maxLength] to prevent runaway memory reads.
/// 3. Using [utf8.decode] with `allowMalformed: true` (replaces invalid bytes with U+FFFD).
/// 4. Falling back to [latin1.decode] if UTF-8 decoding encounters any unforeseen error.
/// 5. Returning empty string if decoding cannot succeed, never letting an exception escape.
extension SafeUtf8Pointer on Pointer<Utf8> {
  String toSafeDartString({int maxLength = 131072}) {
    if (this == nullptr) return '';

    try {
      final codeUnits = cast<Uint8>();
      var len = 0;
      while (len < maxLength && codeUnits[len] != 0) {
        len++;
      }
      if (len == 0) return '';

      return utf8.decode(codeUnits.asTypedList(len), allowMalformed: true);
    } catch (_) {
      try {
        final codeUnits = cast<Uint8>();
        var len = 0;
        while (len < maxLength && codeUnits[len] != 0) {
          len++;
        }
        if (len == 0) return '';
        return latin1.decode(codeUnits.asTypedList(len));
      } catch (_) {
        return '';
      }
    }
  }
}
