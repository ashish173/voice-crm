import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/voice_note.dart';

class StorageService {
  static const String _keyVoiceNotes = 'whisperflow_voice_notes';
  static const String _keyGeminiApiKey = 'whisperflow_gemini_api_key';

  // Get all voice notes, sorted by creation date descending
  static Future<List<VoiceNote>> getVoiceNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = prefs.getStringList(_keyVoiceNotes) ?? [];
    
    final List<VoiceNote> notes = notesJson
        .map((jsonStr) => VoiceNote.fromJson(jsonStr))
        .toList();
        
    // Sort descending (newest first)
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notes;
  }

  // Save or update a voice note
  static Future<void> saveVoiceNote(VoiceNote note) async {
    final prefs = await SharedPreferences.getInstance();
    final List<VoiceNote> notes = await getVoiceNotes();
    
    // Check if note already exists and update, otherwise insert
    final index = notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      notes[index] = note;
    } else {
      notes.add(note);
    }

    final notesJson = notes.map((n) => n.toJson()).toList();
    await prefs.setStringList(_keyVoiceNotes, notesJson);
  }

  // Delete a voice note and its associated audio file
  static Future<void> deleteVoiceNote(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<VoiceNote> notes = await getVoiceNotes();
    
    final index = notes.indexWhere((n) => n.id == id);
    if (index != -1) {
      final note = notes[index];
      // Try to delete the local audio file
      try {
        final file = File(note.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print("Error deleting audio file: $e");
      }

      notes.removeAt(index);
      final notesJson = notes.map((n) => n.toJson()).toList();
      await prefs.setStringList(_keyVoiceNotes, notesJson);
    }
  }

  // Get Gemini API Key
  static Future<String?> getGeminiApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGeminiApiKey);
  }

  // Save Gemini API Key
  static Future<void> saveGeminiApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key.trim().isEmpty) {
      await prefs.remove(_keyGeminiApiKey);
    } else {
      await prefs.setString(_keyGeminiApiKey, key.trim());
    }
  }
}
