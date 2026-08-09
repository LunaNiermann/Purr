import 'dart:async';

import 'package:flutter/services.dart';

/// Thin wrapper over the twokeys/platform channel (Android; falls back to
/// plain clipboard elsewhere so the app still runs on other targets).
class PlatformServices {
  static const _channel = MethodChannel('twokeys/platform');

  static Timer? _clearTimer;

  /// Writes the six bare digits with the sensitive flag and schedules a
  /// best-effort self-clear after 45 s.
  static Future<void> copyCode(String code) async {
    try {
      await _channel.invokeMethod('copySensitive', {'text': code});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: code));
    }
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 45), () async {
      try {
        await _channel.invokeMethod('clearClipboardIfCode', {'text': code});
      } on MissingPluginException {
        // No safe way to check current clip cross-platform; leave it.
      }
    });
  }
}
