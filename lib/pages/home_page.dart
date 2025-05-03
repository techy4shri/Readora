import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'package:readora/services/custom_practice_service.dart';
import 'package:readora/services/practice_stats_service.dart';
import 'practice_screen.dart';

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
  List<PracticeModule> _dailyPractices = [];
  final List<Map<String, dynamic>> _popularModules = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadPracticeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _loadPracticeData() async {
    try {
      // First try to fetch existing practices
      final practices = await CustomPracticeService.fetchPractices();
      
      // If no practices or it's been more than 7 days since last generation,
      // generate new practices
      if (practices.isEmpty || _shouldRefreshPractices(practices)) {
        final newPractices = await CustomPracticeService.generateCustomPractices();
        await CustomPracticeService.savePractices(newPractices);
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

      // Load popular modules (static for now)
      setState(() {
        _popularModules.addAll([
          {
            'id': 'cards_basic',
            'title': 'Basic Cards',
            'description': 'Practice with basic flashcards',
            'popularity': 98,
          },
          {
            'id': 'pronunciation',
            'title': 'Pronunciation',
            'description': 'Improve your accent',
            'popularity': 87,
          },
        ]);
      });
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

  bool _shouldRefreshPractices(List<PracticeModule> practices) {
    if (practices.isEmpty) return true;
    
    // Find the most recent practice
    final latestPractice = practices.reduce((a, b) => 
      a.createdAt.isAfter(b.createdAt) ? a : b);
      
    // If it's been more than 7 days since the last practice was created, refresh
    return DateTime.now().difference(latestPractice.createdAt).inDays > 7;
  }

  int _countCompletedPractices(List<PracticeModule> practices) {
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
      child: Row(
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
                  ? 'assets/images/lexi_content.jpeg'
                  : 'assets/images/lexi_sad.jpeg',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 14),
          
          // Mascot message
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPracticed 
                      ? '$greeting, $firstName!'
                      : 'Uh oh...',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF324259),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasPracticed
                      ? 'You have completed $_practicesDoneToday out of ${_dailyPractices.length} exercises today.'
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
    );
  }

  // Helper function to get icon based on practice type
  IconData _getPracticeIcon(PracticeType type) {
    switch (type) {
      case PracticeType.letterWriting:
        return Icons.text_fields;
      case PracticeType.sentenceWriting:
        return Icons.short_text;
      case PracticeType.phonetic:
        return Icons.record_voice_over;
      case PracticeType.letterReversal:
        return Icons.compare_arrows;
      case PracticeType.vowelSounds:
        return Icons.volume_up;
      default:
        return Icons.school;
    }
  }

  Widget _buildDailyPractices() {
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
                final newPractices = await CustomPracticeService.generateCustomPractices();
                await CustomPracticeService.savePractices(newPractices);
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
      
      // Practice items row - increased height and width
      SizedBox(
        height: 150, // Increased from 110
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
                      width: 120, // Increased from 90
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
                            width: 50, // Increased from 40
                            height: 50, // Increased from 40
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getPracticeIcon(practice.type),
                              color: practice.completed 
                                  ? Colors.green 
                                  : const Color(0xFF324259),
                              size: 26, // Slightly larger icon
                            ),
                          ),
                          const SizedBox(height: 8), // Increased from 8
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8), // Increased from 4
                            child: Text(
                              practice.title,
                              style: const TextStyle(
                                fontSize: 13, // Increased from 12
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 8), // Added spacing
                          if (practice.completed)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18, // Increased from 16
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
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF324259),
          ),
        ),
        const SizedBox(height: 12),
        
        // Cards module
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFE0E0E0),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Cards',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF324259),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Practice with flashcards',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF324259).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Personalized',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF324259),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
                          onTap: () {
                            Navigator.pushNamed(context, '/settings');
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
                                      'assets/images/avatar${_userData!['avatarIndex'] + 1}.png',
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
                          
                          // Statistics/Insights section
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE0E0E0),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.insert_chart_outlined,
                                        color: Color(0xFF324259),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Statistics',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF324259),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE0E0E0),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.lightbulb_outline,
                                        color: Color(0xFF324259),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Insights',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF324259),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
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