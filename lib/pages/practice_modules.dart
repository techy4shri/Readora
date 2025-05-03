import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';

// Drawing area for handwriting input
class DrawingArea {
  Offset point;
  Paint areaPaint;

  DrawingArea({required this.point, required this.areaPaint});
}

// Custom painter for drawing
class MyCustomPainter extends CustomPainter {
  final List<DrawingArea?> points;

  MyCustomPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    // Paint background white
    Paint background = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, background);

    // Draw points
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!.point, points[i + 1]!.point, points[i]!.areaPaint);
      } else if (points[i] != null && points[i + 1] == null) {
        // For single points, draw a small circle for better visibility
        canvas.drawCircle(points[i]!.point, points[i]!.areaPaint.strokeWidth / 2, points[i]!.areaPaint);
      }
    }
  }

  @override
  bool shouldRepaint(MyCustomPainter oldDelegate) {
    return true;
  }
}

class PracticeModulesScreen extends StatefulWidget {
  const PracticeModulesScreen({Key? key}) : super(key: key);

  @override
  _PracticeModulesScreenState createState() => _PracticeModulesScreenState();
}

class _PracticeModulesScreenState extends State<PracticeModulesScreen> {
  List<PracticeModule> modules = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeModules();
  }

  Future<void> _initializeModules() async {
    // Define the default modules
    final defaultModules = [
      PracticeModule(
        id: 'sentence_writing',
        title: 'Sentence Writing',
        description: 'Practice writing sentences with dyslexic challenges',
        type: ModuleType.written,
        totalExercises: 5,
        completedExercises: 0,
      ),
      PracticeModule(
        id: 'word_formation',
        title: 'Word Formation',
        description: 'Form words from letters (OCR based)',
        type: ModuleType.written,
        totalExercises: 5,
        completedExercises: 0,
      ),
      PracticeModule(
        id: 'speech_recognition',
        title: 'Speech Recognition',
        description: 'Practice speaking sentences clearly',
        type: ModuleType.speech,
        totalExercises: 5,
        completedExercises: 0,
      ),
      PracticeModule(
        id: 'phonetic_awareness',
        title: 'Phonetic Awareness',
        description: 'Practice with phonetic rules and sounds',
        type: ModuleType.speech,
        totalExercises: 5,
        completedExercises: 0,
      ),
      PracticeModule(
        id: 'visual_tracking',
        title: 'Visual Tracking',
        description: 'Improve visual tracking skills with exercises',
        type: ModuleType.written,
        totalExercises: 5,
        completedExercises: 0,
      ),
      PracticeModule(
        id: 'reading_comprehension',
        title: 'Reading Comprehension',
        description: 'Read and answer questions about short texts',
        type: ModuleType.written,
        totalExercises: 5,
        completedExercises: 0,
      ),
    ];

    // Load saved progress
    final prefs = await SharedPreferences.getInstance();
    final savedModules = prefs.getString('practice_modules');

    if (savedModules != null) {
      final List<dynamic> decodedModules = json.decode(savedModules);
      modules = decodedModules
          .map((moduleJson) => PracticeModule.fromJson(moduleJson))
          .toList();
    } else {
      modules = defaultModules;
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final modulesJson = modules.map((module) => module.toJson()).toList();
    await prefs.setString('practice_modules', json.encode(modulesJson));
  }

  void _updateProgress(PracticeModule module, int completed) {
    setState(() {
      final index = modules.indexWhere((m) => m.id == module.id);
      if (index != -1) {
        modules[index] = module.copyWith(completedExercises: completed);
        _saveProgress();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Practice Modules',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: modules.length,
              itemBuilder: (context, index) {
                final module = modules[index];
                return ModuleCard(
                  module: module,
                  onTap: () {
                    // Navigate to the specific module screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ModuleDetailScreen(
                          module: module,
                          onProgressUpdate: (completed) {
                            _updateProgress(module, completed);
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

enum ModuleType { written, speech }

class PracticeModule {
  final String id;
  final String title;
  final String description;
  final ModuleType type;
  final int totalExercises;
  final int completedExercises;

  PracticeModule({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.totalExercises,
    required this.completedExercises,
  });

  double get progressPercentage => 
      totalExercises > 0 ? completedExercises / totalExercises : 0.0;

  PracticeModule copyWith({
    String? id,
    String? title,
    String? description,
    ModuleType? type,
    int? totalExercises,
    int? completedExercises,
  }) {
    return PracticeModule(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      totalExercises: totalExercises ?? this.totalExercises,
      completedExercises: completedExercises ?? this.completedExercises,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.toString().split('.').last,
      'totalExercises': totalExercises,
      'completedExercises': completedExercises,
    };
  }

  factory PracticeModule.fromJson(Map<String, dynamic> json) {
    return PracticeModule(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      type: json['type'] == 'written' ? ModuleType.written : ModuleType.speech,
      totalExercises: json['totalExercises'],
      completedExercises: json['completedExercises'],
    );
  }
}

class ModuleCard extends StatelessWidget {
  final PracticeModule module;
  final VoidCallback onTap;

  const ModuleCard({
    Key? key,
    required this.module,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
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
                        fontSize: 12,
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
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress: ${module.completedExercises}/${module.totalExercises}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(module.progressPercentage * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: module.progressPercentage,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      module.progressPercentage == 1.0
                          ? Colors.green
                          : Colors.blue,
                    ),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModuleDetailScreen extends StatefulWidget {
  final PracticeModule module;
  final Function(int) onProgressUpdate;

  const ModuleDetailScreen({
    Key? key,
    required this.module,
    required this.onProgressUpdate,
  }) : super(key: key);

  @override
  _ModuleDetailScreenState createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  late int currentExercise;
  bool isProcessing = false;
  String recognizedText = '';
  bool isCorrect = false;
  bool hasChecked = false;
  final ImagePicker _picker = ImagePicker();
  final textRecognizer = TextRecognizer();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _speechText = '';
  
  // Drawing capabilities
  List<DrawingArea?> points = [];
  Color selectedColor = Colors.black;
  double strokeWidth = 5.0;
  bool _isProcessingDrawing = false;
  
  // Exercise content for each module
  final Map<String, List<String>> moduleExercises = {
    'sentence_writing': [
      'The quick brown fox jumps over the lazy dog.',
      'She sells seashells by the seashore.',
      'How much wood would a woodchuck chuck?',
      'Peter Piper picked a peck of pickled peppers.',
      'All good things must come to an end.',
    ],
    'word_formation': [
      'apple',
      'banana',
      'elephant',
      'dinosaur',
      'butterfly',
    ],
    'speech_recognition': [
      'She sells seashells by the seashore',
      'The big black bug bit the big black bear',
      'Unique New York, unique New York',
      'Peter Piper picked a peck of pickled peppers',
      'Three free throws for three points',
    ],
    'phonetic_awareness': [
      'Snowflake',
      'Caterpillar',
      'Basketball',
      'Butterfly',
      'Sunshine',
    ],
    'visual_tracking': [
      'Find the pattern: 1 2 3, 1 2 3, 1 2 _',
      'Track left to right: → → → ← → → ← → ←',
      'Follow the pattern: A B A B B A B A A',
      'Scan for the letter D: A B C D E F G H I J K L M N O P',
      'Count the circles: ■ ● ■ ● ● ■ ● ■ ● ■ ■ ●',
    ],
    'reading_comprehension': [
      'Tom has a red ball. The ball is round. Tom likes to play with his ball. What color is Tom\'s ball?',
      'Sara went to the store. She bought milk and bread. What did Sara buy at the store?',
      'The sky is blue. The grass is green. Flowers come in many colors. What color is the grass?',
      'Ben has three pets: a dog, a cat, and a fish. How many pets does Ben have?',
      'Maya likes to read books about dinosaurs. She learns about T-Rex and Triceratops. What does Maya like to read about?',
    ],
  };

  @override
  void initState() {
    super.initState();
    currentExercise = widget.module.completedExercises;
    
    // Initialize speech recognition for speech modules
    if (widget.module.type == ModuleType.speech) {
      _initSpeech();
    }
  }
  
  @override
  void dispose() {
    textRecognizer.close();
    super.dispose();
  }
  
  // Initialize speech recognition
  Future<void> _initSpeech() async {
    _speechEnabled = await _speech.initialize();
    setState(() {});
  }

  // Take photo for OCR
  Future<void> _takePhoto() async {
    setState(() {
      isProcessing = true;
      recognizedText = '';
      isCorrect = false;
      hasChecked = false;
    });
    
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) {
        setState(() {
          isProcessing = false;
        });
        return;
      }
      
      final inputImage = InputImage.fromFilePath(photo.path);
      final recognizedText = await textRecognizer.processImage(inputImage);
      
      setState(() {
        this.recognizedText = recognizedText.text;
        
        // Check if the recognized text matches the current exercise
        final currentContent = getCurrentExercise().toLowerCase();
        final cleanRecognized = this.recognizedText.toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();
        final cleanTarget = currentContent
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();
          
        if (widget.module.id == 'sentence_writing') {
          // For sentences, use more lenient comparison (75% match)
          final targetWords = cleanTarget.split(' ');
          final recognizedWords = cleanRecognized.split(' ');
          
          int matchedWords = 0;
          for (final targetWord in targetWords) {
            if (targetWord.isNotEmpty && 
                recognizedWords.any((word) => word.contains(targetWord) || 
                targetWord.contains(word))) {
              matchedWords++;
            }
          }
          
          final matchPercentage = targetWords.isEmpty ? 
              0 : (matchedWords / targetWords.length) * 100;
          isCorrect = matchPercentage >= 75;
        } else {
          // For single words, be more strict
          isCorrect = cleanRecognized.contains(cleanTarget) || 
                      cleanTarget.contains(cleanRecognized);
        }
        
        hasChecked = true;
        isProcessing = false;
      });
      
    } catch (e) {
      setState(() {
        recognizedText = 'Error: ${e.toString()}';
        isProcessing = false;
      });
    }
  }
  
  // Start speech recognition
  void _startListening() {
    if (!_speechEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }
    
    setState(() {
      _isListening = true;
      _speechText = '';
      isCorrect = false;
      hasChecked = false;
    });
    
    _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 5),
      localeId: 'en_US',
    );
  }
  
  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }
  
  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _speechText = result.recognizedWords.toLowerCase();
      
      // Compare with current exercise
      final currentContent = getCurrentExercise().toLowerCase();
      isCorrect = _speechText.contains(currentContent) || 
                  currentContent.contains(_speechText);
      hasChecked = true;
    });
  }

  String getCurrentExercise() {
    final exercises = moduleExercises[widget.module.id] ?? ['Exercise not found'];
    if (currentExercise < exercises.length) {
      return exercises[currentExercise];
    }
    return 'Exercise not found';
  }

  void _nextExercise() {
    if (currentExercise < widget.module.totalExercises - 1) {
      setState(() {
        currentExercise += 1;
        recognizedText = '';
        _speechText = '';
        hasChecked = false;
        isCorrect = false;
      });
    } else {
      _completeModule();
    }
  }
  
  void _previousExercise() {
    if (currentExercise > 0) {
      setState(() {
        currentExercise -= 1;
        recognizedText = '';
        _speechText = '';
        hasChecked = false;
        isCorrect = false;
      });
    }
  }

  void _completeModule() {
    widget.onProgressUpdate(widget.module.totalExercises);
    
    // Show completion dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Module Completed!'),
        content: Text('Congratulations! You have completed the ${widget.module.title} module.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to modules list
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  // Clear drawing canvas
  void _clearDrawing() {
    setState(() {
      points.clear();
      recognizedText = '';
      hasChecked = false;
      isCorrect = false;
    });
  }
  
  // Process drawing for OCR
  Future<void> _processDrawing() async {
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw something first')),
      );
      return;
    }
    
    setState(() {
      _isProcessingDrawing = true;
      recognizedText = '';
      isCorrect = false;
      hasChecked = false;
    });
    
    try {
      // Convert drawing to image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // White background
      final backgroundPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      
      // Use the actual size of the drawing area
      final size = MediaQuery.of(context).size;
      final width = size.width - 32; // Account for padding
      final height = 300.0; // Increased height for better recognition
      
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height), backgroundPaint);
      
      // Draw the points
      for (int i = 0; i < points.length - 1; i++) {
        if (points[i] != null && points[i + 1] != null) {
          canvas.drawLine(points[i]!.point, points[i + 1]!.point, points[i]!.areaPaint);
        } else if (points[i] != null && points[i + 1] == null) {
          canvas.drawPoints(ui.PointMode.points, [points[i]!.point], points[i]!.areaPaint);
        }
      }
      
      // Convert to image
      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      
      if (pngBytes != null) {
        final buffer = pngBytes.buffer;
        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/drawing.png').writeAsBytes(
          buffer.asUint8List(pngBytes.offsetInBytes, pngBytes.lengthInBytes)
        );
        
        // Use ML Kit for text recognition
        final inputImage = InputImage.fromFile(file);
        final recognizedText = await textRecognizer.processImage(inputImage);
        
        // Process the recognized text
        final extracted = recognizedText.text.toLowerCase().trim();
        
        setState(() {
          this.recognizedText = extracted.isEmpty ? "No text detected" : extracted;
          
          // Compare with current exercise
          final currentContent = getCurrentExercise();
          
          // Different comparison logic based on module type
          if (widget.module.id == 'word_formation') {
            // For word formation, check if the recognized text contains the target word
            isCorrect = extracted.contains(currentContent.toLowerCase()) || 
                        currentContent.toLowerCase().contains(extracted);
          } 
          else if (widget.module.id == 'visual_tracking') {
            // Enhanced visual tracking validation
            isCorrect = _validateVisualTrackingAnswer(currentContent, extracted);
            
            // Specific check for number pattern exercise
            if (currentContent.contains('Find the pattern')) {
              isCorrect = extracted == '3' || extracted.contains('3') || extracted.contains('three');
            }
          }
          else if (widget.module.id == 'reading_comprehension') {
            // Enhanced reading comprehension validation
            isCorrect = _validateReadingComprehensionAnswer(currentContent, extracted);
          }
          else {
            // Default comparison
            isCorrect = extracted.toLowerCase() == currentContent.toLowerCase();
          }
          
          hasChecked = true;
        });
      }
    } catch (e) {
      print('Error in _processDrawing: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing drawing: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isProcessingDrawing = false;
      });
    }
  }
  
  // Custom validation for visual tracking exercises
  bool _validateVisualTrackingAnswer(String exerciseContent, String userAnswer) {
    print('Visual tracking validation - Exercise: $exerciseContent, Answer: $userAnswer');
    
    // Debug the user input
    final cleanUserAnswer = userAnswer.trim().toLowerCase();
    print('Cleaned user answer: $cleanUserAnswer');
    
    // Check which visual tracking exercise this is
    if (exerciseContent.contains('Find the pattern')) {
      // Simple number sequence - the answer is 3
      final isCorrect = cleanUserAnswer == '3' || 
                        cleanUserAnswer == 'three' || 
                        cleanUserAnswer.contains('3') || 
                        cleanUserAnswer.contains('three');
      print('Pattern exercise check result: $isCorrect');
      return isCorrect;
    } 
    else if (exerciseContent.contains('Track left to right')) {
      // Arrow tracking exercise - check for arrows
      return userAnswer.contains('→') || userAnswer.contains('←') || 
             userAnswer.contains('arrow') || userAnswer.contains('right') || 
             userAnswer.contains('left');
    }
    else if (exerciseContent.contains('Follow the pattern')) {
      // Letter pattern recognition - check for A or B
      return userAnswer.toLowerCase().contains('b');
    }
    else if (exerciseContent.contains('Scan for the letter')) {
      // Letter scanning - check if they found the target letter (d)
      return userAnswer.contains('d');
    }
    else if (exerciseContent.contains('Count the circles')) {
      // Circle counting - check for numbers (the answer would be 6)
      final numberPattern = RegExp(r'\b[5-7]\b'); // Accept 5, 6, or 7 as close enough
      return numberPattern.hasMatch(userAnswer) || 
             userAnswer.contains('six') || userAnswer.contains('6');
    }
    
    // Default pattern matching for other visual exercises
    final cleanTarget = exerciseContent.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    final cleanExtracted = userAnswer.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    
    // Check for pattern matches - more lenient
    final targetWords = cleanTarget.split(' ');
    int matchedWords = 0;
    
    for (final targetWord in targetWords) {
      if (targetWord.length > 3 && cleanExtracted.contains(targetWord)) { // Only match significant words
        matchedWords++;
      }
    }
    
    // Consider correct if at least 40% of pattern elements are found
    return targetWords.isNotEmpty && (matchedWords / targetWords.length) >= 0.4;
  }

  // Custom validation for reading comprehension exercises
  bool _validateReadingComprehensionAnswer(String exerciseContent, String userAnswer) {
    // Extract the question from the content
    final parts = exerciseContent.split('?');
    if (parts.length < 2) {
      return false; // No question found
    }
    
    // Get the last part which typically contains the question
    final questionPart = parts.last.trim().toLowerCase();
    
    // Extract correct answers based on the question context
    Map<String, List<String>> correctAnswers = {
      'Tom has a red ball': ['red'],
      'Sara went to the store': ['milk', 'bread'],
      'The sky is blue': ['green'],
      'Ben has three pets': ['three', '3'],
      'Maya likes to read books': ['dinosaurs', 'dinosaur'],
    };
    
    // Find which question we're dealing with and check the answer
    for (final key in correctAnswers.keys) {
      if (exerciseContent.toLowerCase().contains(key.toLowerCase())) {
        final answers = correctAnswers[key]!;
        for (final answer in answers) {
          if (userAnswer.toLowerCase().contains(answer.toLowerCase())) {
            return true;
          }
        }
        break;
      }
    }
    
    // If no specific match, do a more general check
    // Extract potential answers from the text (usually nouns and colors)
    final potentialAnswers = [
      'red', 'blue', 'green', 'milk', 'bread', 'three', 'dog', 'cat', 
      'fish', 'dinosaurs', 'trex', 'triceratops', 't-rex'
    ];
    
    for (final answer in potentialAnswers) {
      if (userAnswer.toLowerCase().contains(answer) && 
          exerciseContent.toLowerCase().contains(answer)) {
        return true;
      }
    }
    
    return false;
  }

  // Determine if this module should use drawing input
  bool _shouldUseDrawingInput() {
    final drawingModules = ['word_formation', 'visual_tracking', 'reading_comprehension'];
    return drawingModules.contains(widget.module.id);
  }

  @override
  Widget build(BuildContext context) {
    // Check if module is already completed
    if (widget.module.completedExercises >= widget.module.totalExercises) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.module.title),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Module Completed!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You have successfully completed ${widget.module.title}',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Return to Modules'),
              ),
              // Add a button to restart the module
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  widget.onProgressUpdate(0);
                  setState(() {
                    currentExercise = 0;
                  });
                },
                child: const Text('Practice Again'),
              ),
            ],
          ),
        ),
      );
    }

    final currentContent = getCurrentExercise();
    final bool isLastExercise = currentExercise == widget.module.totalExercises - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.title),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress indicator
                Text(
                  'Exercise ${currentExercise + 1} of ${widget.module.totalExercises}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (currentExercise + 1) / widget.module.totalExercises,
                  backgroundColor: Colors.grey[300],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(height: 24),
                
                // Exercise content
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shouldUseDrawingInput() 
                              ? 'Write the answer with your finger:' 
                              : (widget.module.type == ModuleType.written 
                                  ? 'Write or photograph the following:' 
                                  : 'Say the following:'),
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          currentContent,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Module-specific input controls
                if (_shouldUseDrawingInput())
                  _buildDrawingInput()
                else if (widget.module.type == ModuleType.written)
                  _buildOCRControls()
                else
                  _buildSpeechControls(),
                
                const Spacer(),
                
                // Navigation buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Previous button (if not the first exercise)
                    currentExercise > 0
                        ? ElevatedButton(
                            onPressed: _previousExercise,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Previous'),
                          )
                        : const SizedBox(width: 88), // Placeholder for alignment
                    
                    // Next/Complete button (enabled only if exercise is correct)
                    ElevatedButton(
                      onPressed: isCorrect ? _nextExercise : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        disabledBackgroundColor: Colors.grey,
                      ),
                      child: Text(isLastExercise ? 'Complete Module' : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Loading overlay
          if (isProcessing || _isProcessingDrawing)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
  
  // Drawing input interface
  Widget _buildDrawingInput() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: MediaQuery.of(context).size.height * 0.2,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: RepaintBoundary(
              child: GestureDetector(
                onPanDown: (details) {
                  setState(() {
                    points.add(
                      DrawingArea(
                        point: details.localPosition,
                        areaPaint: Paint()
                          ..color = selectedColor
                          ..strokeWidth = strokeWidth
                          ..strokeCap = StrokeCap.round
                          ..isAntiAlias = true,
                      ),
                    );
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    points.add(
                      DrawingArea(
                        point: details.localPosition,
                        areaPaint: Paint()
                          ..color = selectedColor
                          ..strokeWidth = strokeWidth
                          ..strokeCap = StrokeCap.round
                          ..isAntiAlias = true,
                      ),
                    );
                  });
                },
                onPanEnd: (details) {
                  setState(() {
                    points.add(null);
                  });
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: MyCustomPainter(points: points),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Drawing controls
          Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    ElevatedButton(
      onPressed: _clearDrawing,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white, // Sets text color to white
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder( // Less rounded corners
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: const Text('Clear'),
    ),
    const SizedBox(width: 16),
    ElevatedButton(
      onPressed: _processDrawing,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white, // Sets text color to white
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder( // Less rounded corners
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: const Text('Check Answer'),
    ),
  ],
),
          
          const SizedBox(height: 12),
          
          // Display recognized text
          if (hasChecked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCorrect ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCorrect ? Colors.green : Colors.red,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recognized Text:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recognizedText.isEmpty ? 'No text recognized' : recognizedText,
                    style: TextStyle(
                      fontSize: 16,
                      color: isCorrect ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        isCorrect ? Icons.check_circle : Icons.cancel,
                        color: isCorrect ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isCorrect ? 'Correct!' : 'Try again',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isCorrect ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Controls for OCR-based exercises
  Widget _buildOCRControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Take photo button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Take Photo'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Recognized text display (if available)
        if (hasChecked)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCorrect ? Colors.green : Colors.red,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recognized Text:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  recognizedText.isEmpty ? 'No text recognized' : recognizedText,
                  style: TextStyle(
                    fontSize: 16,
                    color: isCorrect ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isCorrect ? Icons.check_circle : Icons.cancel,
                      color: isCorrect ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCorrect ? 'Correct!' : 'Try again',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isCorrect ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Controls for speech-based exercises
  Widget _buildSpeechControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Press and hold the microphone to speak',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 20),
        
        // Microphone button
        GestureDetector(
          onTapDown: (_) => _startListening(),
          onTapUp: (_) => _stopListening(),
          onTapCancel: () => _stopListening(),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _isListening ? Colors.red : Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Recognized speech display (if available)
        if (hasChecked && _speechText.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCorrect ? Colors.green : Colors.red,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You said:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _speechText,
                  style: TextStyle(
                    fontSize: 16,
                    color: isCorrect ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isCorrect ? Icons.check_circle : Icons.cancel,
                      color: isCorrect ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCorrect ? 'Correct!' : 'Try again',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isCorrect ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
