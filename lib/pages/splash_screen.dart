import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Add a slight delay to allow the splash screen to be visible
    Future.delayed(const Duration(seconds: 2), () {
      _checkUserStatus();
    });
  }

  Future<void> _checkUserStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      
      if (user != null) {
        // Check if user details are completed
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (!mounted) return;
        
        if (userDoc.exists && userDoc.data()?.containsKey('firstName') == true) {
          // User has completed profile - navigate to MainScaffold
          Navigator.of(context).pushReplacementNamed('/main');
        } else {
          // User needs to complete profile
          Navigator.of(context).pushReplacementNamed('/user_details');
        }
      } else {
        // No logged-in user
        Navigator.of(context).pushReplacementNamed('/auth');
      }
    } catch (e) {
      print('Error in splash screen: $e');
      // On error, go to auth screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/auth');
      }
    }
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