import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Set a timer to navigate to the appropriate screen after 3 seconds
    Timer(const Duration(seconds: 3), () {
      // Check if user is already signed in
      if (FirebaseAuth.instance.currentUser != null) {
        // User is signed in, go to home
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        // No user signed in, go to auth screen
        Navigator.of(context).pushReplacementNamed('/auth');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Define customizable dimensions
    final double horizontalPadding = 60.0;
    final double imageWidth = screenWidth - (horizontalPadding * 2);

    return Scaffold(
      backgroundColor: const Color(0xFFB9DBE4),
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding, 
          vertical: 40.0,
        ),
        child: Center(
          child: Image.asset(
            'assets/images/lexi_splash.png',
            width: imageWidth,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}