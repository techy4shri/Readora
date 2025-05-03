import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PracticeStats {
  final int totalCompleted;
  final int streak; // Days in a row with completed practices
  final DateTime lastPracticeDate;
  final Map<String, int> practiceTypeBreakdown;
  
  PracticeStats({
    this.totalCompleted = 0,
    this.streak = 0,
    required this.lastPracticeDate,
    required this.practiceTypeBreakdown,
  });
  
  factory PracticeStats.fromMap(Map<String, dynamic> map) {
    return PracticeStats(
      totalCompleted: map['totalCompleted'] ?? 0,
      streak: map['streak'] ?? 0,
      lastPracticeDate: (map['lastPracticeDate'] as Timestamp).toDate(),
      practiceTypeBreakdown: Map<String, int>.from(map['practiceTypeBreakdown'] ?? {}),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'totalCompleted': totalCompleted,
      'streak': streak,
      'lastPracticeDate': lastPracticeDate,
      'practiceTypeBreakdown': practiceTypeBreakdown,
    };
  }
}

class PracticeStatsService {
  static Future<PracticeStats> getUserStats() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }
      
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('stats')
          .doc('practice_stats')
          .get();
          
      if (!docSnapshot.exists) {
        // Create default stats if none exist
        final defaultStats = PracticeStats(
          totalCompleted: 0,
          streak: 0,
          lastPracticeDate: DateTime.now().subtract(const Duration(days: 1)),
          practiceTypeBreakdown: {},
        );
        
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('stats')
            .doc('practice_stats')
            .set(defaultStats.toMap());
            
        return defaultStats;
      }
      
      return PracticeStats.fromMap(docSnapshot.data()!);
    } catch (e) {
      print('Error getting user stats: $e');
      // Return default stats if there's an error
      return PracticeStats(
        totalCompleted: 0,
        streak: 0,
        lastPracticeDate: DateTime.now().subtract(const Duration(days: 1)),
        practiceTypeBreakdown: {},
      );
    }
  }
  
  static Future<void> updateStatsAfterCompletion(String practiceType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }
      
      // Get current stats
      final currentStats = await getUserStats();
      
      // Today's date with time set to midnight for proper date comparison
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      
      // Last practice date with time set to midnight
      final lastDate = DateTime(
        currentStats.lastPracticeDate.year,
        currentStats.lastPracticeDate.month,
        currentStats.lastPracticeDate.day,
      );
      
      // Calculate difference in days
      final difference = today.difference(lastDate).inDays;
      
      // Update streak based on last practice date
      int newStreak = currentStats.streak;
      if (difference == 0) {
        // Already practiced today, streak doesn't change
        newStreak = currentStats.streak;
      } else if (difference == 1) {
        // Practiced yesterday, streak increases
        newStreak = currentStats.streak + 1;
      } else {
        // Missed a day, streak resets to 1
        newStreak = 1;
      }
      
      // Update practice type breakdown
      final typeBreakdown = Map<String, int>.from(currentStats.practiceTypeBreakdown);
      typeBreakdown[practiceType] = (typeBreakdown[practiceType] ?? 0) + 1;
      
      // Create updated stats
      final updatedStats = PracticeStats(
        totalCompleted: currentStats.totalCompleted + 1,
        streak: newStreak,
        lastPracticeDate: today,
        practiceTypeBreakdown: typeBreakdown,
      );
      
      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('stats')
          .doc('practice_stats')
          .set(updatedStats.toMap());
    } catch (e) {
      print('Error updating stats: $e');
    }
  }
  
  // Get practices completed today
  static Future<int> getPracticesCompletedToday() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }
      
      // Get today's date range
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      // Query completed practices within today's date range
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('practice_modules')
          .where('completed', isEqualTo: true)
          .where('lastCompletedAt', isGreaterThanOrEqualTo: startOfDay)
          .where('lastCompletedAt', isLessThan: endOfDay)
          .get();
          
      return querySnapshot.docs.length;
    } catch (e) {
      print('Error getting practices completed today: $e');
      return 0;
    }
  }
}