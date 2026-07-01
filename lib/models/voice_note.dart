import 'dart:convert';

class VoiceNote {
  final String id;
  final String title;
  final DateTime createdAt;
  final String filePath;
  final int durationMs;
  final String transcript;
  final List<String> aiSummary;
  final List<String> aiActions;
  final Map<String, String> aiRewrite; // Key: template name, Value: rewritten content
  final List<String> tags;

  VoiceNote({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.filePath,
    required this.durationMs,
    required this.transcript,
    this.aiSummary = const [],
    this.aiActions = const [],
    this.aiRewrite = const {},
    this.tags = const [],
  });

  // Convert to JSON Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'filePath': filePath,
      'durationMs': durationMs,
      'transcript': transcript,
      'aiSummary': aiSummary,
      'aiActions': aiActions,
      'aiRewrite': aiRewrite,
      'tags': tags,
    };
  }

  // Create from JSON Map
  factory VoiceNote.fromMap(Map<String, dynamic> map) {
    return VoiceNote(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Untitled Note',
      createdAt: map['createdAt'] != null 
          ? DateTime.parse(map['createdAt']) 
          : DateTime.now(),
      filePath: map['filePath'] ?? '',
      durationMs: map['durationMs'] ?? 0,
      transcript: map['transcript'] ?? '',
      aiSummary: List<String>.from(map['aiSummary'] ?? []),
      aiActions: List<String>.from(map['aiActions'] ?? []),
      aiRewrite: Map<String, String>.from(map['aiRewrite'] ?? {}),
      tags: List<String>.from(map['tags'] ?? []),
    );
  }

  // Convert to JSON String
  String toJson() => json.encode(toMap());

  // Create from JSON String
  factory VoiceNote.fromJson(String source) => VoiceNote.fromMap(json.decode(source));

  // Copy with helper
  VoiceNote copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    String? filePath,
    int? durationMs,
    String? transcript,
    List<String>? aiSummary,
    List<String>? aiActions,
    Map<String, String>? aiRewrite,
    List<String>? tags,
  }) {
    return VoiceNote(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      transcript: transcript ?? this.transcript,
      aiSummary: aiSummary ?? this.aiSummary,
      aiActions: aiActions ?? this.aiActions,
      aiRewrite: aiRewrite ?? this.aiRewrite,
      tags: tags ?? this.tags,
    );
  }
}
