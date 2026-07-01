import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

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

  // Parse deep link and navigate
  void _handleDeepLink(Uri uri) {
    debugPrint("Incoming Deep Link: $uri");
    
    // Check if the scheme is whisperflow and target host is 'record'
    // This matches whisperflow://record
    final isRecordScheme = uri.scheme == 'whisperflow' && 
        (uri.host == 'record' || uri.path.contains('record'));

    if (isRecordScheme) {
      // Delay slightly to ensure Navigator is initialized if app is cold starting
      Future.delayed(const Duration(milliseconds: 500), () {
        navigatorKey.currentState?.pushNamed('/record');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whisperflow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorKey: navigatorKey, // Required for deep-link routing
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/record': (context) => const RecordingScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
