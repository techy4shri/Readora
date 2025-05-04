import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DifficultyLevel {
  easy,
  medium,
  hard
}

class UserLevelService {
  // Singleton pattern
  static final UserLevelService _instance = UserLevelService._internal();
  factory UserLevelService() => _instance;
  UserLevelService._internal();
  
  // Difficulty level constants
  static const int easyLevel = 0;
  static const int mediumLevel = 1;
  static const int hardLevel = 2;
  
  // Thresholds for level changes
  static const double lowerThreshold = 0.2;  // 20% correct to move down
  static const double maintainThreshold = 0.5;  // 50% correct to stay at same level
  static const double upperThreshold = 0.8;  // 80% correct to move up
  
  // State variables
  Timer? _levelCheckTimer;
  int _currentLevel = mediumLevel; // Default to medium
  
  // Stream controller for level updates
  final _levelStreamController = StreamController<int>.broadcast();
  Stream<int> get levelStream => _levelStreamController.stream;
  
  // Initialize service
  Future<void> initialize() async {
    try {
      await _loadCurrentLevel();
      _startPeriodicLevelCheck();
    } catch (e) {
      print('Error initializing UserLevelService: $e');
    }
  }
  
  // Load user's current level from SharedPreferences or Firestore
  Future<void> _loadCurrentLevel() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Use localStorage if no user is signed in
        final prefs = await SharedPreferences.getInstance();
        _currentLevel = prefs.getInt('user_difficulty_level') ?? mediumLevel;
        return;
      }
      
      // Try to get from Firestore first
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
          
      if (docSnap.exists && docSnap.data()!.containsKey('difficultyLevel')) {
        _currentLevel = docSnap.data()!['difficultyLevel'];
      } else {
        // Use localStorage as backup
        final prefs = await SharedPreferences.getInstance();
        _currentLevel = prefs.getInt('user_difficulty_level') ?? mediumLevel;
      }
      
      // Notify listeners
      _levelStreamController.add(_currentLevel);
      print('Loaded user difficulty level: $_currentLevel');
    } catch (e) {
      print('Error loading difficulty level: $e');
      // Default to medium if there's an error
      _currentLevel = mediumLevel;
    }
  }
  
  // Save current level both locally and to Firestore
  Future<void> _saveCurrentLevel() async {
    try {
      // Save locally first
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_difficulty_level', _currentLevel);
      
      // Then save to Firestore if user is logged in
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'difficultyLevel': _currentLevel});
      }
      
      // Notify listeners
      _levelStreamController.add(_currentLevel);
      print('Saved user difficulty level: $_currentLevel');
    } catch (e) {
      print('Error saving difficulty level: $e');
    }
  }
  
  // Get current level
  int get currentLevel => _currentLevel;
  
  // Get current level as enum
  DifficultyLevel get currentDifficultyLevel {
    switch (_currentLevel) {
      case easyLevel:
        return DifficultyLevel.easy;
      case hardLevel:
        return DifficultyLevel.hard;
      case mediumLevel:
      default:
        return DifficultyLevel.medium;
    }
  }
  
  // Start periodic level check (every 1 minute)
  void _startPeriodicLevelCheck() {
    _levelCheckTimer?.cancel();
    _levelCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      checkAndUpdateLevel();
    });
    print('Started periodic level check timer');
  }
  
  // Record an exercise attempt
  Future<void> recordExerciseAttempt({
    required String exerciseId, 
    required bool isCorrect,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final timestamp = DateTime.now();
      final dateStr = _formatDate(timestamp);
      
      // Add to exercise_attempts collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('exercise_attempts')
          .add({
            'exerciseId': exerciseId,
            'isCorrect': isCorrect,
            'timestamp': timestamp,
            'dateStr': dateStr,
            'difficultyLevel': _currentLevel,
          });
          
      print('Recorded exercise attempt: $exerciseId, correct: $isCorrect');
    } catch (e) {
      print('Error recording exercise attempt: $e');
    }
  }
  
  // Format date as YYYY-MM-DD
  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
  
  // Check success rate and update level if needed
  Future<void> checkAndUpdateLevel() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Get all attempts from the last 3 days
      final now = DateTime.now();
      final threeDaysAgo = now.subtract(const Duration(days: 3));
      
      // Convert to Firestore timestamps
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('exercise_attempts')
          .where('timestamp', isGreaterThan: threeDaysAgo)
          .get();
          
      // Check if we have enough data to make a decision
      final attempts = querySnapshot.docs;
      if (attempts.isEmpty) {
        print('Not enough exercise attempts to evaluate level');
        return;
      }
      
      // Calculate success rate
      int totalAttempts = attempts.length;
      int correctAttempts = attempts.where((doc) => doc.data()['isCorrect'] == true).length;
      double successRate = correctAttempts / totalAttempts;
      
      print('User success rate: $successRate ($correctAttempts/$totalAttempts)');
      
      // Determine if level should change
      int newLevel = _currentLevel;
      
      if (successRate <= lowerThreshold) {
        // Move down a level if not already at lowest
        if (_currentLevel > easyLevel) {
          newLevel = _currentLevel - 1;
        }
      } else if (successRate >= upperThreshold) {
        // Move up a level if not already at highest
        if (_currentLevel < hardLevel) {
          newLevel = _currentLevel + 1;
        }
      }
      // Between thresholds - stay at current level
      
      // Update level if it changed
      if (newLevel != _currentLevel) {
        _currentLevel = newLevel;
        await _saveCurrentLevel();
        print('Updated difficulty level to: $_currentLevel');
      }
    } catch (e) {
      print('Error checking and updating level: $e');
    }
  }
  
  // Force level update (for testing)
  Future<void> setLevel(int level) async {
    if (level >= easyLevel && level <= hardLevel) {
      _currentLevel = level;
      await _saveCurrentLevel();
    }
  }
  
  // Clean up resources
  void dispose() {
    _levelCheckTimer?.cancel();
    _levelStreamController.close();
  }
} 