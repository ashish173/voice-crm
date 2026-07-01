import Flutter
import UIKit
import AppIntents
import Speech

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let registrar = self.registrar(forPlugin: "TranscribePluginMain") {
      self.registerTranscribeChannel(with: registrar.messenger())
    } else if let controller = window?.rootViewController as? FlutterViewController {
      self.registerTranscribeChannel(with: controller.binaryMessenger)
    }

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TranscribePluginImplicit") {
      self.registerTranscribeChannel(with: registrar.messenger())
    }
  }

  private func registerTranscribeChannel(with messenger: FlutterBinaryMessenger) {
    print("AppDelegate: registering MethodChannel com.whisperflow/transcribe")
    let transcribeChannel = FlutterMethodChannel(name: "com.whisperflow/transcribe",
                                              binaryMessenger: messenger)
    transcribeChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "transcribeFile" {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "FilePath is missing", details: nil))
          return
        }
        self?.transcribeAudioFile(filePath: filePath, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
  }

  private func transcribeAudioFile(filePath: String, result: @escaping FlutterResult) {
      let fileURL = URL(fileURLWithPath: filePath)
      
      SFSpeechRecognizer.requestAuthorization { authStatus in
          DispatchQueue.main.async {
              switch authStatus {
              case .authorized:
                  self.performTranscription(fileURL: fileURL, result: result)
              case .denied:
                  result(FlutterError(code: "PERMISSION_DENIED", message: "Speech recognition permission denied by user", details: nil))
              case .restricted:
                  result(FlutterError(code: "RESTRICTED", message: "Speech recognition restricted on this device", details: nil))
              case .notDetermined:
                  result(FlutterError(code: "NOT_DETERMINED", message: "Speech recognition not determined", details: nil))
              @unknown default:
                  result(FlutterError(code: "UNKNOWN", message: "Unknown speech recognition status", details: nil))
              }
          }
      }
  }

  private func performTranscription(fileURL: URL, result: @escaping FlutterResult) {
      guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
          result(FlutterError(code: "UNAVAILABLE", message: "SFSpeechRecognizer is not available or does not support local transcription", details: nil))
          return
      }
      
      let request = SFSpeechURLRecognitionRequest(url: fileURL)
      request.shouldReportPartialResults = false
      if #available(iOS 13.0, *) {
          request.requiresOnDeviceRecognition = false
      }
      
      var hasSentResult = false
      recognizer.recognitionTask(with: request) { recognitionResult, error in
          DispatchQueue.main.async {
              if hasSentResult { return }
              
              if let error = error {
                  hasSentResult = true
                  result(FlutterError(code: "TRANSCRIBE_ERROR", message: error.localizedDescription, details: nil))
                  return
              }
              
              guard let recognitionResult = recognitionResult else { return }
              
              if recognitionResult.isFinal {
                  hasSentResult = true
                  let transcript = recognitionResult.bestTranscription.formattedString
                  result(transcript)
              }
          }
      }
  }
}

// Siri App Intents and App Shortcuts Integration (iOS 16+)
@available(iOS 16.0, *)
struct RecordVoiceNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Voice Note"
    static var description = IntentDescription("Launches Flow Notes and immediately starts recording a voice note.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "whisperflow://record") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct WhisperflowShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordVoiceNoteIntent(),
            phrases: [
                "Record a voice note in \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Capture voice note in \(.applicationName)"
            ],
            shortTitle: "Record Voice Note",
            systemImageName: "mic.fill"
        )
    }
}
