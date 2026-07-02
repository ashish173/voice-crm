# Peraj AI CRM (Whisperflow)

A modern, fast, and feature-rich AI-powered CRM companion mobile application built with Flutter. It allows professionals to capture voice updates, transcribe them.

## Features Developed

- **On-Device Voice Capture**: 
  - Rich, glassmorphic UI with a pulsating orb animation and a real-time rolling audio wave visualizer.
  - Controls for pause, resume, and trash/cancellation.
- **Hardware & Siri Shortcuts Integration**:
  - Deep integration with iOS App Intents and Apple Shortcuts.
  - Supports launching and stopping voice recording instantly via a long press of the device's hardware side button
- **AI Processing Pipeline**:
  - Automated transcription, text cleaning, summary generation, action items extraction, and key insights formatting.
- **Local Persistence & Offline First**:
  - Secure offline storage for voice notes, transcripts, and AI-generated metadata.

## Tech Stack

- **Frontend**: Flutter & Dart
- **OS Native Integration**: Swift (iOS), `SFSpeechRecognizer` for native transcription, `AppIntents` for iOS 16+ hardware shortcut triggers.
- **Database/Storage**: Local file system & database storage.

## Future / Pending Roadmap

- [ ] **API Transcription Integration**: Connect to a cloud API (e.g., Whisper API) to replace the on-device transcription layer for higher accuracy.
- [ ] **Company Management**: Fetch the company list from CRM endpoints and allow users to assign notes/action items to specific companies.
