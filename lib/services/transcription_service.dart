import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class TranscriptionService {
  static const MethodChannel _channel = MethodChannel('com.whisperflow/transcribe');

  /// Attempts to transcribe the recorded audio file using the native device transcription.
  /// Currently only implemented on iOS using SFSpeechRecognizer.
  /// Returns null if not supported, fails, or is on another platform.
  static Future<String?> transcribeAudio(String filePath) async {
    if (!Platform.isIOS) {
      return null;
    }

    try {
      // Guard against the native side hanging indefinitely on very short/silent
      // clips (e.g. stopping a recording almost immediately via the side button).
      final String? transcript = await _channel.invokeMethod<String>(
        'transcribeFile',
        {'filePath': filePath},
      ).timeout(const Duration(seconds: 15));
      if (transcript != null && transcript.trim().isNotEmpty) {
        return transcript.trim();
      }
      return null;
    } on TimeoutException catch (e) {
      print("Native iOS transcription timed out: $e");
      return null;
    } on PlatformException catch (e) {
      print("Native iOS transcription failed: ${e.message} (code: ${e.code})");
      return null;
    } catch (e) {
      print("Unexpected error calling native transcription: $e");
      return null;
    }
  }
}
