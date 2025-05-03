import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'pages/splash_screen.dart';
import 'pages/auth_screen.dart';
import 'pages/home_page.dart';
import 'pages/user_details.dart';
import 'pages/tests.dart';
import 'pages/practice_modules.dart';
import 'pages/dashboard.dart';
import 'pages/user_settings.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'pages/main_scaffold.dart'; 
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:readora/services/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Ensure the service account file is available
  await ensureServiceAccountExists();
  
  // Initialize the AudioService
  final audioService = AudioService();
  await audioService.initialize();
  
  runApp(const MyApp());
}

Future<void> ensureServiceAccountExists() async {
  final directory = await getApplicationDocumentsDirectory();
  final credentialsPath = '${directory.path}/service-account.json';
  final file = File(credentialsPath);
  
  if (!await file.exists()) {
    try {
      print("DEBUG: Service account file doesn't exist, copying from assets");
      // Load from assets
      final byteData = await rootBundle.load('assets/service-account.json');
      // Write to app directory
      await file.writeAsBytes(
          byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      print("DEBUG: Service account file copied successfully");
    } catch (e) {
      print("ERROR: Failed to setup service account file: $e");
    }
  } else {
    print("DEBUG: Service account file already exists");
  }
}

// Convert to StatefulWidget to handle app lifecycle
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final AudioService _audioService = AudioService();

  @override
  void initState() {
    super.initState();
    // Add observer to track app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    // Start playing background music when app launches
    _audioService.playBackgroundMusic();
  }

  @override
  void dispose() {
    // Clean up resources
    _audioService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive || 
        state == AppLifecycleState.detached) {
      // App is not in foreground - pause music
      _audioService.pauseBackgroundMusic();
    } else if (state == AppLifecycleState.resumed) {
      // App is in foreground again - resume music
      _audioService.playBackgroundMusic();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Readora',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF324259)),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/auth': (context) => const AuthScreen(),
        '/main': (context) => const MainScaffold(),
        '/user_details': (context) => const UserDetailsScreen(),
      },
    );
  }
}