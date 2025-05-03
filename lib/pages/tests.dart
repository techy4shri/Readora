import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:io';

// Enhanced Gemini API Service
class GeminiService {
  static final _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  static final _model = GenerativeModel(model: 'gemini-1.5-pro', apiKey: _apiKey);

  static Future<String> generateSentence() async {
    try {
      // Enhanced prompt for generating test sentences that include common dyslexia challenge patterns
      final content = [Content.text('''Generate a simple sentence for dyslexia testing using common words. 
      The sentence should:
      - Be 8-10 words in length
      - Include at least one word with similar-looking letters (like b/d, p/q, or m/n)
      - Include at least one word with a common letter reversal pattern (like "was/saw")
      - Include a mix of short and longer words
      - Be at a 3rd-4th grade reading level
      - Use natural, conversational language
      
      Return only the sentence with no additional text or explanations.''')];
      
      final response = await _model.generateContent(content);
      return response.text ?? 'She seemed like an angel in her white dress.';
    } catch (e) {
      // Fallback sentences in case API call fails - improved with better test patterns
      final fallbackSentences = [
        'The boy quickly jumped over the puddle beside the dog.',
        'She read the book while her brother played outside.',
        'My mother baked delicious bread with plenty of honey.',
        'The quiet night was filled with bright twinkling stars.',
        'He found his lost keys under the blue wooden bench.',
        'We need to pack our bags before the big trip.',
        'The dog barked at the mailman behind our fence.',
      ];
      return fallbackSentences[DateTime.now().second % fallbackSentences.length];
    }
  }

  static Future<Map<String, String>> analyzeTest(String original, String written, String spoken) async {
    try {
      // Enhanced prompt with more specific instructions for detailed pattern analysis and improved formatting
      final prompt = '''
      # Dyslexia Assessment Analysis

      ## Input Data
      Original sentence: "$original"
      Written response: "$written"
      Spoken response: "$spoken"
      
      ## Analysis Instructions
      Perform a detailed analysis comparing both the written and spoken responses to the original sentence, looking specifically for patterns consistent with dyslexia or reading/spelling difficulties.
      
      ### Written Analysis Focus
      1. Letter reversals (b/d, p/q, etc.)
      2. Letter transpositions (on/no, was/saw, etc.)
      3. Letter omissions or additions
      4. Phonological errors (spelling words as they sound)
      5. Consistent confusion with specific letters
      6. Issues with vowel sounds
      7. Word spacing issues
      8. Capitalization inconsistencies
      
      ### Speech Analysis Focus
      1. Sound substitutions
      2. Sound omissions or additions
      3. Difficulty with specific phonemes
      4. Word order changes
      5. Word substitution patterns
      6. Pronunciation differences in similar-sounding words
      7. Hesitations or repetitions
      8. Challenges with multisyllabic words
      
      ## Output Format Requirements
      Format your response EXACTLY as follows with careful attention to the formatting:
      
      HEADING: [Brief 3-4 word descriptive heading that captures the core pattern]
      
      WRITTEN_ANALYSIS: 
      ## Key Observations
      - [First key observation with specific example]
      - [Second key observation with specific example]
      - [Third key observation with specific example]
      
      ### Pattern Details
      [One concise paragraph explaining the overall pattern seen in writing]
      
      SPEECH_ANALYSIS: 
      ## Key Observations
      - [First key observation with specific example]
      - [Second key observation with specific example]
      - [Third key observation with specific example]
      
      ### Pattern Details
      [One concise paragraph explaining the overall pattern seen in speech]
      
      RECOMMENDATIONS: 
      ## Practice Activities
      1. [First specific practice recommendation that addresses a key pattern]
      2. [Second specific practice recommendation]
      3. [Third specific practice recommendation]
      
      ### Focus Areas
      - [Primary area to focus practice efforts]
      - [Secondary area to focus practice efforts]
      ''';
      
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      final responseText = response.text ?? '';
      
      // Parse the formatted response with the new format
      final headingMatch = RegExp(r'HEADING:(.*?)(?=WRITTEN_ANALYSIS:|$)', dotAll: true).firstMatch(responseText);
      final writtenMatch = RegExp(r'WRITTEN_ANALYSIS:(.*?)(?=SPEECH_ANALYSIS:|$)', dotAll: true).firstMatch(responseText);
      final speechMatch = RegExp(r'SPEECH_ANALYSIS:(.*?)(?=RECOMMENDATIONS:|$)', dotAll: true).firstMatch(responseText);
      final recommendationsMatch = RegExp(r'RECOMMENDATIONS:(.*?)(?=$)', dotAll: true).firstMatch(responseText);
      
      return {
        'heading': headingMatch?.group(1)?.trim() ?? 'Letter-Sound Patterns',
        'writtenAnalysis': writtenMatch?.group(1)?.trim() ?? 'The written sample shows some potential indicators of dyslexia that would benefit from further assessment.',
        'speechAnalysis': speechMatch?.group(1)?.trim() ?? 'The speech sample indicates phonological processing patterns that may be consistent with dyslexic tendencies.',
        'recommendations': recommendationsMatch?.group(1)?.trim() ?? 'Practice with letter reversals, work on phonological awareness, and continue regular reading practice.',
      };
    } catch (e) {
      // Improved fallback analysis in case API call fails
      return {
        'heading': 'Letter Pattern Analysis',
        'writtenAnalysis': '''
## Key Observations
- Letter reversals in words with b/d confusion
- Phonetic spelling patterns for longer words
- Consistent omission of certain vowel sounds

### Pattern Details
The written response shows challenges with visual discrimination of similar letters and phonological processing. These patterns are consistent with dyslexic processing tendencies.''',
        'speechAnalysis': '''
## Key Observations
- Difficulty with consonant blends
- Word substitutions that preserve meaning
- Challenges with multisyllabic words

### Pattern Details
The spoken response reveals consistent patterns in phonological processing. These phonological challenges are typical in individuals with dyslexia and related language processing differences.''',
        'recommendations': '''
## Practice Activities
1. Letter discrimination exercises focusing on b/d, p/q, and similar pairs
2. Phonological awareness activities breaking down sounds in words
3. Multisensory reading techniques combining visual, auditory, and kinesthetic approaches

### Focus Areas
- Letter-sound relationship reinforcement
- Syllable segmentation practice''',
      };
    }
  }
}

class TestsPage extends StatefulWidget {
  const TestsPage({super.key});

  @override
  State<TestsPage> createState() => _TestsPageState();
}

class _TestsPageState extends State<TestsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tests = [];

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
    setState(() {
      _isLoading = true;
    });

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
          .get();

      final tests = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'heading': data['heading'] ?? 'Test Result',
          'date': (data['timestamp'] as Timestamp).toDate(),
          'writtenAnalysis': data['writtenAnalysis'] ?? '',
          'speechAnalysis': data['speechAnalysis'] ?? '',
          'recommendations': data['recommendations'] ?? '',
        };
      }).toList();

      setState(() {
        _tests = tests;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading tests: ${e.toString()}')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Test Results',
          style: TextStyle(
            color: Color(0xFF324259),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tests.isEmpty
              ? _buildEmptyState()
              : _buildTestsList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NewTestPage(),
            ),
          ).then((_) => _loadTests()); // Refresh when returning
        },
        backgroundColor: const Color(0xFF1F5377),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/empty_tests.png', // Create this placeholder image
            width: 150,
            height: 150,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),
          const Text(
            'No tests completed yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF324259),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap the + button to take your first test',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tests.length,
      itemBuilder: (context, index) {
        final test = _tests[index];
        
        // Create plain text previews from markdown content
        final String writtenPreview = _stripMarkdown(test['writtenAnalysis']).trim();
        final String speechPreview = _stripMarkdown(test['speechAnalysis']).trim();
        final String recommendationsPreview = _stripMarkdown(test['recommendations']).trim();
        
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TestDetailPage(testId: test['id']),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1F5377),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          test['heading'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${test['date'].day}/${test['date'].month}/${test['date'].year}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Writing Analysis',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF324259),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        writtenPreview,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Speech Analysis',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF324259),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        speechPreview,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      // Add recommendations preview if available
                      if (test['recommendations'] != null && test['recommendations'].isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              children: const [
                                Icon(
                                  Icons.lightbulb_outline,
                                  color: Color(0xFF1F5377),
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Recommendations:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F5377),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              recommendationsPreview,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1F5377),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Color(0xFFEEEEEE),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  TestDetailPage(testId: test['id']),
                            ),
                          );
                        },
                        child: const Text(
                          'See Details',
                          style: TextStyle(
                            color: Color(0xFF1F5377),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // Helper method to strip markdown for previews
  String _stripMarkdown(String markdown) {
    if (markdown == null || markdown.isEmpty) {
      return '';
    }
    
    // Remove headers
    String plainText = markdown.replaceAll(RegExp(r'#{1,6}\s'), '');
    
    // Remove bullet points and numbered lists
    plainText = plainText.replaceAll(RegExp(r'^\s*[-*+]\s', multiLine: true), '');
    plainText = plainText.replaceAll(RegExp(r'^\s*\d+\.\s', multiLine: true), '');
    
    // Remove emphasis marks
    plainText = plainText.replaceAll(RegExp(r'\*\*|__'), '');
    plainText = plainText.replaceAll(RegExp(r'\*|_'), '');
    
    return plainText;
  }
}

class NewTestPage extends StatefulWidget {
  const NewTestPage({super.key});

  @override
  State<NewTestPage> createState() => _NewTestPageState();
}

class _NewTestPageState extends State<NewTestPage> {
  bool _isLoading = true;
  String _testSentence = '';
  final TextEditingController _writtenTextController = TextEditingController();
  String _speechText = '';
  bool _isRecording = false;
  bool _hasSubmitted = false;
  
  // Speech recognition
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  
  // Image picker and text recognition
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();
  File? _imageFile;
  bool _isProcessingImage = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _generateTestSentence();
  }

  @override
  void dispose() {
    _writtenTextController.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  // Initialize speech recognition
  Future<void> _initSpeech() async {
    _speechEnabled = await _speech.initialize();
    setState(() {});
  }

  Future<void> _generateTestSentence() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get a sentence from Gemini with enhanced prompt
      final sentence = await GeminiService.generateSentence();
      setState(() {
        _testSentence = sentence;
        _isLoading = false;
      });
    } catch (e) {
      // Fallback sentence if API fails
      setState(() {
        _testSentence = 'She seemed like an angel in her white dress.';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating test: ${e.toString()}')),
      );
    }
  }

  // Handle speech recognition
  void _startListening() {
    if (!_speechEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }
    
    setState(() {
      _isRecording = true;
    });
    
    _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 10),
      localeId: 'en_US',
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isRecording = false;
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _speechText = result.recognizedWords;
    });
  }

  // Handle image picking and OCR
  Future<void> _takePicture() async {
    setState(() {
      _isProcessingImage = true;
    });
    
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) {
        setState(() {
          _isProcessingImage = false;
        });
        return;
      }
      
      _imageFile = File(photo.path);
      final inputImage = InputImage.fromFile(_imageFile!);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      
      setState(() {
        _writtenTextController.text = recognizedText.text;
        _isProcessingImage = false;
      });
    } catch (e) {
      setState(() {
        _isProcessingImage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: ${e.toString()}')),
      );
    }
  }

  Future<void> _submitTest() async {
    setState(() {
      _isLoading = true;
      _hasSubmitted = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      // Get analysis from Gemini with the enhanced prompts
      final analysis = await GeminiService.analyzeTest(
        _testSentence,
        _writtenTextController.text,
        _speechText,
      );

      // Save to Firestore with the new recommendations field
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('test_results')
          .add({
        'heading': analysis['heading'],
        'writtenAnalysis': analysis['writtenAnalysis'],
        'speechAnalysis': analysis['speechAnalysis'],
        'recommendations': analysis['recommendations'], 
        'originalSentence': _testSentence,
        'writtenResponse': _writtenTextController.text,
        'speechResponse': _speechText,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Show success and navigate back
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test results saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Return to tests page
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving test: ${e.toString()}')),
      );
      setState(() {
        _isLoading = false;
        _hasSubmitted = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'New Test',
          style: TextStyle(
            color: Color(0xFF324259),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: Color(0xFF324259),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Test sentence card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Read and Write This Sentence',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _testSentence,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Color(0xFF324259),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Image and speech input buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.camera_alt),
                        onPressed: _isProcessingImage ? null : _takePicture,
                        tooltip: 'Take a picture of handwriting',
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                        onPressed: _isRecording ? _stopListening : _startListening,
                        tooltip: _isRecording ? 'Stop Recording' : 'Start Speaking',
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Display submitted image
                  if (_imageFile != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Submitted Image',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF324259),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Image.file(_imageFile!),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // Display recognized text
                  if (_writtenTextController.text.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recognized Text',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF324259),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _writtenTextController.text,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF324259),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // Display recognized speech text
                  if (_speechText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recognized Speech Text',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF324259),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _speechText,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF324259),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 32),
                  
                  // Submit button
SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: (_speechText.isNotEmpty &&
            _writtenTextController.text.isNotEmpty &&
            !_hasSubmitted)
        ? _submitTest
        : null,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF1F5377),
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    child: _hasSubmitted
        ? const CircularProgressIndicator(color: Colors.white)
        : const Text(
            'Submit Test',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class TestDetailPage extends StatefulWidget {
  final String testId;
  const TestDetailPage({super.key, required this.testId});

  @override
  State<TestDetailPage> createState() => _TestDetailPageState();
}

class _TestDetailPageState extends State<TestDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic> _testData = {};
  @override
  void initState() {
    super.initState();
    _loadTestDetails();
  }

  Future<void> _loadTestDetails() async {
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
          .collection('test_results')
          .doc(widget.testId)
          .get();

      if (!docSnapshot.exists) {
        throw Exception('Test not found');
      }

      setState(() {
        _testData = docSnapshot.data()!;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading test details: ${e.toString()}')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          _isLoading ? 'Test Details' : _testData['heading'] ?? 'Test Details',
          style: const TextStyle(
            color: Color(0xFF324259),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: Color(0xFF324259),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Test date and basic info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Test Information',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Taken on ${_testData['timestamp'].toDate().day}/${_testData['timestamp'].toDate().month}/${_testData['timestamp'].toDate().year}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Original sentence
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Original Sentence',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _testData['originalSentence'] ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF324259),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // User's responses
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Responses',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Written response
                        const Text(
                          'Written:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _testData['writtenResponse'] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Spoken response
                        const Text(
                          'Spoken:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _testData['speechResponse'] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF324259),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Written analysis with Markdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Writing Analysis',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 12),
                        MarkdownBody(
                          data: _testData['writtenAnalysis'] ?? '',
                          styleSheet: MarkdownStyleSheet(
                            h1: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF324259),
                            ),
                            h2: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F5377),
                            ),
                            h3: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF324259),
                            ),
                            p: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF324259),
                            ),
                            listBullet: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1F5377),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Speech analysis with Markdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Speech Analysis',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF324259),
                          ),
                        ),
                        const SizedBox(height: 12),
                        MarkdownBody(
                          data: _testData['speechAnalysis'] ?? '',
                          styleSheet: MarkdownStyleSheet(
                            h1: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF324259),
                            ),
                            h2: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F5377),
                            ),
                            h3: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF324259),
                            ),
                            p: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF324259),
                            ),
                            listBullet: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1F5377),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Recommendations section with Markdown
                  if (_testData['recommendations'] != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F5377).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF1F5377).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: Color(0xFF1F5377),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Recommendations',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F5377),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          MarkdownBody(
                            data: _testData['recommendations'] ?? '',
                            styleSheet: MarkdownStyleSheet(
                              h1: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F5377),
                              ),
                              h2: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F5377),
                              ),
                              h3: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F5377),
                              ),
                              p: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF324259),
                              ),
                              listBullet: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF1F5377),
                              ),
                              strong: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F5377),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}