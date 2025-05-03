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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Ensure the service account file is available
  await ensureServiceAccountExists();
  
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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