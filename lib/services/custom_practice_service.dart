import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

// Types of practices
enum PracticeType {
  letterWriting,
  sentenceWriting,
  phonetic,
  letterReversal,
  vowelSounds
}

// Model for a practice module
class PracticeModule {
  final String id;
  final String title;
  final PracticeType type;
  final List<String> content;
  final bool completed;
  final DateTime createdAt;
  final int difficulty; // 1-5 scale

  PracticeModule({
    required this.id,
    required this.title,
    required this.type,
    required this.content,
    this.completed = false,
    required this.createdAt,
    this.difficulty = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type.toString().split('.').last,
      'content': content,
      'completed': completed,
      'createdAt': createdAt,
      'difficulty': difficulty,
    };
  }

  factory PracticeModule.fromMap(Map<String, dynamic> map) {
    return PracticeModule(
      id: map['id'],
      title: map['title'],
      type: PracticeType.values.firstWhere(
        (e) => e.toString().split('.').last == map['type'],
        orElse: () => PracticeType.letterWriting,
      ),
      content: List<String>.from(map['content']),
      completed: map['completed'] ?? false,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      difficulty: map['difficulty'] ?? 1,
    );
  }

  // Create a copy of this practice with updated fields
  PracticeModule copyWith({
    String? id,
    String? title,
    PracticeType? type,
    List<String>? content,
    bool? completed,
    DateTime? createdAt,
    int? difficulty,
  }) {
    return PracticeModule(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      content: content ?? this.content,
      completed: completed ?? this.completed,
      createdAt: createdAt ?? this.createdAt,
      difficulty: difficulty ?? this.difficulty,
    );
  }
}

class CustomPracticeService {
  static final _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  static final _model = GenerativeModel(model: 'gemini-1.5-pro', apiKey: _apiKey);
  
  // Fetch user's recent test results
  static Future<List<Map<String, dynamic>>> _fetchRecentTestResults() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('test_results')
          .orderBy('timestamp', descending: true)
          .limit(3) // Get the most recent 3 tests
          .get();

      return querySnapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('Error fetching test results: $e');
      return [];
    }
  }

  // Generate custom practice modules based on test results
  static Future<List<PracticeModule>> generateCustomPractices() async {
    try {
      // Fetch recent test results
      final testResults = await _fetchRecentTestResults();
      if (testResults.isEmpty) {
        // Return default practices if no test results
        return _createDefaultPractices();
      }

      // Extract patterns from test results
      List<String> writtenAnalyses = [];
      List<String> speechAnalyses = [];
      List<String> recommendations = [];

      for (var test in testResults) {
        writtenAnalyses.add(test['writtenAnalysis'] ?? '');
        speechAnalyses.add(test['speechAnalysis'] ?? '');
        recommendations.add(test['recommendations'] ?? '');
      }

      // Combine analyses for prompt
      final combinedAnalyses = {
        'writtenAnalysis': writtenAnalyses.join('\n\n'),
        'speechAnalysis': speechAnalyses.join('\n\n'),
        'recommendations': recommendations.join('\n\n'),
      };

      // Generate personalized practices using Gemini
      return await _generatePracticesWithGemini(combinedAnalyses);
    } catch (e) {
      print('Error generating custom practices: $e');
      return _createDefaultPractices();
    }
  }

  // Generate practices using Gemini API
  static Future<List<PracticeModule>> _generatePracticesWithGemini(
      Map<String, String> analyses) async {
    try {
      // Create the prompt for Gemini
      final prompt = '''
      # Dyslexia Practice Module Generation

      ## User's Analysis Data
      ### Written Analysis:
      ${analyses['writtenAnalysis']}

      ### Speech Analysis:
      ${analyses['speechAnalysis']}

      ### Recommendations:
      ${analyses['recommendations']}

      ## Task
      Create 5 personalized practice modules for this user based on their dyslexia test results. 
      Each module should target a specific pattern or challenge identified in the analysis.

      ## Requirements
      For each practice module, provide the following in JSON format:
      
      ```json
      [
        {
          "title": "Short descriptive title",
          "type": "One of: letterWriting, sentenceWriting, phonetic, letterReversal, vowelSounds",
          "content": ["Item 1", "Item 2", "Item 3", "Item 4", "Item 5"],
          "difficulty": number from 1-5
        },
        ...
      ]
      ```

      For the "content" field:
      - For letterWriting: Include 5 letters the user struggles with
      - For sentenceWriting: Include 5 sentences with challenging patterns
      - For phonetic: Include 5 words that target difficult sounds
      - For letterReversal: Include 5 pairs of easily confused letters/words
      - For vowelSounds: Include 5 words with challenging vowel sounds

      Keep content appropriate for age 7-12 reading level. Focus on specific patterns found in their test results.
      ''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      final responseText = response.text ?? '';

      // Extract JSON from the response
      final jsonRegex = RegExp(r'\[\s*\{.*?\}\s*\]', dotAll: true);
      final match = jsonRegex.firstMatch(responseText);
      
      if (match == null) {
        throw Exception('Could not extract valid JSON from response');
      }
      
      final jsonString = match.group(0);
      final List<dynamic> jsonData = json.decode(jsonString!);
      
      // Convert to PracticeModule objects
      List<PracticeModule> practices = [];
      
      for (var item in jsonData) {
        // Convert the "type" string to PracticeType enum
        final typeStr = item['type'] as String;
        final type = PracticeType.values.firstWhere(
          (e) => e.toString().split('.').last == typeStr,
          orElse: () => PracticeType.letterWriting,
        );
        
        practices.add(PracticeModule(
          id: 'practice_${DateTime.now().millisecondsSinceEpoch}_${practices.length}',
          title: item['title'],
          type: type,
          content: List<String>.from(item['content']),
          completed: false,
          createdAt: DateTime.now(),
          difficulty: item['difficulty'] ?? 1,
        ));
      }
      
      // Ensure we have at most 5 practices
      return practices.take(5).toList();
    } catch (e) {
      print('Error with Gemini API: $e');
      return _createDefaultPractices();
    }
  }

  // Save practices to Firestore
  static Future<void> savePractices(List<PracticeModule> practices) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }
      
      // Get a batch write instance
      final batch = FirebaseFirestore.instance.batch();
      
      // First, delete existing practices to avoid duplicates
      final existingPractices = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('practice_modules')
          .get();
          
      for (var doc in existingPractices.docs) {
        batch.delete(doc.reference);
      }
      
      // Add new practices
      for (var practice in practices) {
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('practice_modules')
            .doc(practice.id);
            
        batch.set(docRef, practice.toMap());
      }
      
      // Commit the batch
      await batch.commit();
    } catch (e) {
      print('Error saving practices: $e');
    }
  }

  // Fetch practices from Firestore
  static Future<List<PracticeModule>> fetchPractices() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('practice_modules')
          .orderBy('createdAt', descending: true)
          .get();

      if (querySnapshot.docs.isEmpty) {
        // No practices found, create and save default ones
        final defaults = _createDefaultPractices();
        await savePractices(defaults);
        return defaults;
      }

      return querySnapshot.docs
          .map((doc) => PracticeModule.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('Error fetching practices: $e');
      return _createDefaultPractices();
    }
  }

  // Mark a practice as completed
  static Future<void> markPracticeCompleted(String practiceId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('practice_modules')
          .doc(practiceId)
          .update({'completed': true});
    } catch (e) {
      print('Error marking practice as completed: $e');
    }
  }

  // Create default practices when no test data is available
  static List<PracticeModule> _createDefaultPractices() {
    return [
      PracticeModule(
        id: 'default_letter_writing',
        title: 'Letter Practice',
        type: PracticeType.letterWriting,
        content: ['b', 'd', 'p', 'q', 'm'],
        completed: false,
        createdAt: DateTime.now(),
        difficulty: 1,
      ),
      PracticeModule(
        id: 'default_sentence_writing',
        title: 'Sentence Writing',
        type: PracticeType.sentenceWriting,
        content: [
          'The dog ran to the park.',
          'She went to the store today.',
          'They played games after school.',
          'We saw birds in the tree.',
          'He likes to read books.'
        ],
        completed: false,
        createdAt: DateTime.now(),
        difficulty: 2,
      ),
      PracticeModule(
        id: 'default_phonetic',
        title: 'Sound Practice',
        type: PracticeType.phonetic,
        content: ['through', 'thought', 'strength', 'special', 'straight'],
        completed: false,
        createdAt: DateTime.now(),
        difficulty: 3,
      ),
      PracticeModule(
        id: 'default_reversal',
        title: 'Similar Words',
        type: PracticeType.letterReversal,
        content: ['was/saw', 'on/no', 'of/for', 'form/from', 'who/how'],
        completed: false,
        createdAt: DateTime.now(),
        difficulty: 2,
      ),
      PracticeModule(
        id: 'default_vowels',
        title: 'Vowel Sounds',
        type: PracticeType.vowelSounds,
        content: ['team', 'boat', 'night', 'house', 'food'],
        completed: false,
        createdAt: DateTime.now(),
        difficulty: 2,
      ),
    ];
  }
}