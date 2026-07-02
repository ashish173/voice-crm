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

  // ── Audio ────────────────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _audioReady = false; // true once setSource succeeds
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  // ── Customer dropdown ────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showDropdown = false;
  String _searchQuery = '';

  // Stable LayerLink for CompositedTransformFollower
  final LayerLink _layerLink = LayerLink();

  static const List<String> _companies = [
    'Apple',
    'Google',
    'Microsoft',
    'Meta',
    'Amazon',
    'Tesla',
    'Netflix',
    'OpenAI',
    'Salesforce',
    'SAP',
    'Oracle',
    'IBM',
  ];

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _searchController.text = _note.customer ?? '';
    _initAudioPlayer(); // async: checks file then sets up player
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

  // ── Audio setup ──────────────────────────────────────────────────────────
  Future<void> _initAudioPlayer() async {
    // First: confirm file exists before touching the player
    final fileExists = await File(_note.filePath).exists();
    if (!mounted) return;

    if (!fileExists) {
      // Nothing to play – still show the sheet, just disable the player
      return;
    }

    try {
      await _audioPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            // playback category: plays through speaker by default (no earpiece)
            // defaultToSpeaker is only valid for playAndRecord – omit it here.
            category: AVAudioSessionCategory.playback,
            options: const {
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

      await _audioPlayer.setSource(DeviceFileSource(_note.filePath));

      if (mounted) setState(() => _audioReady = true);

      _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });
      _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
      });
      _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() { _position = Duration.zero; _isPlaying = false; });
      });
    } catch (e) {
      debugPrint('VoiceNoteBottomSheet: audio init error: $e');
    }
  }

  void _togglePlayPause() async {
    if (!_audioReady) return;
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        // Source is already loaded via setSource() in _initAudioPlayer.
        // Use resume() to avoid re-setting source which resets the player on iOS.
        await _audioPlayer.resume();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Playback error: $e')));
      }
    }
  }

  // ── Customer assignment ──────────────────────────────────────────────────
  Future<void> _assignCustomer(String name) async {
    final updated = _note.copyWith(customer: name.isEmpty ? null : name);
    await StorageService.saveVoiceNote(updated);
    if (!mounted) return;
    setState(() {
      _note = updated;
      _searchController.text = name;
      _searchQuery = name;
      _showDropdown = false;
    });
    _searchFocusNode.unfocus();
    widget.onUpdate();
  }

  // ── Delete ───────────────────────────────────────────────────────────────
  Future<void> _deleteNote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgMidnight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.borderLight),
        ),
        title: const Text('Delete Recording'),
        content: const Text(
            'Permanently delete this voice note and its audio file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20))),
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.deleteVoiceNote(_note.id);
      widget.onUpdate();
      if (mounted) Navigator.pop(context);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('MMMM d, yyyy • h:mm a').format(_note.createdAt);
    final filtered = _companies
        .where((c) => c.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return GestureDetector(
      // Dismiss dropdown when tapping outside the search field
      onTap: () {
        if (_showDropdown) setState(() => _showDropdown = false);
        _searchFocusNode.unfocus();
      },
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgMidnight,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border(top: BorderSide(color: AppTheme.borderLight, width: 1.5)),
        ),
        // SingleChildScrollView lets content push up above the keyboard
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          // viewInsets accounts for the keyboard height
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Drag handle ──────────────────────────────────────────
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

                // ── Title row ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _note.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent),
                        onPressed: _deleteNote,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Audio player ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: AppTheme.glassDecoration(borderRadius: 16),
                    child: Row(
                      children: [
                        // Play / Pause button
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: _audioReady
                                  ? AppTheme.primaryGradient
                                  : null,
                              color: _audioReady
                                  ? null
                                  : AppTheme.surfaceTranslucent,
                              shape: BoxShape.circle,
                              boxShadow: _audioReady
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.accentViolet
                                            .withOpacity(0.35),
                                        blurRadius: 10,
                                      )
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: _audioReady
                                  ? Colors.white
                                  : AppTheme.textMuted,
                              size: 28,
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Slider + timestamps
                        Expanded(
                          child: Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14),
                                  activeTrackColor: AppTheme.accentMagenta,
                                  inactiveTrackColor: AppTheme.borderLight,
                                  thumbColor: AppTheme.accentMagenta,
                                  overlayColor:
                                      AppTheme.accentMagenta.withOpacity(0.12),
                                  disabledThumbColor: AppTheme.textMuted,
                                  disabledActiveTrackColor: AppTheme.textMuted,
                                  disabledInactiveTrackColor:
                                      AppTheme.borderLight,
                                ),
                                child: Slider(
                                  min: 0,
                                  max: _duration.inMilliseconds > 0
                                      ? _duration.inMilliseconds.toDouble()
                                      : 1,
                                  value: _position.inMilliseconds
                                      .toDouble()
                                      .clamp(
                                          0,
                                          _duration.inMilliseconds > 0
                                              ? _duration.inMilliseconds
                                                  .toDouble()
                                              : 1),
                                  onChanged: _audioReady
                                      ? (v) => _audioPlayer.seek(
                                          Duration(milliseconds: v.toInt()))
                                      : null,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_fmt(_position),
                                        style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 11)),
                                    Text(_fmt(_duration),
                                        style: const TextStyle(
                                            color: AppTheme.textMuted,
                                            fontSize: 11)),
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

                const SizedBox(height: 20),

                // ── Customer select ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assign Customer',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Search field with stable LayerLink
                      CompositedTransformTarget(
                        link: _layerLink,
                        child: Container(
                          decoration: AppTheme.glassDecoration(borderRadius: 12),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 14),
                            onTap: () =>
                                setState(() => _showDropdown = true),
                            onChanged: (v) => setState(() {
                              _searchQuery = v;
                              _showDropdown = true;
                            }),
                            decoration: InputDecoration(
                              hintText: 'Search & select company…',
                              hintStyle: const TextStyle(
                                  color: AppTheme.textMuted, fontSize: 14),
                              prefixIcon: const Icon(Icons.business_rounded,
                                  color: AppTheme.textSecondary, size: 18),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_searchController.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => _assignCustomer(''),
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.clear_rounded,
                                            color: AppTheme.textSecondary,
                                            size: 18),
                                      ),
                                    ),
                                  GestureDetector(
                                    onTap: () => setState(
                                        () => _showDropdown = !_showDropdown),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        _showDropdown
                                            ? Icons.arrow_drop_up_rounded
                                            : Icons.arrow_drop_down_rounded,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                        ),
                      ),

                      // Inline dropdown list (renders inside the scroll view)
                      if (_showDropdown)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            color: AppTheme.bgObsidian,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.borderLight),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.55),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: filtered.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No company found',
                                        style: TextStyle(
                                            color: AppTheme.textMuted)),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    itemCount: filtered.length,
                                    itemBuilder: (_, i) {
                                      final company = filtered[i];
                                      final isSelected =
                                          company == _note.customer;
                                      return Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () =>
                                              _assignCustomer(company),
                                          child: Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 16,
                                                vertical: 13),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? AppTheme.accentViolet
                                                      .withOpacity(0.15)
                                                  : Colors.transparent,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isSelected
                                                      ? Icons.check_circle_rounded
                                                      : Icons.business_outlined,
                                                  size: 16,
                                                  color: isSelected
                                                      ? AppTheme.accentViolet
                                                      : AppTheme.textMuted,
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  company,
                                                  style: TextStyle(
                                                    color: isSelected
                                                        ? AppTheme.accentViolet
                                                        : AppTheme.textPrimary,
                                                    fontSize: 14,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
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

                const SizedBox(height: 20),

                // ── Transcript ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Transcript',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: AppTheme.glassDecoration(borderRadius: 16),
                        child: Text(
                          _note.transcript.isNotEmpty
                              ? _note.transcript
                              : 'No transcript available.',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
