import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/voice_note.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'note_detail_screen.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List<VoiceNote> _allNotes = [];
  List<VoiceNote> _filteredNotes = [];
  bool _isLoading = true;
  
  String _searchQuery = '';
  String _selectedTag = 'All';
  List<String> _availableTags = ['All'];

  late AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _loadNotes();
    
    // Pulse animation for the central recording button
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  // Load voice notes from local storage
  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final notes = await StorageService.getVoiceNotes();
      
      // Extract unique tags for filtering
      final Set<String> tagSet = {'All'};
      for (var note in notes) {
        tagSet.addAll(note.tags);
      }

      setState(() {
        _allNotes = notes;
        _availableTags = tagSet.toList();
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

  // Filter notes based on search query and selected tag
  void _applyFilters() {
    setState(() {
      _filteredNotes = _allNotes.where((note) {
        final matchesSearch = note.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            note.transcript.toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesTag = _selectedTag == 'All' || note.tags.contains(_selectedTag);
        
        return matchesSearch && matchesTag;
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

  // Helper to open details screen
  void _openNoteDetails(VoiceNote note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NoteDetailScreen(note: note)),
    );
    _loadNotes(); // Reload notes in case they were updated
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
                          "Flow Notes",
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "AI-powered voice journal",
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
                    hintText: "Search notes, transcripts, tags...",
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

              // Tags Filters (Horizontal List)
              if (_availableTags.length > 1)
                Container(
                  height: 40,
                  margin: const EdgeInsets.only(bottom: 12.0),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    itemCount: _availableTags.length,
                    itemBuilder: (context, index) {
                      final tag = _availableTags[index];
                      final isSelected = _selectedTag == tag;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTag = tag;
                              _applyFilters();
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: isSelected ? AppTheme.primaryGradient : null,
                              color: isSelected ? null : AppTheme.surfaceTranslucent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected 
                                    ? AppTheme.accentMagenta.withOpacity(0.5) 
                                    : AppTheme.borderLight,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppTheme.textSecondary,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Quick Info Banner for physical Shortcut
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: AppTheme.glassDecoration(
                    borderRadius: 12,
                    borderColor: AppTheme.accentCyan.withOpacity(0.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.offline_bolt_rounded, color: AppTheme.accentCyan, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Configure Side Button to trigger voice recording instantly. Tap settings icon above to view the setup guide.",
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

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
      child: GestureDetector(
        onTap: () => _openNoteDetails(note),
        child: Container(
          decoration: AppTheme.glassDecoration(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
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
                      // Date and metadata
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
                      // Tags and Action Menu
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Note tags
                          Wrap(
                            spacing: 6,
                            children: note.tags.map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.bgObsidian.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.borderLight),
                              ),
                              child: Text(
                                '#$tag',
                                style: const TextStyle(
                                  color: AppTheme.accentCyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )).toList(),
                          ),
                          // Delete / Menu trigger
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
                  : "Try checking your spelling or selecting a different tag filter.",
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
}
