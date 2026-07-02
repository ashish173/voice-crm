import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/voice_note.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import 'package:whisperflow_replica/main.dart' as app_globals;

class BackgroundProcessor {
  /// Set of note IDs currently being processed in memory.
  static final Set<String> _activeJobs = {};

  static Set<String> get activeJobs => _activeJobs;

  /// Starts background processing for a voice note.
  static void startProcessing(VoiceNote placeholderNote) {
    if (_activeJobs.contains(placeholderNote.id)) {
      debugPrint("BackgroundProcessor: Job for ${placeholderNote.id} already active, ignoring");
      return; 
    }
    _activeJobs.add(placeholderNote.id);
    _runTranscription(placeholderNote);
  }

  /// Runs the transcription and AI processing asynchronously.
  static Future<void> _runTranscription(VoiceNote placeholderNote) async {
    try {
      debugPrint("BackgroundProcessor: Starting AI processing for note ${placeholderNote.id}");
      
      final VoiceNote completedNote = await AIService.processAudioNote(
        placeholderNote.filePath,
        placeholderNote.durationMs,
      ).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException("AI processing timed out after 90 seconds"),
      );

      final updatedNote = completedNote.copyWith(
        id: placeholderNote.id,
        isProcessing: false,
        hasFailed: false,
      );

      await StorageService.saveVoiceNote(updatedNote);
      debugPrint("BackgroundProcessor: Successfully processed note ${placeholderNote.id}");
    } catch (e) {
      debugPrint("BackgroundProcessor: Error processing note ${placeholderNote.id}: $e");
      
      final failedNote = placeholderNote.copyWith(
        title: "Transcription Failed",
        isProcessing: false,
        hasFailed: true,
        transcript: "Failed to process: $e",
      );
      
      await StorageService.saveVoiceNote(failedNote);
    } finally {
      _activeJobs.remove(placeholderNote.id);
      
      // Notify the UI to refresh
      if (app_globals.onVoiceNotesChanged != null) {
        app_globals.onVoiceNotesChanged!();
      }
    }
  }
}
