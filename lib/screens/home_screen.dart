import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/voice_note.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_note_bottom_sheet.dart';
import 'package:whisperflow_replica/main.dart' as app_globals;
import '../services/background_processor.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<VoiceNote> _allNotes = [];
  List<VoiceNote> _filteredNotes = [];
  bool _isLoading = true;
  
  String _searchQuery = '';
  final Set<String> _dismissedTaskIds = {};

  late AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _loadNotes();
    WidgetsBinding.instance.addObserver(this);
    app_globals.onVoiceNotesChanged = _loadNotes;
    
    // Pulse animation for the central recording button
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (app_globals.onVoiceNotesChanged == _loadNotes) {
      app_globals.onVoiceNotesChanged = null;
    }
    _fabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("HomeScreen: App resumed, reloading voice notes list");
      _loadNotes();
    }
  }

  // Load voice notes from local storage
  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final notes = await StorageService.getVoiceNotes();

      // Automatically resume background processing for any notes stuck in isProcessing
      for (final note in notes) {
        if (note.isProcessing) {
          BackgroundProcessor.startProcessing(note);
        }
      }

      setState(() {
        _allNotes = notes;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading notes: $e")),
      );
    }
  }

  // Filter notes based on search query
  void _applyFilters() {
    setState(() {
      _filteredNotes = _allNotes.where((note) {
        // Exclude actively processing notes from the main list view
        if (note.isProcessing) return false;

        final matchesSearch = note.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            note.transcript.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (note.customer?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
        
        return matchesSearch;
      }).toList();
    });
  }

  // Delete voice note
  Future<void> _deleteNote(String id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgMidnight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.borderLight),
        ),
        title: const Text("Delete Voice Note"),
        content: const Text("Are you sure you want to permanently delete this voice note and its audio file?"),
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
      await StorageService.deleteVoiceNote(id);
      _loadNotes();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Note deleted successfully")),
      );
    }
  }

  // Format duration into MM:SS
  String _formatDuration(int ms) {
    final int totalSeconds = ms ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Helper to open details bottom sheet pane
  void _openNoteDetails(VoiceNote note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VoiceNoteBottomSheet(
        note: note,
        onUpdate: _loadNotes,
      ),
    );
  }

  // Helper to open recording screen
  void _openRecordingScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RecordingScreen()),
    );
    _loadNotes(); // Reload notes list
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Custom Premium Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Peraj AI",
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "AI powered CRM",
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.accentMagenta.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    // Settings Button
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SettingsScreen()),
                        );
                        _loadNotes(); // Reload notes (e.g. API key might change behavior)
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: AppTheme.glassDecoration(borderRadius: 12),
                        child: const Icon(
                          Icons.settings_outlined,
                          color: AppTheme.textPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _applyFilters();
                    });
                  },
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: "Search notes, transcripts, customers...",
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _searchQuery = '';
                                _applyFilters();
                              });
                            },
                            child: const Icon(Icons.clear_rounded, color: AppTheme.textSecondary),
                          )
                        : null,
                  ),
                ),
              ),



              _buildProcessingIndicator(),

              // Voice Notes List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.accentViolet),
                      )
                    : _filteredNotes.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                            itemCount: _filteredNotes.length,
                            itemBuilder: (context, index) {
                              final note = _filteredNotes[index];
                              return _buildNoteCard(note);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      
      // Floating Recording Button
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildFab(),
    );
  }

  // Note Card Widget
  Widget _buildNoteCard(VoiceNote note) {
    final dateFormatted = DateFormat('MMM d, yyyy • h:mm a').format(note.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        decoration: AppTheme.glassDecoration(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openNoteDetails(note),
              onLongPress: () => _deleteNote(note.id),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            note.title,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Duration badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.accentViolet.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_arrow_rounded, color: AppTheme.accentMagenta, size: 14),
                              const SizedBox(width: 2),
                              Text(
                                _formatDuration(note.durationMs),
                                style: const TextStyle(
                                  color: AppTheme.accentMagenta,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Date
                    Text(
                      dateFormatted,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Transcript preview
                    Text(
                      note.transcript,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    // Customer badge + delete
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (note.customer != null && note.customer!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accentViolet.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.accentViolet.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.business_rounded, color: AppTheme.accentViolet, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  note.customer!,
                                  style: const TextStyle(
                                    color: AppTheme.accentViolet,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.bgObsidian.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.borderLight),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.business_outlined, color: AppTheme.textMuted, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'Unassigned',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        GestureDetector(
                          onTap: () => _deleteNote(note.id),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  // Empty State Widget
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceTranslucent,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.borderLight, width: 1.5),
              ),
              child: const Icon(
                Icons.mic_none_rounded,
                size: 40,
                color: AppTheme.accentMagenta,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isEmpty ? "Speak your thoughts" : "No notes found",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? "Tap the record button below or hold your side button to capture a voice note. The AI will handle the rest."
                  : "Try checking your spelling or search terms.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  // Animated Floating Action Button for Recording
  Widget _buildFab() {
    return AnimatedBuilder(
      animation: _fabController,
      builder: (context, child) {
        final double scale = 1.0 + (_fabController.value * 0.12);
        return GestureDetector(
          onTap: _openRecordingScreen,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Pulsing Circle
              Container(
                width: 76 * scale,
                height: 76 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.accentViolet.withOpacity(0.0),
                      AppTheme.accentMagenta.withOpacity(0.25 - (_fabController.value * 0.15)),
                    ],
                  ),
                ),
              ),
              // Inner Glow Ring
              Container(
                width: 68 * (1.0 + (_fabController.value * 0.05)),
                height: 68 * (1.0 + (_fabController.value * 0.05)),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accentMagenta.withOpacity(0.4 * (1.0 - _fabController.value)),
                    width: 2.0,
                  ),
                ),
              ),
              // Main Button
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentViolet,
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProcessingIndicator() {
    final processingNotes = _allNotes.where((n) => n.isProcessing).toList();
    final visibleNotes = processingNotes.where((n) => !_dismissedTaskIds.contains(n.id)).toList();

    if (visibleNotes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
      child: Column(
        children: visibleNotes.map((note) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.accentViolet.withOpacity(0.12),
                  AppTheme.accentCyan.withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.accentViolet.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentCyan),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Transcribing voice note...",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Duration: ${_formatDuration(note.durationMs)}",
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _dismissedTaskIds.add(note.id);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
