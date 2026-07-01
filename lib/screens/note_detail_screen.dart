import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/voice_note.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class NoteDetailScreen extends StatefulWidget {
  final VoiceNote note;
  const NoteDetailScreen({Key? key, required this.note}) : super(key: key);

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> with SingleTickerProviderStateMixin {
  late VoiceNote _note;
  late TabController _tabController;

  // Audio Playback
  final AudioPlayer _audioPlayer = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackRate = 1.0;

  bool _isPlaying = false;
  bool _isEditingTranscript = false;
  late TextEditingController _transcriptEditController;
  
  // Rewriter state
  bool _isRewriting = false;
  String _selectedRewriteTemplate = "Professional Email";
  final TextEditingController _customRewriteController = TextEditingController();
  String? _currentRewriteResult;

  // Subscriptions
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _tabController = TabController(length: 4, vsync: this);
    _transcriptEditController = TextEditingController(text: _note.transcript);

    _initAudioPlayer();
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    
    _audioPlayer.dispose();
    _tabController.dispose();
    _transcriptEditController.dispose();
    _customRewriteController.dispose();
    super.dispose();
  }

  // Setup player listeners
  void _initAudioPlayer() async {
    try {
      // Set audio context to play through speaker and mix with other audio
      await _audioPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );

      final fileExists = await File(_note.filePath).exists();
      print("NoteDetailScreen: Audio file exists: $fileExists at: ${_note.filePath}");
      if (!fileExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Warning: Audio file not found at local path. Playback may fail."),
            backgroundColor: Colors.amber[700],
          ),
        );
      }

      await _audioPlayer.setSource(DeviceFileSource(_note.filePath));
      
      _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _playerState = state;
            _isPlaying = state == PlayerState.playing;
          });
        }
      });

      _completeSub = _audioPlayer.onPlayerComplete.listen((event) {
        if (mounted) {
          setState(() {
            _position = Duration.zero;
            _isPlaying = false;
          });
        }
      });
    } catch (e) {
      print("Error initializing audio player: $e");
    }
  }

  // Play / Pause toggle
  void _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(DeviceFileSource(_note.filePath));
      }
    } catch (e) {
      print("Error during playback: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Playback error: $e")),
      );
    }
  }

  // Cycle speed rate
  void _cyclePlaybackRate() async {
    double nextRate = 1.0;
    if (_playbackRate == 1.0) {
      nextRate = 1.25;
    } else if (_playbackRate == 1.25) {
      nextRate = 1.5;
    } else if (_playbackRate == 1.5) {
      nextRate = 2.0;
    } else if (_playbackRate == 2.0) {
      nextRate = 0.8;
    } else {
      nextRate = 1.0;
    }

    await _audioPlayer.setPlaybackRate(nextRate);
    setState(() {
      _playbackRate = nextRate;
    });
  }

  // Save the updated note model in storage
  Future<void> _updateNote(VoiceNote updatedNote) async {
    await StorageService.saveVoiceNote(updatedNote);
    setState(() {
      _note = updatedNote;
    });
  }

  // Toggle action item checked state
  void _toggleActionItem(int index, bool? val) {
    final List<String> updatedActions = List.from(_note.aiActions);
    final String currentItem = updatedActions[index];
    
    // Toggle checkmark visual indicator in bullet string
    if (val == true) {
      if (!currentItem.startsWith("[x] ")) {
        updatedActions[index] = "[x] " + currentItem.replaceAll("[ ] ", "");
      }
    } else {
      updatedActions[index] = "[ ] " + currentItem.replaceAll("[x] ", "");
    }

    _updateNote(_note.copyWith(aiActions: updatedActions));
  }

  // Save transcript edits
  void _saveTranscriptEdit() {
    final updatedText = _transcriptEditController.text.trim();
    if (updatedText.isNotEmpty) {
      _updateNote(_note.copyWith(transcript: updatedText));
    }
    setState(() {
      _isEditingTranscript = false;
    });
  }

  // Copy text to clipboard
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$label copied to clipboard")),
    );
  }

  // Trigger Gemini to rewrite transcription using templates or custom prompt
  void _triggerRewrite() async {
    final String prompt = _selectedRewriteTemplate == "Custom Instruction"
        ? _customRewriteController.text.trim()
        : _selectedRewriteTemplate;

    if (_selectedRewriteTemplate == "Custom Instruction" && prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter custom instructions for rewriting.")),
      );
      return;
    }

    setState(() {
      _isRewriting = true;
      _currentRewriteResult = null;
    });

    try {
      final rewritten = await AIService.rewriteTranscript(_note.transcript, prompt);
      
      // Update note local model and add to rewrites map
      final Map<String, String> updatedRewrites = Map.from(_note.aiRewrite);
      final String saveKey = _selectedRewriteTemplate == "Custom Instruction" ? "Custom Draft" : _selectedRewriteTemplate;
      updatedRewrites[saveKey] = rewritten;
      
      await _updateNote(_note.copyWith(aiRewrite: updatedRewrites));
      
      setState(() {
        _currentRewriteResult = rewritten;
        _isRewriting = false;
      });
    } catch (e) {
      setState(() => _isRewriting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Rewrite failed: $e")),
      );
    }
  }

  // Helper formatting for durations
  String _printDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_note.title),
        actions: [
          // Info/Share dropdown menu
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'share') {
                _copyToClipboard(_note.transcript, "Transcript");
              }
            },
            color: AppTheme.bgMidnight,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, size: 18),
                    SizedBox(width: 8),
                    Text("Copy Transcript"),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 1. Audio Player Widget Card
              _buildAudioPlayerCard(),

              const SizedBox(height: 16),

              // 2. Tab Bar Selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  height: 48,
                  decoration: AppTheme.glassDecoration(borderRadius: 24),
                  padding: const EdgeInsets.all(4),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: AppTheme.textSecondary,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    tabs: const [
                      Tab(text: "Transcript"),
                      Tab(text: "Summary"),
                      Tab(text: "Actions"),
                      Tab(text: "Rewrite"),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 3. Tab contents
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Container(
                    decoration: AppTheme.glassDecoration(borderRadius: 20),
                    padding: const EdgeInsets.all(18),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTranscriptTab(),
                        _buildSummaryTab(),
                        _buildActionsTab(),
                        _buildRewriteTab(),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // Audio Playback Section Card
  Widget _buildAudioPlayerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.glassDecoration(borderRadius: 20),
        child: Column(
          children: [
            // Playback controls (Play, Pause, Progress, Rate)
            Row(
              children: [
                // Play / Pause Button
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Elapsed Time / Duration
                Expanded(
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          activeTrackColor: AppTheme.accentMagenta,
                          inactiveTrackColor: AppTheme.borderLight,
                          thumbColor: AppTheme.accentMagenta,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _position.inMilliseconds.toDouble(),
                          min: 0,
                          max: _duration.inMilliseconds.toDouble() > 0 
                              ? _duration.inMilliseconds.toDouble() 
                              : 1.0,
                          onChanged: (val) async {
                            await _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _printDuration(_position),
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                            Text(
                              _printDuration(_duration),
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Playback speed rate toggler
                GestureDetector(
                  onTap: _cyclePlaybackRate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.bgObsidian.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    child: Text(
                      "${_playbackRate}x",
                      style: const TextStyle(
                        color: AppTheme.accentCyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // TAB 1: Transcript Viewer & Editor
  Widget _buildTranscriptTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Full Transcript",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.accentMagenta),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (_isEditingTranscript) {
                      _saveTranscriptEdit();
                    } else {
                      setState(() {
                        _transcriptEditController.text = _note.transcript;
                        _isEditingTranscript = true;
                      });
                    }
                  },
                  child: Icon(
                    _isEditingTranscript ? Icons.check_circle_outline_rounded : Icons.edit_note_rounded,
                    color: AppTheme.accentCyan,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () => _copyToClipboard(_note.transcript, "Transcript"),
                  child: const Icon(
                    Icons.copy_rounded,
                    color: AppTheme.textSecondary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
        const Divider(color: AppTheme.borderLight, height: 24),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: _isEditingTranscript
                ? TextField(
                    controller: _transcriptEditController,
                    maxLines: null,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, height: 1.5),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                : Text(
                    _note.transcript,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // TAB 2: AI Takeaways Summary
  Widget _buildSummaryTab() {
    if (_note.aiSummary.isEmpty) {
      return const Center(child: Text("No AI Summary available for this note."));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "AI Key Insights",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.accentMagenta),
        ),
        const Divider(color: AppTheme.borderLight, height: 24),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _note.aiSummary.length,
            itemBuilder: (context, index) {
              final takeaway = _note.aiSummary[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Icon(Icons.blur_on_rounded, color: AppTheme.accentCyan, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        takeaway,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // TAB 3: Action Items Checklist
  Widget _buildActionsTab() {
    if (_note.aiActions.isEmpty) {
      return const Center(child: Text("No actionable items found in this voice note."));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Action Items",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.accentMagenta),
        ),
        const Divider(color: AppTheme.borderLight, height: 24),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _note.aiActions.length,
            itemBuilder: (context, index) {
              final actionStr = _note.aiActions[index];
              
              // Determine if action is checked by parsing prefix
              bool isChecked = actionStr.startsWith("[x] ");
              
              // Clean the string prefix for visual presentation
              final cleanText = actionStr
                  .replaceAll("[x] ", "")
                  .replaceAll("[ ] ", "");

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: CheckboxListTile(
                  title: Text(
                    cleanText,
                    style: TextStyle(
                      color: isChecked ? AppTheme.textMuted : AppTheme.textPrimary,
                      decoration: isChecked ? TextDecoration.lineThrough : null,
                      fontSize: 14,
                    ),
                  ),
                  value: isChecked,
                  onChanged: (val) => _toggleActionItem(index, val),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppTheme.accentViolet,
                  checkColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // TAB 4: AI Text Rewriter
  Widget _buildRewriteTab() {
    final templates = ["Professional Email", "Blog Draft", "Bulleted List", "Custom Instruction"];
    
    // Get existing result for display if it exists in the note
    final displayKey = _selectedRewriteTemplate == "Custom Instruction" ? "Custom Draft" : _selectedRewriteTemplate;
    final String? savedRewrite = _note.aiRewrite[displayKey];
    
    final resultToShow = _currentRewriteResult ?? savedRewrite;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "AI Copywriter & Formatter",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.accentMagenta),
        ),
        const SizedBox(height: 12),
        // Dropdown selection
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.bgObsidian.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRewriteTemplate,
                    isExpanded: true,
                    dropdownColor: AppTheme.bgMidnight,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    items: templates.map((tmpl) => DropdownMenuItem(
                      value: tmpl,
                      child: Text(tmpl),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedRewriteTemplate = val;
                          _currentRewriteResult = null;
                        });
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Run Button
            GestureDetector(
              onTap: _isRewriting ? null : _triggerRewrite,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _isRewriting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),

        // Custom text field if Custom Instruction is selected
        if (_selectedRewriteTemplate == "Custom Instruction") ...[
          const SizedBox(height: 10),
          TextField(
            controller: _customRewriteController,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              hintText: "Enter custom style/format guidelines (e.g. 'Translate to Spanish')",
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],

        const Divider(color: AppTheme.borderLight, height: 24),

        // Rewritten Text Output Display
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgObsidian.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: _isRewriting
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accentViolet))
                : resultToShow != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: () => _copyToClipboard(resultToShow, "AI Rewrite"),
                                child: const Icon(Icons.copy_rounded, color: AppTheme.textSecondary, size: 16),
                              ),
                            ],
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Text(
                                resultToShow,
                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, height: 1.5),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: Text(
                          "Tap the magic wand icon above to generate the rewrite draft.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
          ),
        ),
      ],
    );
  }
}
