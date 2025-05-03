import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

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
  List<ImageOption>? imageOptions;

  PracticeModule({
    required this.id,
    required this.title,
    required this.type,
    required this.content,
    this.completed = false,
    required this.createdAt,
    this.difficulty = 1,
    this.imageOptions,
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
      'imageOptions': imageOptions?.map((e) => e.toJson()).toList(),
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
      imageOptions: map['imageOptions'] != null
          ? List<ImageOption>.from(
              map['imageOptions'].map((x) => ImageOption.fromJson(x)))
          : null,
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
    List<ImageOption>? imageOptions,
  }) {
    return PracticeModule(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      content: content ?? this.content,
      completed: completed ?? this.completed,
      createdAt: createdAt ?? this.createdAt,
      difficulty: difficulty ?? this.difficulty,
      imageOptions: imageOptions ?? this.imageOptions,
    );
  }
}

class ImageOption {
  final String id;
  final String imageUrl;
  final String word;

  ImageOption({
    required this.id,
    required this.imageUrl,
    required this.word,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageUrl': imageUrl,
        'word': word,
      };

  factory ImageOption.fromJson(Map<String, dynamic> json) {
    return ImageOption(
      id: json['id'],
      imageUrl: json['imageUrl'],
      word: json['word'],
    );
  }
}

class CustomPracticeService {
  static final _projectId = dotenv.env['VERTEX_PROJECT_ID'] ?? '';
  static final _location = dotenv.env['VERTEX_LOCATION'] ?? 'us-central1';
  static final _modelId = 'gemini-1.5-pro-001'; // Using full model name with version
  static String? _accessToken;
  static DateTime? _tokenExpiry;
  
  // Get service account credentials from a file
  static Future<ServiceAccountCredentials> _getCredentials() async {
    final directory = await getApplicationDocumentsDirectory();
    final credentialsPath = '${directory.path}/service-account.json';
    final file = File(credentialsPath);
    
    // Check if credentials file exists
    if (!await file.exists()) {
      throw Exception('Service account credentials file not found at: $credentialsPath');
    }
    
    final jsonString = await file.readAsString();
    final jsonMap = json.decode(jsonString);
    return ServiceAccountCredentials.fromJson(jsonMap);
  }

  // Get OAuth2 access token
  static Future<String> _getAccessToken() async {
    // Check if we have a valid token already
    if (_accessToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      print("DEBUG: Using cached access token");
      return _accessToken!;
    }
    
    try {
      print("DEBUG: Getting fresh access token");
      final credentials = await _getCredentials();
      
      // Define the scopes needed for Vertex AI
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      
      // Get the HTTP client with OAuth2 credentials
      final client = await clientViaServiceAccount(credentials, scopes);
      
      // Store the token and its expiry
      _accessToken = client.credentials.accessToken.data;
      _tokenExpiry = client.credentials.accessToken.expiry;
      
      print("DEBUG: Successfully obtained fresh access token, expires at: $_tokenExpiry");
      return _accessToken!;
    } catch (e) {
      print("ERROR: Failed to get access token: $e");
      throw Exception('Failed to authenticate with Vertex AI: $e');
    }
  }

  // Method to get authentication headers with token
  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await _getAccessToken();
    print("DEBUG: Got auth headers with token");
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Get the Vertex AI endpoint for Gemini
  static String get _endpoint {
    print("DEBUG: Constructing endpoint with project=$_projectId, location=$_location, model=$_modelId");
    // For Gemini models, use the generateContent endpoint
    final endpoint = 'https://$_location-aiplatform.googleapis.com/v1/projects/$_projectId/locations/$_location/publishers/google/models/$_modelId:generateContent';
    print("DEBUG: Endpoint: $endpoint");
    return endpoint;
  }
  
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

      // Generate personalized practices using Vertex AI
      return await _generatePracticesWithGemini(combinedAnalyses);
    } catch (e) {
      print('Error generating custom practices: $e');
      return _createDefaultPractices();
    }
  }

  // Generate practices using Vertex AI API
  static Future<List<PracticeModule>> _generatePracticesWithGemini(
      Map<String, String> analyses) async {
    try {
      // Create a unique generation ID for this request
      final randomSeed = DateTime.now().millisecondsSinceEpoch;
      
      // Create the prompt for Vertex AI
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

      Important: Generate different content each time, including ${DateTime.now().toIso8601String()} as a timestamp to ensure uniqueness.
      Generation ID: $randomSeed
      ''';

      // Get headers with OAuth token
      final headers = await _getAuthHeaders();
      
      // Prepare request body for Gemini model in Vertex AI with randomness
      final requestBody = jsonEncode({
        "contents": [
          {
            "role": "user",
            "parts": [
              {
                "text": prompt
              }
            ]
          }
        ],
        "generationConfig": {
          "temperature": 0.7, // Increase temperature for more variety
          "maxOutputTokens": 1024,
          "topK": 40,
          "topP": 0.95
        }
      });
      
      print("DEBUG: Sending request to Vertex AI");
      print("DEBUG: Full request body: $requestBody");
      
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: headers,
        body: requestBody,
      );
      
      if (response.statusCode != 200) {
        print("DEBUG: ⚠️ Error response: ${response.statusCode}");
        print("DEBUG: ⚠️ Headers: ${response.headers}");
        print("DEBUG: ⚠️ Full error body: ${response.body}");
        throw Exception("API call failed with status code: ${response.statusCode}");
      }
      
      final responseData = jsonDecode(response.body);
      
      // Extract text from Gemini response format in Vertex AI
      String responseText = "";
      if (responseData.containsKey('candidates') && 
          responseData['candidates'] is List && 
          responseData['candidates'].isNotEmpty) {
        
        print("DEBUG: Found candidates in response");
        
        var candidate = responseData['candidates'][0];
        if (candidate.containsKey('content') && 
            candidate['content'].containsKey('parts') && 
            candidate['content']['parts'] is List && 
            candidate['content']['parts'].isNotEmpty) {
          
          responseText = candidate['content']['parts'][0]['text'] ?? '';
          print("DEBUG: Extracted text of length: ${responseText.length}");
          print("DEBUG: First 100 chars: ${responseText.substring(0, min(100, responseText.length))}...");
        } else {
          print("DEBUG: ⚠️ Unexpected candidate format");
          print("DEBUG: ⚠️ Candidate: $candidate");
        }
      } else {
        print("DEBUG: ⚠️ No candidates found in response");
        throw Exception('Invalid response format from Vertex AI');
      }

      // Extract JSON from the response - improve the regex to be more robust
      final jsonRegex = RegExp(r'\[\s*\{.*?\}\s*\]', dotAll: true);
      final match = jsonRegex.firstMatch(responseText);
      
      if (match == null) {
        print("DEBUG: ⚠️ No JSON found in response text");
        print("DEBUG: ⚠️ Response text: $responseText");
        
        // Alternative approach - try to find JSON anywhere in the text
        final anyJsonMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(responseText);
        
        if (anyJsonMatch != null) {
          try {
            final jsonString = anyJsonMatch.group(0);
            print("DEBUG: Found alternative JSON: ${jsonString?.substring(0, min(100, jsonString?.length ?? 0))}...");
            final List<dynamic> jsonData = json.decode(jsonString!);
            
            // Convert to PracticeModule objects
            return _createPracticesFromJsonData(jsonData);
          } catch (e) {
            print("DEBUG: ⚠️ Failed to parse alternative JSON: $e");
            throw Exception('Could not extract valid JSON from response');
          }
        } else {
          throw Exception('Could not extract valid JSON from response');
        }
      }
      
      final jsonString = match.group(0);
      final List<dynamic> jsonData = json.decode(jsonString!);
      
      return _createPracticesFromJsonData(jsonData);
    } catch (e) {
      print('Error with Vertex AI API: $e');
      return _createDefaultPractices();
    }
  }
  
  // Helper method to create practice modules from JSON data
  static List<PracticeModule> _createPracticesFromJsonData(List<dynamic> jsonData) {
    // Convert to PracticeModule objects
    List<PracticeModule> practices = [];
    
    for (var item in jsonData) {
      try {
        // Convert the "type" string to PracticeType enum
        final typeStr = item['type'] as String;
        final type = PracticeType.values.firstWhere(
          (e) => e.toString().split('.').last == typeStr,
          orElse: () => PracticeType.letterWriting,
        );
        
        final practice = PracticeModule(
          id: 'practice_${DateTime.now().millisecondsSinceEpoch}_${practices.length}',
          title: item['title'],
          type: type,
          content: List<String>.from(item['content']),
          completed: false,
          createdAt: DateTime.now(),
          difficulty: item['difficulty'] ?? 1,
        );

        // When creating sentence writing exercises, add image options
        if (practice.type == PracticeType.sentenceWriting) {
          practice.imageOptions = [
            ImageOption(
              id: 'img1',
              imageUrl: 'https://example.com/image1.jpg',
              word: 'example',
            ),
            // Add more image options
          ];
        }

        practices.add(practice);
      } catch (e) {
        print("DEBUG: Error creating practice module: $e");
        // Continue to next item
      }
    }
    
    // Ensure we have at most 5 practices
    return practices.take(5).toList();
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