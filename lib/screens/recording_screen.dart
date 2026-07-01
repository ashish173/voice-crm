import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:record/record.dart';
import '../main.dart' as app_globals;
import '../models/voice_note.dart';
import '../services/ai_service.dart';
import '../services/recording_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class RecordingScreen extends StatefulWidget {
  final bool autoStart;
  const RecordingScreen({Key? key, this.autoStart = true}) : super(key: key);

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> with TickerProviderStateMixin {
  final RecordingService _recordingService = RecordingService();
  
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isPaused = false;
  
  int _secondsElapsed = 0;
  Timer? _timer;
  
  // Keep track of the last e.g. 25 amplitude values to draw a rolling wave
  final List<double> _amplitudes = List.generate(25, (_) => 0.05);
  StreamSubscription<Amplitude>? _ampSubscription;

  late AnimationController _orbController;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    if (widget.autoStart) {
      _startRecording();
    }
  }

  @override
  void dispose() {
    // Unregister from global state when screen leaves
    app_globals.isRecordingActive = false;
    app_globals.onStopRecordingRequested = null;
    _timer?.cancel();
    _ampSubscription?.cancel();
    _orbController.dispose();
    _recordingService.dispose();
    super.dispose();
  }

  // Request mic permission and start recording
  void _startRecording() async {
    try {
      final allowed = await _recordingService.hasPermission();
      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission is required to record voice notes.")),
        );
        Navigator.pop(context);
        return;
      }

      await _recordingService.startRecording();
      _startTimer();
      _startAmplitudeTracking();

      // Register with global state so the side-button deep link can stop us
      app_globals.isRecordingActive = true;
      app_globals.onStopRecordingRequested = _stopAndSaveNote;

      setState(() {
        _isInitialized = true;
        _isPaused = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error starting recording: $e")),
      );
      Navigator.pop(context);
    }
  }

  // Duration Timer
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
  }

  // Subscribe to real-time volume level (dB) and map to a scale of 0.0 to 1.0
  void _startAmplitudeTracking() {
    _ampSubscription?.cancel();
    _ampSubscription = _recordingService.amplitudeStream.listen((amp) {
      setState(() {
        // Map dB (typically -160 to 0) to 0.0 to 1.0 range
        // -160 is silence, 0 is max volume
        double normalized = (amp.current + 160.0) / 160.0;
        
        // Clamp it and introduce a slight noise threshold
        if (normalized < 0.0) normalized = 0.05;
        if (normalized > 1.0) normalized = 1.0;
        if (normalized < 0.15) normalized = 0.05; // Noise gate
        
        // Shift values to create rolling effect
        _amplitudes.removeAt(0);
        _amplitudes.add(normalized);
      });
    });
  }

  // Pause
  void _pauseRecording() async {
    await _recordingService.pauseRecording();
    _pauseTimer();
    _orbController.stop();
    setState(() {
      _isPaused = true;
    });
  }

  // Resume
  void _resumeRecording() async {
    await _recordingService.resumeRecording();
    _startTimer();
    _orbController.repeat(reverse: true);
    setState(() {
      _isPaused = false;
    });
  }

  // Cancel recording (deletes progress)
  void _cancelRecording() async {
    _timer?.cancel();
    _ampSubscription?.cancel();
    await _recordingService.cancelRecording();
    Navigator.pop(context);
  }

  // Save
  void _stopAndSaveNote() async {
    _timer?.cancel();
    _ampSubscription?.cancel();
    _orbController.stop();

    setState(() {
      _isProcessing = true;
    });

    try {
      final recordResult = await _recordingService.stopRecording();
      if (recordResult != null) {
        final String path = recordResult['filePath'];
        final int durationMs = recordResult['durationMs'];

        // Process audio with AI
        final VoiceNote note = await AIService.processAudioNote(path, durationMs);
        
        // Save note metadata locally
        await StorageService.saveVoiceNote(note);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Flow processed: ${note.title}"),
              backgroundColor: AppTheme.accentViolet,
            ),
          );
          Navigator.pop(context, true); // Return success
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error processing note: $e")),
        );
      }
    }
  }

  // Format MM:SS
  String _formatTime(int totalSecs) {
    final int minutes = totalSecs ~/ 60;
    final int seconds = totalSecs % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _cancelRecording();
        return true;
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: SafeArea(
            child: _isProcessing 
                ? _buildProcessingState() 
                : _buildRecordingState(),
          ),
        ),
      ),
    );
  }

  // 1. AI Processing Loading Overlay
  Widget _buildProcessingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SpinKitDoubleBounce(
              color: AppTheme.accentMagenta,
              size: 80.0,
            ),
            const SizedBox(height: 40),
            Text(
              "Flow AI Processing...",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Polishing your transcription, generating action items, and extracting key insights...",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: AppTheme.glassDecoration(borderRadius: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt, color: AppTheme.accentCyan, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "Powered by Gemini 1.5 Flash",
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.accentCyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. Active Recording State Screen UI
  Widget _buildRecordingState() {
    return Column(
      children: [
        // Screen Header / Close button
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _cancelRecording,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: AppTheme.glassDecoration(borderRadius: 12),
                  child: const Icon(Icons.close, color: AppTheme.textPrimary, size: 20),
                ),
              ),
              Text(
                _isPaused ? "Recording Paused" : "Listening...",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(width: 40), // Spacer for centering title
            ],
          ),
        ),

        const Spacer(),

        // Pulsating Gradient Orb
        AnimatedBuilder(
          animation: _orbController,
          builder: (context, child) {
            // Orb scaling linked to pulse animation and current amplitude level
            final currentAmp = _amplitudes.last;
            final double scale = 1.0 + (_orbController.value * 0.08) + (currentAmp * 0.12);
            
            return Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Glow Orb
                  Container(
                    width: 200 * scale,
                    height: 200 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.accentViolet.withOpacity(0.0),
                          AppTheme.accentMagenta.withOpacity(_isPaused ? 0.05 : 0.25 * (1.0 - _orbController.value)),
                        ],
                      ),
                    ),
                  ),
                  // Border Glowing Ring
                  Container(
                    width: 170 * (scale - 0.02),
                    height: 170 * (scale - 0.02),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.accentMagenta.withOpacity(_isPaused ? 0.1 : 0.3 * scale),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Core Glassmorphic Orb
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0x33FFFFFF), Color(0x08FFFFFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: AppTheme.borderLight, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentViolet.withOpacity(0.3),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _isPaused ? Icons.pause_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 40),

        // Live Audio Wave Visualizer (Bars)
        if (!_isPaused && _isInitialized)
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _amplitudes.map((ampHeight) {
                // Height of each bar, with a minimum representation
                final double height = (ampHeight * 50).clamp(4.0, 50.0);
                
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 3.5,
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [AppTheme.accentViolet, AppTheme.accentCyan],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                );
              }).toList(),
            ),
          )
        else
          const SizedBox(height: 60, child: Center(child: Text("Recording paused"))),

        const SizedBox(height: 20),

        // Elapsed Time Timer
        Text(
          _formatTime(_secondsElapsed),
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w300,
            color: AppTheme.textPrimary,
            letterSpacing: 2.0,
          ),
        ),

        const Spacer(),

        // Recording Control Buttons
        Padding(
          padding: const EdgeInsets.only(bottom: 40.0, left: 30.0, right: 30.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 1. Cancel / Trash Button
              GestureDetector(
                onTap: _cancelRecording,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: AppTheme.glassDecoration(borderRadius: 28),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
                ),
              ),

              // 2. Main Stop and Save button
              GestureDetector(
                onTap: _isInitialized ? _stopAndSaveNote : null,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentViolet,
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.stop_rounded, color: Colors.white, size: 36),
                ),
              ),

              // 3. Pause / Resume Button
              GestureDetector(
                onTap: !_isInitialized 
                    ? null 
                    : _isPaused 
                        ? _resumeRecording 
                        : _pauseRecording,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: AppTheme.glassDecoration(borderRadius: 28),
                  child: Icon(
                    _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: AppTheme.accentCyan,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
