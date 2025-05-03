import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Helper method to convert errors to user-friendly messages
  String _getReadableErrorMessage(dynamic error) {
    // Check for empty fields first
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      return 'Please enter both email and password';
    }
    
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found with this email. Please sign up instead.';
        case 'wrong-password':
          return 'Incorrect password. Please try again';
        case 'invalid-email':
          return 'Please enter a valid email address';
        case 'user-disabled':
          return 'This account has been disabled';
        case 'email-already-in-use':
          return 'This email is already registered. Please sign in instead.';
        case 'operation-not-allowed':
          return 'Email/password accounts are not enabled';
        case 'weak-password':
          return 'Password is too weak. Please use at least 6 characters';
        case 'network-request-failed':
          return 'A network error occurred. Please check your connection and try again';
        case 'too-many-requests':
          return 'Access temporarily blocked due to many failed attempts. Please try again later';
        case 'invalid-credential':
          return 'The email or password is incorrect. Please try again';
        default:
          return 'Authentication error: ${error.code}. Please try again later';
      }
    } else if (error.toString().contains('socket')) {
      return 'Network error. Please check your internet connection and try again';
    } else if (error.toString().contains('timeout')) {
      return 'Connection timeout. Please try again later';
    }
    
    return 'An unexpected error occurred. Please try again later';
  }

  // Updated method with validation
  void _submitForm() {
    // Check for empty fields before even trying to authenticate
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both email and password'),
          // Using default color instead of bright red
        ),
      );
      return;
    }
    
    _signInWithEmailPassword();
  }

  // Check if user profile exists and redirect accordingly
  Future<void> _checkUserProfileAndRedirect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // Check if user document exists in Firestore
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    
    if (!mounted) return;
    
    if (userDoc.exists) {
      // User profile exists, go to main scaffold
      Navigator.of(context).pushReplacementNamed('/main');
    } else {
      // New user, go to profile setup
      Navigator.of(context).pushReplacementNamed('/user_details');
    }
  }

  // Updated Firebase Email/Password Authentication with better error handling
  Future<void> _signInWithEmailPassword() async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (_isLogin) {
        // Sign In
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        // Check if profile exists and redirect
        await _checkUserProfileAndRedirect();
      } else {
        // Sign Up
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        // New user, go to profile setup
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/user_details');
      }
    } catch (e) {
      // Show user-friendly error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getReadableErrorMessage(e)),
            // Using default color instead of bright red
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Updated Google Sign In with better error handling
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // Begin interactive sign in process
      final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
      
      if (gUser == null) {
        // User canceled the sign-in flow
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Get auth details from request
      final GoogleSignInAuthentication gAuth = await gUser.authentication;
      
      // Create new credential for user
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );
      
      // Sign in with credential
      await FirebaseAuth.instance.signInWithCredential(credential);
      
      // Check if profile exists and redirect
      await _checkUserProfileAndRedirect();
    } catch (e) {
      // Handle specific Google Sign In errors
      String errorMessage;
      
      if (e.toString().contains('network')) {
        errorMessage = 'A network error occurred. Please check your connection and try again.';
      } else if (e.toString().contains('canceled')) {
        errorMessage = 'Sign in was canceled';
      } else if (e is FirebaseAuthException) {
        errorMessage = _getReadableErrorMessage(e);
      } else {
        errorMessage = 'Failed to sign in with Google. Please try again later.';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Image.asset(
                  'assets/images/lexi_rain_temp.jpeg',
                  height: 150,
                ),
                const SizedBox(height: 20),
                Text(
                  _isLogin ? 'Welcome Back' : 'Create Account',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF324259),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isLogin ? 'Sign In' : 'Sign Up',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR'),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: Image.asset(
                    'assets/images/google_logo.png', 
                    height: 24,
                  ),
                  label: const Text('Sign in with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading ? null : () {
                    setState(() {
                      _isLogin = !_isLogin;
                    });
                  },
                  child: Text(
                    _isLogin 
                        ? 'Don\'t have an account? Sign Up' 
                        : 'Already have an account? Sign In',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}