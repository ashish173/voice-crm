import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/voice_note.dart';
import 'storage_service.dart';
import 'transcription_service.dart';

class AIService {
  // Process the recorded audio note. If native transcription is available, it uses it.
  // Then, if a Gemini API Key is configured, it will call the Gemini API for high-quality
  // summary, action items, and tags from the transcript text.
  // Otherwise, it will fallback to audio-based Gemini or simulated note processing.
  static Future<VoiceNote> processAudioNote(String filePath, int durationMs) async {
    final apiKey = await StorageService.getGeminiApiKey();

    // 1. Attempt native on-device transcription first (e.g. iOS)
    try {
      final nativeTranscript = await TranscriptionService.transcribeAudio(filePath);
      if (nativeTranscript != null && nativeTranscript.trim().isNotEmpty) {
        print("Successfully obtained native transcription: '$nativeTranscript'");
        if (apiKey != null && apiKey.isNotEmpty) {
          try {
            return await _processTextTranscriptWithGemini(filePath, durationMs, nativeTranscript, apiKey);
          } catch (e) {
            print("Gemini API text processing failed, falling back to simulated text note: $e");
            return _generateSimulatedNoteFromText(filePath, durationMs, nativeTranscript);
          }
        } else {
          return _generateSimulatedNoteFromText(filePath, durationMs, nativeTranscript);
        }
      }
    } catch (e) {
      print("Native transcription failed or not supported: $e");
    }

    // 2. Fallback to full audio processing (Gemini or simulated)
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        return await _processWithGemini(filePath, durationMs, apiKey);
      } catch (e) {
        print("Gemini API audio processing failed, falling back to simulated mode: $e");
        return _generateSimulatedNote(filePath, durationMs, errorContext: e.toString());
      }
    } else {
      return _generateSimulatedNote(filePath, durationMs);
    }
  }

  // Upload audio note to Gemini for full transcription and structural analysis
  static Future<VoiceNote> _processWithGemini(String filePath, int durationMs, String apiKey) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception("Audio file not found at $filePath");
    }

    final bytes = await file.readAsBytes();
    final base64Audio = base64Encode(bytes);

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey'
    );

    final prompt = """
    Analyze this audio file. Perform the following operations:
    1. Transcribe the spoken text in the audio with high accuracy and include natural formatting (paragraphs, capitalization, punctuation).
    2. Generate a short, catchy, professional title (3-5 words) that summarizes the note.
    3. Generate a summary list of 3-5 key takeaways/bullet points.
    4. Extract a list of 2-5 actionable items or checklists. If there are no clear actions, suggest logical next steps.
    5. Choose 1 to 3 relevant tags (e.g. "Work", "Idea", "Meeting", "Personal", "Study", "To-Do") for this note.

    You MUST return the output as a JSON object with this exact structure:
    {
      "title": "Short Title Here",
      "transcript": "Exact transcription of the audio...",
      "summary": ["Takeaway 1", "Takeaway 2", "Takeaway 3"],
      "actions": ["Action Item 1", "Action Item 2"],
      "tags": ["Tag1", "Tag2"]
    }

    Return ONLY the raw JSON output. Do not include markdown code block formatting (no ```json). Do not add any text before or after the JSON.
    """;

    final requestBody = {
      "contents": [
        {
          "parts": [
            {
              "inlineData": {
                "mimeType": "audio/mp4", // AAC LC in M4A container maps to mp4/m4a audio formats
                "data": base64Audio
              }
            },
            {
              "text": prompt
            }
          ]
        }
      ],
      "generationConfig": {
        "responseMimeType": "application/json"
      }
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception("Gemini API error (Status ${response.statusCode}): ${response.body}");
    }

    final responseJson = json.decode(response.body);
    final textOutput = responseJson['candidates']?[0]['content']?[partsKey(responseJson)]?[0]['text'] ?? '';
    
    if (textOutput.toString().trim().isEmpty) {
      throw Exception("Empty response received from Gemini API");
    }

    // Parse the returned JSON from Gemini
    final Map<String, dynamic> data = json.decode(textOutput);

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Perform initial mock rewrites to seed the note, or we can lazy-generate them
    final initialRewrites = {
      'Professional Email': 'Drafting professional email from transcript: "${data['transcript']}"',
      'Clear Summary': 'Summary draft: ' + (data['summary'] as List).join(', '),
    };

    return VoiceNote(
      id: id,
      title: data['title'] ?? 'Voice Note',
      createdAt: DateTime.now(),
      filePath: filePath,
      durationMs: durationMs,
      transcript: data['transcript'] ?? '',
      aiSummary: List<String>.from(data['summary'] ?? []),
      aiActions: List<String>.from(data['actions'] ?? []),
      aiRewrite: initialRewrites,
      tags: List<String>.from(data['tags'] ?? ['Voice']),
    );
  }

  // Helper to extract parts key which varies in some API structures
  static int partsKey(dynamic responseJson) {
    // Standard structure is candidates[0].content.parts
    return 0;
  }

  // Call Gemini to rewrite a transcript using a specific template/instructions
  static Future<String> rewriteTranscript(String transcript, String template) async {
    final apiKey = await StorageService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return _simulateRewrite(transcript, template);
    }

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey'
      );

      String systemInstruction = "";
      if (template == "Professional Email") {
        systemInstruction = "Rewrite the following transcript into a polite, professional email. Add placeholders like [Name] where appropriate. Keep it clean and polished.";
      } else if (template == "Blog Draft") {
        systemInstruction = "Rewrite the following transcript into a structured, engaging blog post draft with a headline and clear paragraphs. Maintain a conversational but informative tone.";
      } else if (template == "Bulleted List") {
        systemInstruction = "Convert the key ideas, items, or points in the transcript into a beautifully structured, hierarchical bulleted list.";
      } else {
        systemInstruction = "Rewrite the following transcript according to these instructions: $template";
      }

      final requestBody = {
        "contents": [
          {
            "parts": [
              {
                "text": "$systemInstruction\n\nTranscript:\n\"$transcript\""
              }
            ]
          }
        ]
      };

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(requestBody),
      );

      if (response.statusCode != 200) {
        throw Exception("API Error: ${response.statusCode}");
      }

      final responseJson = json.decode(response.body);
      return responseJson['candidates']?[0]['content']?.containsKey('parts') == true 
          ? responseJson['candidates'][0]['content']['parts'][0]['text'] ?? ''
          : responseJson['candidates'][0]['content']['parts'][0]['text'] ?? '';
    } catch (e) {
      print("Rewrite API call failed: $e");
      return _simulateRewrite(transcript, template);
    }
  }

  // Simulated Note Generator for Offline / Fallback mode
  static VoiceNote _generateSimulatedNote(String filePath, int durationMs, {String? errorContext}) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dateStr = DateTime.now().toString().substring(0, 16);
    
    // Choose a realistic set of mock transcripts depending on note duration
    String transcript;
    String title;
    List<String> summary;
    List<String> actions;
    List<String> tags;

    if (durationMs < 5000) {
      title = "Quick Reminder";
      transcript = "Remember to buy groceries and call Ashish back before checking the logs tonight.";
      summary = ["Quick reminder generated on recording.", "Tasks: buy groceries, contact Ashish."];
      actions = ["Buy groceries", "Call Ashish back tonight"];
      tags = ["Personal", "To-Do"];
    } else if (durationMs < 15000) {
      title = "Product Brainstorming";
      transcript = "We should implement a premium design for the mobile app, focusing on glassmorphic elements, deep neon gradients, and elegant hover animations. Also, the iOS shortcut must trigger URL deep-linking immediately.";
      summary = [
        "Discussed mobile application visual requirements.",
        "Stressed key elements: glassmorphic design and neon gradients.",
        "Emphasized linking Action Button to custom URL schemes."
      ];
      actions = [
        "Design translucent card overlay components in Flutter",
        "Implement custom scheme handler for 'whisperflow://'",
        "Test URL routing from native Shortcuts app"
      ];
      tags = ["Work", "Design"];
    } else {
      title = "Weekly Tech Sync";
      transcript = "So for the weekly update, the database migration is complete and we verified that queries are twice as fast now. I need to document the new API schema in the wiki. Also, let's set up the staging environment and deploy the replica build for manual testing next Tuesday. Let's make sure the client logs are enabled.";
      summary = [
        "Announced successful completion of the database migration.",
        "Reported 2x improvement in query performance.",
        "Identified next steps: wiki documentation and staging setup.",
        "Scheduled the replica build deployment for next Tuesday."
      ];
      actions = [
        "Document new API schema in the developer wiki",
        "Prepare staging deployment pipeline",
        "Deploy Whisperflow replica build to staging by Tuesday morning",
        "Confirm client log collectors are active"
      ];
      tags = ["Work", "Sync", "Engineering"];
    }

    if (errorContext != null) {
      transcript = "[API Offline Fallback] $transcript\n\n(Note: Processing failed due to: $errorContext)";
    }

    final initialRewrites = {
      'Professional Email': _simulateRewrite(transcript, 'Professional Email'),
      'Blog Draft': _simulateRewrite(transcript, 'Blog Draft'),
      'Bulleted List': _simulateRewrite(transcript, 'Bulleted List'),
    };

    return VoiceNote(
      id: id,
      title: title,
      createdAt: DateTime.now(),
      filePath: filePath,
      durationMs: durationMs,
      transcript: transcript,
      aiSummary: summary,
      aiActions: actions,
      aiRewrite: initialRewrites,
      tags: const [],
    );
  }

  // Simulated Rewrite Generator for Offline Mode
  static String _simulateRewrite(String transcript, String template) {
    if (template == "Professional Email") {
      return """Subject: Update: Notes and Action Items from Recording

Dear Team,

I am writing to share the key details transcribed from my recent voice update:

"${transcript.replaceAll('[API Offline Fallback] ', '')}"

To summarize our next steps:
- We will proceed with implementing the visual design elements discussed.
- All tasks have been logged, and we are tracking action items to ensure timely completion.

Please let me know if you have any questions or feedback.

Best regards,
[Name]""";
    } else if (template == "Blog Draft") {
      return """# Unlocking Productivity: Capturing Spoken Ideas

We often think faster than we type. In our recent sync, we explored ideas that could redefine our workflow:

> "${transcript.replaceAll('[API Offline Fallback] ', '')}"

### The Core Shift
Capturing thoughts in real-time allows us to avoid losing fleeting inspiration. By leveraging voice-first capture mechanics—like a dedicated physical trigger—we bridge the gap between active thinking and technical logging.

### What Lies Ahead
In the coming weeks, we will be polishing these mechanisms to ensure seamless integrations across all platforms, pushing the boundaries of local productivity software.""";
    } else {
      // Bulleted List
      return """• Key Notes Captured:
  - Transcript: "${transcript.replaceAll('[API Offline Fallback] ', '')}"
  - Created: Just now
  - Action Items:
    - Review recorded objectives
    - Sync with team on milestones""";
    }
  }

  // Call Gemini with the text transcript to generate structural analysis (title, summary, actions, tags)
  static Future<VoiceNote> _processTextTranscriptWithGemini(
      String filePath, int durationMs, String transcript, String apiKey) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey'
    );

    final prompt = """
    Analyze this transcribed speech text. Perform the following operations:
    1. Clean up any minor transcribing noise or run-on sentences to format it nicely, but preserve the exact meaning.
    2. Generate a short, catchy, professional title (3-5 words) that summarizes the note.
    3. Generate a summary list of 3-5 key takeaways/bullet points.
    4. Extract a list of 2-5 actionable items or checklists. If there are no clear actions, suggest logical next steps.
    5. Choose 1 to 3 relevant tags (e.g. "Work", "Idea", "Meeting", "Personal", "Study", "To-Do") for this note.

    You MUST return the output as a JSON object with this exact structure:
    {
      "title": "Short Title Here",
      "summary": ["Takeaway 1", "Takeaway 2", "Takeaway 3"],
      "actions": ["Action Item 1", "Action Item 2"],
      "tags": ["Tag1", "Tag2"]
    }

    Return ONLY the raw JSON output. Do not include markdown code block formatting (no ```json). Do not add any text before or after the JSON.

    Speech Text to analyze:
    "$transcript"
    """;

    final requestBody = {
      "contents": [
        {
          "parts": [
            {
              "text": prompt
            }
          ]
        }
      ],
      "generationConfig": {
        "responseMimeType": "application/json"
      }
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception("Gemini API text processing error (Status ${response.statusCode}): ${response.body}");
    }

    final responseJson = json.decode(response.body);
    final textOutput = responseJson['candidates']?[0]['content']?[partsKey(responseJson)]?[0]['text'] ?? '';
    
    if (textOutput.toString().trim().isEmpty) {
      throw Exception("Empty response received from Gemini API");
    }

    final Map<String, dynamic> data = json.decode(textOutput);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    
    final initialRewrites = {
      'Professional Email': await rewriteTranscript(transcript, 'Professional Email'),
      'Blog Draft': await rewriteTranscript(transcript, 'Blog Draft'),
      'Bulleted List': await rewriteTranscript(transcript, 'Bulleted List'),
    };

    return VoiceNote(
      id: id,
      title: data['title'] ?? 'Voice Note',
      createdAt: DateTime.now(),
      filePath: filePath,
      durationMs: durationMs,
      transcript: transcript,
      aiSummary: List<String>.from(data['summary'] ?? []),
      aiActions: List<String>.from(data['actions'] ?? []),
      aiRewrite: initialRewrites,
      tags: const [],
    );
  }

  // Simulated Note Generator for Offline / Fallback mode using actual native transcript
  static VoiceNote _generateSimulatedNoteFromText(String filePath, int durationMs, String transcript) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Simple heuristics for title
    final words = transcript.split(' ');
    String title = words.take(4).join(' ');
    if (title.length > 25) {
      title = '${title.substring(0, 22)}...';
    }
    if (title.trim().isEmpty) {
      title = "Voice Note";
    } else {
      title = "${title[0].toUpperCase()}${title.substring(1)}";
    }

    final initialRewrites = {
      'Professional Email': _simulateRewrite(transcript, 'Professional Email'),
      'Blog Draft': _simulateRewrite(transcript, 'Blog Draft'),
      'Bulleted List': _simulateRewrite(transcript, 'Bulleted List'),
    };

    return VoiceNote(
      id: id,
      title: title,
      createdAt: DateTime.now(),
      filePath: filePath,
      durationMs: durationMs,
      transcript: transcript,
      aiSummary: [
        "Transcribed locally using on-device Speech recognition.",
        "Audio length: ${(durationMs / 1000).toStringAsFixed(1)} seconds."
      ],
      aiActions: [
        "Review on-device transcription details",
        "Add manual tags or categories if needed"
      ],
      aiRewrite: initialRewrites,
      tags: const [],
    );
  }
}
