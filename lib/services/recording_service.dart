import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

class RecordingService {
  // Singleton pattern to ensure recording lifecycle persists across screens
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentFilePath;
  DateTime? _startTime;

  bool get isRecording => _isRecording;
  String? get currentFilePath => _currentFilePath;

  // Check and request microphone permission
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  // Start audio recording
  Future<void> startRecording() async {
    if (!await hasPermission()) {
      throw Exception("Microphone permission not granted");
    }

    // Generate unique file path in temporary or document directory
    final directory = await getApplicationDocumentsDirectory();
    final String filename = 'voice_note_${const Uuid().v4()}.m4a';
    final String filePath = '${directory.path}/$filename';

    _currentFilePath = filePath;
    _startTime = DateTime.now();

    // Start recording
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc, // Standard lightweight AAC/M4A format
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );

    _isRecording = true;
  }

  // Pause recording
  Future<void> pauseRecording() async {
    await _recorder.pause();
    _isRecording = false;
  }

  // Resume recording
  Future<void> resumeRecording() async {
    await _recorder.resume();
    _isRecording = true;
  }

  // Stop recording and return details: path and duration
  Future<Map<String, dynamic>?> stopRecording() async {
    if (!_isRecording && _startTime == null) return null;

    final String? path = await _recorder.stop();
    final DateTime endTime = DateTime.now();
    final int durationMs = _startTime != null 
        ? endTime.difference(_startTime!).inMilliseconds 
        : 0;

    _isRecording = false;
    _startTime = null;
    _currentFilePath = null;

    if (path == null) return null;

    return {
      'filePath': path,
      'durationMs': durationMs,
    };
  }

  // Get current amplitude for the visualizer
  Stream<Amplitude> get amplitudeStream {
    return _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));
  }

  // Cancel recording and delete the temporary file
  Future<void> cancelRecording() async {
    final String? path = await _recorder.stop();
    _isRecording = false;
    _startTime = null;
    _currentFilePath = null;

    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print("Error deleting cancelled file: $e");
      }
    }
  }

  // Clean up
  void dispose() {
    _recorder.dispose();
  }
}
