import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/voice_note.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class VoiceNoteBottomSheet extends StatefulWidget {
  final VoiceNote note;
  final VoidCallback onUpdate;

  const VoiceNoteBottomSheet({
    Key? key,
    required this.note,
    required this.onUpdate,
  }) : super(key: key);

  @override
  State<VoiceNoteBottomSheet> createState() => _VoiceNoteBottomSheetState();
}

class _VoiceNoteBottomSheetState extends State<VoiceNoteBottomSheet> {
  late VoiceNote _note;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _audioFileExists = false;

  // Search & Select dropdown state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showDropdown = false;
  String _searchQuery = '';

  final List<String> _companies = [
    "Google",
    "Apple",
    "Microsoft",
    "Meta",
    "Amazon",
    "Tesla",
    "Netflix",
    "OpenAI",
  ];

  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _searchController.text = _note.customer ?? '';
    _checkAudioFile();
    _initAudioPlayer();
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkAudioFile() async {
    final fileExists = await File(_note.filePath).exists();
    if (mounted) {
      setState(() {
        _audioFileExists = fileExists;
      });
    }
  }

  void _initAudioPlayer() async {
    try {
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

      if (_audioFileExists) {
        await _audioPlayer.setSource(DeviceFileSource(_note.filePath));
      }

      _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
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

  void _togglePlayPause() async {
    if (!_audioFileExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Audio file not found on device.")),
      );
      return;
    }

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(DeviceFileSource(_note.filePath));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Playback error: $e")),
      );
    }
  }

  Future<void> _assignCustomer(String customerName) async {
    final updatedNote = _note.copyWith(customer: customerName);
    await StorageService.saveVoiceNote(updatedNote);
    if (mounted) {
      setState(() {
        _note = updatedNote;
        _searchController.text = customerName;
        _showDropdown = false;
      });
      _searchFocusNode.unfocus();
    }
    widget.onUpdate();
  }

  Future<void> _deleteNote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgMidnight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.borderLight),
        ),
        title: const Text("Delete Recording"),
        content: const Text("Are you sure you want to permanently delete this voice note and its audio recording?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.deleteVoiceNote(_note.id);
      widget.onUpdate();
      if (mounted) {
        Navigator.pop(context); // Close bottom sheet
      }
    }
  }

  String _formatTime(Duration duration) {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatted = DateFormat('MMMM d, yyyy • h:mm a').format(_note.createdAt);
    
    // Filter companies for the searchable dropdown
    final filteredCompanies = _companies
        .where((c) => c.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgMidnight,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border(
            top: BorderSide(color: AppTheme.borderLight, width: 1.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pull Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and Date Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _note.title,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateFormatted,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      onPressed: _deleteNote,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),

              // Audio Player Panel
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppTheme.glassDecoration(borderRadius: 16),
                  child: Row(
                    children: [
                      // Play/Pause circular button
                      GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accentViolet.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Progress slider and timestamps
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                activeTrackColor: AppTheme.accentMagenta,
                                inactiveTrackColor: AppTheme.borderLight,
                                thumbColor: AppTheme.accentMagenta,
                                overlayColor: AppTheme.accentMagenta.withOpacity(0.12),
                              ),
                              child: Slider(
                                min: 0.0,
                                max: _duration.inMilliseconds.toDouble() > 0.0
                                    ? _duration.inMilliseconds.toDouble()
                                    : 1.0,
                                value: _position.inMilliseconds.toDouble().clamp(
                                      0.0,
                                      _duration.inMilliseconds.toDouble() > 0.0
                                          ? _duration.inMilliseconds.toDouble()
                                          : 1.0,
                                    ),
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
                                    _formatTime(_position),
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                  ),
                                  Text(
                                    _formatTime(_duration),
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Search & Select Customer Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Assign Customer",
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    CompositedTransformTarget(
                      link: LayerLink(),
                      child: Container(
                        decoration: AppTheme.glassDecoration(borderRadius: 12),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                          onTap: () {
                            setState(() {
                              _showDropdown = true;
                            });
                          },
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                              _showDropdown = true;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: "Search & select company...",
                            prefixIcon: const Icon(Icons.business_rounded, color: AppTheme.textSecondary, size: 18),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchController.text.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => _assignCustomer(''),
                                    child: const Icon(Icons.clear_rounded, color: AppTheme.textSecondary, size: 18),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    _showDropdown ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showDropdown = !_showDropdown;
                                      if (_showDropdown) {
                                        _searchFocusNode.requestFocus();
                                      } else {
                                        _searchFocusNode.unfocus();
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    
                    // Search dropdown suggestions overlay
                    if (_showDropdown)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 160),
                        decoration: BoxDecoration(
                          color: AppTheme.bgObsidian,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderLight),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: filteredCompanies.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text("No company found", style: TextStyle(color: AppTheme.textMuted)),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: filteredCompanies.length,
                                  itemBuilder: (context, index) {
                                    final comp = filteredCompanies[index];
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _assignCustomer(comp),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Text(
                                            comp,
                                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Transcript Panel
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Transcript",
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.glassDecoration(borderRadius: 16),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Text(
                          _note.transcript.isNotEmpty
                              ? _note.transcript
                              : "No transcript available.",
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
