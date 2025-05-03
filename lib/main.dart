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

void main() async {
  await dotenv.load();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
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