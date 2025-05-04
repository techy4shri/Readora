import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'package:readora/services/custom_practice_service.dart' as practice_service;
import 'package:readora/services/practice_stats_service.dart';
import 'package:readora/services/practice_module_service.dart'; // Import new service
import 'package:readora/services/user_level_service.dart'; // Add this import
import 'practice_screen.dart';
import 'module_details.dart'; // Renamed from practice_modules.dart for clarity
import 'user_settings.dart';  // Added import for UserSettingsScreen

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  int _practicesDoneToday = 0;
  int _modulesCompletedToday = 0;
  int _practicesCompletedToday = 0; // New field to track practice module completions
  List<practice_service.PracticeModule> _dailyPractices = [];
  List<PracticeModule> _popularModules = [];
  
  // Add difficulty level
  DifficultyLevel _difficultyLevel = DifficultyLevel.medium;
  final UserLevelService _userLevelService = UserLevelService();

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadUserData();
    _loadPracticeData();
    
    // Subscribe to module updates
    PracticeModuleService.moduleStream.listen((modules) {
      // Update popular modules when any module changes
      _loadPopularModules();
      // Also refresh modules completion count
      _loadModulesCompletedToday();
    });
    
    // Subscribe to difficulty level updates
    _userLevelService.levelStream.listen((level) {
      setState(() {
        _difficultyLevel = _userLevelService.currentDifficultyLevel;
      });
      // Refresh practices when level changes
      _loadPracticeData(forceRefresh: true);
    });
    
    // Refresh data when returning to this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCompletedPractices();
      // Save progress data at regular intervals
      _saveUserProgressData();
    });
  }

  @override
  void dispose() {
    _saveUserProgressData(); // Save progress when leaving the page
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    try {
      await _userLevelService.initialize();
      _difficultyLevel = _userLevelService.currentDifficultyLevel;
    } catch (e) {
      print('Error initializing services: $e');
    }
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (docSnapshot.exists) {
        setState(() {
          _userData = docSnapshot.data();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading user data: ${e.toString()}')),
      );
    } finally {
      // Don't set _isLoading to false here, as we're still loading practices
    }
  }

  Future<void> _loadPracticeData({bool forceRefresh = false}) async {
    try {
      // First load daily practices (from previous code)
      final practices = await practice_service.CustomPracticeService.fetchPractices();
      
      if (practices.isEmpty || _shouldRefreshPractices(practices) || forceRefresh) {
        final newPractices = await practice_service.CustomPracticeService.generateCustomPractices();
        await practice_service.CustomPracticeService.savePractices(newPractices);
        setState(() {
          _dailyPractices = newPractices;
          _practicesDoneToday = _countCompletedPractices(newPractices);
        });
      } else {
        setState(() {
          _dailyPractices = practices;
          _practicesDoneToday = _countCompletedPractices(practices);
        });
      }

      // Load popular modules from our new service
      await _loadPopularModules();
      
      // Load modules completed today
      await _loadModulesCompletedToday();
      
      // Load completed practices from Firebase
      await _loadCompletedPractices();
      
      // After loading all data, save the progress to track daily activity
      await _saveUserProgressData();
      
      // Check user's level
      await _userLevelService.checkAndUpdateLevel();
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading practices: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadPopularModules() async {
    try {
      final popularModules = await PracticeModuleService.getPopularModules();
      setState(() {
        _popularModules = popularModules;
      });
    } catch (e) {
      print('Error loading popular modules: $e');
    }
  }
  
  // New method to save daily progress to the database
  Future<void> _saveDailyProgress(List<practice_service.PracticeModule> practices) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Get yesterday's date as this is for the day that just ended
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final dateStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";
      
      // Count completed practices
      final completed = practices.where((practice) => practice.completed).length;
      final total = practices.length;
      
      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('dailyProgress')
          .doc('${user.uid}_$dateStr')
          .set({
            'userId': user.uid,
            'date': dateStr,
            'completed': completed,
            'total': total,
            'timestamp': FieldValue.serverTimestamp(),
          });
          
      print('Saved daily progress: $completed/$total for $dateStr');
    } catch (e) {
      print('Error saving daily progress: $e');
    }
  }

  // New method to load modules completed today
  Future<void> _loadModulesCompletedToday() async {
    try {
      final completedCount = await PracticeModuleService.getCompletedModulesToday();
      setState(() {
        _modulesCompletedToday = completedCount;
      });
    } catch (e) {
      print('Error loading completed modules: $e');
    }
  }

  // New method to load completed practices from Firebase
  Future<void> _loadCompletedPractices() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Get today's date in YYYY-MM-DD format
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      // Reference to the user's daily stats document
      final dailyStatsRef = FirebaseFirestore.instance
          .collection('userStats')
          .doc('${user.uid}_$dateStr');
      
      final docSnapshot = await dailyStatsRef.get();
      
      if (docSnapshot.exists && docSnapshot.data()!.containsKey('completedPractices')) {
        final completedPractices = docSnapshot.data()!['completedPractices'] as int;
        setState(() {
          _practicesCompletedToday = completedPractices;
        });
        print('Loaded $completedPractices completed practices for today');
      } else {
        setState(() {
          _practicesCompletedToday = 0;
        });
        print('No completed practices found for today');
      }
    } catch (e) {
      print('Error loading completed practices: $e');
    }
  }

  bool _shouldRefreshPractices(List<practice_service.PracticeModule> practices) {
    if (practices.isEmpty) return true;
    
    // Find the most recent practice
    final latestPractice = practices.reduce((a, b) => 
      a.createdAt.isAfter(b.createdAt) ? a : b);
      
    // If it's been more than 7 days since the last practice was created, refresh
    if (DateTime.now().difference(latestPractice.createdAt).inDays > 7) {
      _saveDailyProgress(practices); // Save progress before refreshing
      return true;
    }
    
    // Check if current date is different from the date when practices were created
    // This ensures practices refresh at 12am each day
    final today = DateTime.now();
    final createdDate = latestPractice.createdAt;
    
    final needsRefresh = today.year != createdDate.year || 
                         today.month != createdDate.month || 
                         today.day != createdDate.day;
    
    // If we need to refresh for a new day, save yesterday's progress first
    if (needsRefresh) {
      _saveDailyProgress(practices);
    }
    
    return needsRefresh;
  }

  int _countCompletedPractices(List<practice_service.PracticeModule> practices) {
    return practices.where((practice) => practice.completed).length;
  }

  Widget _buildMascot() {
    
    final bool hasPracticed = _practicesDoneToday > 0;
    final String firstName = _userData?['firstName'] ?? 'there';
    
    // Get the current hour to determine greeting
    final int currentHour = DateTime.now().hour;
    String greeting;
    
    if (currentHour < 12) {
      greeting = 'Good morning';
    } else if (currentHour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }
    
    // Get difficulty level text
    String difficultyText;
    Color difficultyColor;
    
    switch (_difficultyLevel) {
      case DifficultyLevel.easy:
        difficultyText = 'Easy';
        difficultyColor = Colors.green;
        break;
      case DifficultyLevel.hard:
        difficultyText = 'Hard';
        difficultyColor = Colors.red;
        break;
      case DifficultyLevel.medium:
      default:
        difficultyText = 'Medium';
        difficultyColor = Colors.blue;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Mascot image
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFEEF2F6),
                ),
                child: Image.asset(
                  hasPracticed 
                      ? 'assets/images/lexi_content.webp'
                      : 'assets/images/lexi_sad.webp',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 14),
              
              // Mascot message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasPracticed)
                      Text(
                        '$greeting, $firstName!',
                        style: const TextStyle(
                          fontSize: 22.0,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF324259),
                        ),
                      )
                    else
                      const Text(
                        'Uh oh...',
                        style: TextStyle(
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF324259),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      hasPracticed
                          ? ''
                          : "You haven't completed any practices today.",
                      style: TextStyle(
                        fontSize: 14,
                        color: hasPracticed ? Colors.green[700] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Add difficulty level indicator
          Container(
            margin: const EdgeInsets.only(top: 8, right: 14, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: difficultyColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: difficultyColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, size: 16, color: difficultyColor),
                const SizedBox(width: 4),
                Text(
                  'Current Level: $difficultyText',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: difficultyColor,
                  ),
                ),
              ],
            ),
          ),
          
          // Add modules and practices completed count if any
          if (_modulesCompletedToday > 0 || _practicesCompletedToday > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Column(
                children: [
                  // Show modules completed if any
                  if (_modulesCompletedToday > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber[700], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'You completed $_modulesCompletedToday ${_modulesCompletedToday == 1 ? 'module' : 'modules'} today!',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF324259),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // Show practices completed if any
                  if (_practicesCompletedToday > 0)
                    Container(
                      width: double.infinity,
                      margin: _modulesCompletedToday > 0 ? const EdgeInsets.only(top: 8.0) : EdgeInsets.zero,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'You completed $_practicesCompletedToday ${_practicesCompletedToday == 1 ? 'practice' : 'practices'} today!',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF324259),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Helper function to get icon based on practice type
  IconData _getPracticeIcon(practice_service.PracticeType type) {
    switch (type) {
      case practice_service.PracticeType.letterWriting:
        return Icons.text_fields;
      case practice_service.PracticeType.sentenceWriting:
        return Icons.short_text;
      case practice_service.PracticeType.phonetic:
        return Icons.record_voice_over;
      case practice_service.PracticeType.letterReversal:
        return Icons.compare_arrows;
      case practice_service.PracticeType.vowelSounds:
        return Icons.volume_up;
      default:
        return Icons.school;
    }
  }

  Widget _buildDailyPractices() {
    // Existing implementation remains the same
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Your daily practices',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF324259),
              ),
            ),
            TextButton(
              onPressed: () async {
                setState(() {
                  _isLoading = true;
                });
                try {
                  final newPractices = await practice_service.CustomPracticeService.generateCustomPractices();
                  await practice_service.CustomPracticeService.savePractices(newPractices);
                  setState(() {
                    _dailyPractices = newPractices;
                    _practicesDoneToday = _countCompletedPractices(newPractices);
                  });
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error refreshing practices: ${e.toString()}')),
                  );
                } finally {
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
              child: Text(
                'Refresh',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        
        // Practice items row
        SizedBox(
          height: 150,
          child: _dailyPractices.isEmpty
              ? const Center(child: Text('No practices available'))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _dailyPractices.length,
                  itemBuilder: (context, index) {
                    final practice = _dailyPractices[index];
                    return GestureDetector(
                      onTap: () {
                        // Navigate to practice screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PracticeScreen(practice: practice),
                          ),
                        ).then((_) => _loadPracticeData()); // Refresh when returning
                      },
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: practice.completed
                                ? Colors.green.withOpacity(0.5)
                                : const Color(0xFFE0E0E0),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getPracticeIcon(practice.type),
                                color: practice.completed 
                                    ? Colors.green 
                                    : const Color(0xFF324259),
                                size: 26,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                practice.title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (practice.completed)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
      ],
    );
  }

  Widget _buildPopularModules() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Popular exercise modules',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF324259),
          ),
        ),
        const SizedBox(height: 12),
        
        // Module cards in a horizontal scroll
        SizedBox(
          height: 170,
          child: _popularModules.isEmpty 
              ? const Center(child: Text('No modules available'))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _popularModules.length,
                  itemBuilder: (context, index) {
                    final module = _popularModules[index];
                    return Container(
                      width: MediaQuery.of(context).size.width * 0.70,
                      margin: const EdgeInsets.only(right: 16),
                      child: Card(
                        elevation: 2,
                        color: const Color.fromARGB(255, 233, 240, 252),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ModuleDetailScreen(
                                  module: module,
                                  onProgressUpdate: (completed) {
                                    // Update progress using the central service
                                    PracticeModuleService.updateModuleProgress(
                                      module.id, 
                                      completed
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        module.title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: module.type == ModuleType.written
                                            ? Colors.blue.withOpacity(0.2)
                                            : Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        module.type == ModuleType.written ? "Written" : "Speech",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: module.type == ModuleType.written
                                              ? Colors.blue
                                              : Colors.green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  module.description,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Spacer(),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Progress: ${module.completedExercises}/${module.totalExercises}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '${(module.progressPercentage * 100).toStringAsFixed(0)}%',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    LinearProgressIndicator(
                                      value: module.progressPercentage,
                                      backgroundColor: const Color.fromARGB(255, 205, 205, 206),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        module.progressPercentage == 1.0
                                            ? const Color.fromARGB(255, 84, 156, 86)
                                            : Colors.blue,
                                      ),
                                      minHeight: 5,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Save combined user progress to Firestore in user/progress collection
  Future<void> _saveUserProgressData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Get today's date in YYYY-MM-DD format
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      // Calculate total practices completed today (both types)
      final totalPracticesCompleted = _practicesDoneToday + _modulesCompletedToday + _practicesCompletedToday;
      
      // Reference to user's progress document
      final progressRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('progress')
          .doc(dateStr);
      
      // Update or create the progress document
      await progressRef.set({
        'date': dateStr,
        'practice_done': totalPracticesCompleted,
        'daily_practices': _practicesDoneToday,
        'modules_completed': _modulesCompletedToday,
        'practice_modules': _practicesCompletedToday,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // Use merge to update only these fields
      
      print('Saved user progress data for $dateStr: $totalPracticesCompleted total practices');
      
    } catch (e) {
      print('Error saving user progress data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Top bar with search and profile
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Search bar
                        Expanded(
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE0E0E0),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.search,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    decoration: const InputDecoration(
                                      hintText: 'Search',
                                      border: InputBorder.none,
                                      hintStyle: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 8.0),
                                    ),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        // Profile avatar
                        GestureDetector(
                          onTap: () async {
                            // Navigate to UserSettingsScreen and wait for result
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const UserSettingsScreen(),
                              ),
                            );
                            
                            // If changes were made (result is true), refresh user data
                            if (result == true) {
                              _loadUserData();
                            }
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF324259),
                                width: 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: _userData?['avatarIndex'] != null
                                  ? Image.asset(
                                      'assets/images/avatar${_userData!['avatarIndex'] + 1}.webp',
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(Icons.person),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Main content area with scrolling
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMascot(),
                          const SizedBox(height: 24),
                          _buildDailyPractices(),
                          const SizedBox(height: 24),
                          _buildPopularModules(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}