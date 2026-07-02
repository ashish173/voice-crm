import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Global recording state — used to coordinate side-button toggle behaviour
// between the deep-link handler in main.dart and the active RecordingScreen.
// ──────────────────────────────────────────────────────────────────────────────

/// True while a RecordingScreen is mounted and actively recording.
bool isRecordingActive = false;

/// RecordingScreen sets this callback on mount so the deep-link handler can
/// call _stopAndSaveNote() when the side button is pressed a second time.
VoidCallback? onStopRecordingRequested;

/// HomeScreen sets this callback so we can notify it to reload the voice notes list
VoidCallback? onVoiceNotesChanged;

// Global key to navigate from deep link handler when app is running
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  DateTime? _lastLinkTime;
  String? _lastLinkUri;

  @override
  void initState() {
    super.initState();
    _initDeepLinking();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  // Set up deep linking listener
  Future<void> _initDeepLinking() async {
    // 1. Handle link that launched the app from terminated state
    try {
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint("Failed to get initial deep link: $e");
    }

    // 2. Listen to incoming deep links while app is in background or active
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint("Error handling deep link stream: $err");
      },
    );
  }

  // Parse deep link and navigate — or stop an active recording.
  void _handleDeepLink(Uri uri) {
    final now = DateTime.now();
    if (_lastLinkUri == uri.toString() &&
        _lastLinkTime != null &&
        now.difference(_lastLinkTime!).inMilliseconds < 1000) {
      debugPrint("Side button: duplicate deep link ignored ($uri)");
      return;
    }
    _lastLinkUri = uri.toString();
    _lastLinkTime = now;

    debugPrint("Incoming Deep Link: $uri");

    final isRecordScheme = uri.scheme == 'whisperflow' &&
        (uri.host == 'record' || uri.path.contains('record'));

    if (!isRecordScheme) return;

    if (isRecordingActive) {
      // A RecordingScreen is already open (recording, stopping, or processing).
      if (onStopRecordingRequested != null) {
        // Still actively recording → this press means stop & save.
        debugPrint("Side button: stopping active recording");
        onStopRecordingRequested!();
      } else {
        // Already stopping/processing a previous take — ignore this press
        // instead of stacking a second RecordingScreen on top of it, which
        // would leave the old one stuck behind the new one indefinitely.
        debugPrint("Side button: ignored — a recording is still being processed");
      }
    } else {
      // No recording screen open → open a new one.
      debugPrint("Side button: starting new recording");
      isRecordingActive = true; // Block subsequent start triggers immediately
      Future.delayed(const Duration(milliseconds: 300), () {
        navigatorKey.currentState?.pushNamed('/record');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Peraj AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorKey: navigatorKey,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/record': (context) => const RecordingScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
