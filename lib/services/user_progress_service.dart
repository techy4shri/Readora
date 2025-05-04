import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

enum DifficultyLevel {
  easy,
  medium,
  hard
}

class UserProgressService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Timer for periodic level check
  static Timer? _levelCheckTimer;
  
  // Stream controller to broadcast level changes
  static final _levelStreamController = StreamController<DifficultyLevel>.broadcast();
  static Stream<DifficultyLevel> get levelStream => _levelStreamController.stream;
  
  // Initialize the service and start periodic level check
  static void initialize() {
    // Start the periodic level check timer (every 1 minute)
    _levelCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      checkAndUpdateUserLevel();
    });
  }
  
  // Clean up resources when app is closed
  static void dispose() {
    _levelCheckTimer?.cancel();
    _levelStreamController.close();
  }
  
  // Save individual exercise attempt
  static Future<void> saveExerciseAttempt({
    required String exerciseId,
    required String subExerciseId,
    required bool isCorrect,
    required int attemptCount,
    required String exerciseType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    // Get current date in YYYY-MM-DD format
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    
    // Reference to the attempt document
    final attemptRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('exerciseAttempts')
        .doc('${exerciseId}_${subExerciseId}_$dateStr');
    
    // Update or create the attempt document
    await attemptRef.set({
      'exerciseId': exerciseId,
      'subExerciseId': subExerciseId,
      'isCorrect': isCorrect,
      'attemptCount': attemptCount,
      'exerciseType': exerciseType,
      'timestamp': FieldValue.serverTimestamp(),
      'date': dateStr,
    });
    
    // Also update the aggregated user stats
    await _updateUserStats(isCorrect);
  }
  
  // Update user stats with the latest attempt
  static Future<void> _updateUserStats(bool isCorrect) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    // Get current date in YYYY-MM-DD format
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    
    // Reference to the user stats document
    final statsRef = _firestore
        .collection('userStats')
        .doc('${user.uid}_$dateStr');
    
    // Update the stats document
    await statsRef.set({
      'userId': user.uid,
      'date': dateStr,
      'totalAttempts': FieldValue.increment(1),
      'correctAttempts': isCorrect ? FieldValue.increment(1) : FieldValue.increment(0),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  
  // Get current user difficulty level
  static Future<DifficultyLevel> getUserLevel() async {
    final user = _auth.currentUser;
    if (user == null) return DifficultyLevel.medium; // Default level
    
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      
      if (userDoc.exists && userDoc.data()!.containsKey('difficultyLevel')) {
        final levelString = userDoc.data()!['difficultyLevel'] as String;
        
        // Parse level string to enum
        switch (levelString) {
          case 'easy':
            return DifficultyLevel.easy;
          case 'hard':
            return DifficultyLevel.hard;
          case 'medium':
          default:
            return DifficultyLevel.medium;
        }
      }
      
      // If no level is set, set default and return medium
      await _firestore.collection('users').doc(user.uid).update({
        'difficultyLevel': 'medium',
      });
      
      return DifficultyLevel.medium;
    } catch (e) {
      print('Error getting user level: $e');
      return DifficultyLevel.medium;
    }
  }
  
  // Update user difficulty level
  static Future<void> updateUserLevel(DifficultyLevel level) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    String levelString;
    
    switch (level) {
      case DifficultyLevel.easy:
        levelString = 'easy';
        break;
      case DifficultyLevel.hard:
        levelString = 'hard';
        break;
      case DifficultyLevel.medium:
      default:
        levelString = 'medium';
        break;
    }
    
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'difficultyLevel': levelString,
      });
      
      // Broadcast level change
      _levelStreamController.add(level);
      
      print('User level updated to: $levelString');
    } catch (e) {
      print('Error updating user level: $e');
    }
  }
  
  // Check user performance and update level accordingly
  static Future<void> checkAndUpdateUserLevel() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    try {
      // Get attempts from the last 7 days
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final weekAgoStr = "${weekAgo.year}-${weekAgo.month.toString().padLeft(2, '0')}-${weekAgo.day.toString().padLeft(2, '0')}";
      
      // Query user stats for the time period
      final statsQuery = await _firestore
          .collection('userStats')
          .where('userId', isEqualTo: user.uid)
          .where('date', isGreaterThanOrEqualTo: weekAgoStr)
          .get();
      
      // Calculate total stats
      int totalAttempts = 0;
      int correctAttempts = 0;
      
      for (var doc in statsQuery.docs) {
        totalAttempts += (doc.data()['totalAttempts'] as num).toInt();
        correctAttempts += (doc.data()['correctAttempts'] as num).toInt();
      }
      
      // Skip level check if not enough attempts
      if (totalAttempts < 10) {
        print('Not enough attempts to check level: $totalAttempts');
        return;
      }
      
      // Calculate success rate
      double successRate = totalAttempts > 0 
          ? (correctAttempts / totalAttempts) * 100 
          : 0.0;
      
      print('User success rate: $successRate% ($correctAttempts/$totalAttempts)');
      
      // Get current level
      final currentLevel = await getUserLevel();
      
      // Determine if level change is needed based on criteria
      DifficultyLevel newLevel;
      
      if (successRate <= 20.0) {
        // Move down a level if success rate is 20% or lower
        newLevel = currentLevel == DifficultyLevel.medium 
            ? DifficultyLevel.easy 
            : (currentLevel == DifficultyLevel.hard ? DifficultyLevel.medium : DifficultyLevel.easy);
      } else if (successRate >= 80.0) {
        // Move up a level if success rate is 80% or higher
        newLevel = currentLevel == DifficultyLevel.medium 
            ? DifficultyLevel.hard 
            : (currentLevel == DifficultyLevel.easy ? DifficultyLevel.medium : DifficultyLevel.hard);
      } else {
        // Stay at the same level for 20-80% success rate
        newLevel = currentLevel;
      }
      
      // Update level if changed
      if (newLevel != currentLevel) {
        print('Changing user level from $currentLevel to $newLevel');
        await updateUserLevel(newLevel);
      }
    } catch (e) {
      print('Error checking and updating user level: $e');
    }
  }
}