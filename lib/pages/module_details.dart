import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:readora/services/practice_module_service.dart';
import 'package:readora/services/drawing_utils.dart'; // Correct path for drawing utilities

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
  
  // Exercise content for each module - should be moved to a central service in a real app
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
      'Track left to right: → → → ← → → ← →',
      'Follow the pattern: A B A B B A B A A',
      'Scan for the letter D: a b c d e f g h i j k l m n o p',
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
          isCorrect = matchPercentage >= 100;
        } else {
          // For single words, be more strict
          isCorrect = cleanRecognized.isNotEmpty && (cleanRecognized.contains(cleanTarget) || 
                      cleanTarget.contains(cleanRecognized));
        }
        
        hasChecked = true;
        isProcessing = false;
      });
      
    } catch (e) {
      setState(() {
        recognizedText = 'Error: ${e.toString()}';
        isProcessing = false;
        isCorrect = false; // Ensure errors are marked as incorrect
        hasChecked = true;
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
      isCorrect = _speechText.isNotEmpty && (_speechText.contains(currentContent) || 
                  currentContent.contains(_speechText));
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
    if (isCorrect) {
      // Update progress if this is a new highest completed exercise
      if (currentExercise >= widget.module.completedExercises) {
        // Only increment progress if we're at the highest completed exercise
        widget.onProgressUpdate(currentExercise + 1);
        
        // Also update using the central service to ensure all screens are in sync
        PracticeModuleService.updateModuleProgress(
          widget.module.id, 
          currentExercise + 1
        );
        
        print('Progress updated: ${currentExercise + 1}/${widget.module.totalExercises}');
      }
      
      if (currentExercise < widget.module.totalExercises - 1) {
        setState(() {
          currentExercise += 1;
          recognizedText = '';
          _speechText = '';
          hasChecked = false;
          isCorrect = false;
          points.clear(); // Reset drawing if applicable
        });
      } else {
        _completeModule();
      }
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
    // Update to mark the entire module as complete
    widget.onProgressUpdate(widget.module.totalExercises);
    
    // Also update using the central service
    PracticeModuleService.updateModuleProgress(
      widget.module.id, 
      widget.module.totalExercises
    );
    
    // The recordModuleCompletion will be called inside updateModuleProgress
    // when the module is detected as newly completed
    
    print('Module completed: ${widget.module.title}');
    
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
        // Ensure we always set hasChecked=true even if no text was recognized
        hasChecked = true;
        
        // Set a more user-friendly message when no text is detected
        this.recognizedText = extracted.isEmpty ? "No text detected" : extracted;
        
        // Compare with current exercise
        final currentContent = getCurrentExercise();
        
        // Different comparison logic based on module type
        if (widget.module.id == 'word_formation') {
          // For word formation, require exact match
          isCorrect = extracted.isNotEmpty && extracted.toLowerCase().trim() == currentContent.toLowerCase().trim();
        } 
        else if (widget.module.id == 'visual_tracking') {
          // For visual tracking exercises, we still need some specialized validation
          // but make it stricter
          
          // Specific check for number pattern exercise
          if (currentContent.contains('Find the pattern')) {
            isCorrect = extracted == '3' || extracted == 'three';
          } else {
            // Use stricter validation for other visual tracking exercises
            isCorrect = _validateVisualTrackingAnswerStrict(currentContent, extracted);
          }
        }
        else if (widget.module.id == 'reading_comprehension') {
          // Use stricter validation for reading comprehension
          isCorrect = _validateReadingComprehensionAnswerStrict(currentContent, extracted);
        }
        else {
          // Default comparison - exact match only
          isCorrect = extracted.toLowerCase().trim() == currentContent.toLowerCase().trim();
        }
      });
    } else {
      // Handle case where image conversion failed
      setState(() {
        hasChecked = true;
        recognizedText = "Error: Could not process image";
        isCorrect = false;
      });
    }
  } catch (e) {
    print('Error in _processDrawing: ${e.toString()}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error processing drawing: ${e.toString()}')),
    );
    
    // Make sure we update UI state even in case of errors
    setState(() {
      hasChecked = true;
      recognizedText = "Error processing drawing";
      isCorrect = false;
      _isProcessingDrawing = false;
    });
  } finally {
    setState(() {
      _isProcessingDrawing = false;
    });
  }
}

// Stricter validation for visual tracking exercises
bool _validateVisualTrackingAnswerStrict(String exerciseContent, String userAnswer) {
  print('Strict visual tracking validation - Exercise: $exerciseContent, Answer: $userAnswer');
  
  // Debug the user input
  final cleanUserAnswer = userAnswer.trim().toLowerCase();
  print('Cleaned user answer: $cleanUserAnswer');
  
  // Check which visual tracking exercise this is
  if (exerciseContent.contains('Find the pattern')) {
    // Only accept exact "3" or "three"
    return cleanUserAnswer == '3' || cleanUserAnswer == 'three';
  } 
  else if (exerciseContent.contains('Track left to right')) {
    // Arrow tracking exercise - require exact arrow match
    return cleanUserAnswer == '←' || cleanUserAnswer == 'left arrow';
  }
  else if (exerciseContent.contains('Follow the pattern')) {
    // Letter pattern recognition - require exact match of expected letter
    return cleanUserAnswer == 'b';
  }
  else if (exerciseContent.contains('Scan for the letter')) {
    // Letter scanning - exact match only
    return cleanUserAnswer == 'd';
  }
  else if (exerciseContent.contains('Count the circles')) {
    // Circle counting - exact number only (6)
    return cleanUserAnswer == '6' || cleanUserAnswer == 'six';
  }
  
  // For any other pattern, default to exact match
  return false;
}

// Stricter validation for reading comprehension exercises
bool _validateReadingComprehensionAnswerStrict(String exerciseContent, String userAnswer) {
  // Clean up the user answer
  final cleanAnswer = userAnswer.trim().toLowerCase();
  
  // Match exact answers based on the specific question
  if (exerciseContent.contains('Tom has a red ball')) {
    return cleanAnswer == 'red';
  } 
  else if (exerciseContent.contains('Sara went to the store')) {
    // For this one, accept either "milk and bread" or "bread and milk"
    return cleanAnswer == 'milk and bread' || cleanAnswer == 'bread and milk';
  } 
  else if (exerciseContent.contains('The sky is blue')) {
    return cleanAnswer == 'green';
  } 
  else if (exerciseContent.contains('Ben has three pets')) {
    return cleanAnswer == 'three' || cleanAnswer == '3';
  } 
  else if (exerciseContent.contains('Maya likes to read books')) {
    return cleanAnswer == 'dinosaurs' || cleanAnswer == 'dinosaur';
  }
  
  // Default to exact match if none of the specific cases apply
  return false;
}

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
      return userAnswer.contains('←') || userAnswer.contains('left');
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
    return targetWords.isNotEmpty && (matchedWords / targetWords.length) >= 1.0;
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
  
  @override
  Widget build(BuildContext context) {
    // First check if module is already completed
    // Use the current module data from the service to ensure up-to-date information
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
                  backgroundColor: const Color(0xFF1F5377),
                ),
                child: const Text('Return to Modules',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
              // Add a button to restart the module
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  // Reset progress using the shared service
                  PracticeModuleService.resetModuleProgress(widget.module.id);
                  
                  // Also notify parent through callback
                  widget.onProgressUpdate(0);
                  
                  setState(() {
                    currentExercise = 0;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color.fromARGB(255, 121, 31, 28),
                ),
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
      body: SafeArea(
        child: Stack(
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
                  
                  // Show saved progress indicator if different from current exercise
                  if (widget.module.completedExercises > 0 && 
                      widget.module.completedExercises != currentExercise)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Saved progress: ${widget.module.completedExercises}/${widget.module.totalExercises}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                  
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
                  const SizedBox(height: 16),
                  
                  // Module-specific input controls
                  if (_shouldUseDrawingInput())
                    _buildDrawingInput()
                  else if (widget.module.type == ModuleType.written)
                    Expanded(child: _buildOCRControls())
                  else
                    Expanded(child: _buildSpeechControls()),
                  
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
                          backgroundColor: Colors.green,
                          disabledBackgroundColor: Colors.grey,
                        ),
                        child: Text(isLastExercise ? 'Complete Module' : 'Next'),
                      ),
                    ],
                  ),
                  
                  // Small bottom padding
                  const SizedBox(height: 12),
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
      ),
    );
  }

  // Determine if this module should use drawing input
  bool _shouldUseDrawingInput() {
    final drawingModules = ['word_formation', 'visual_tracking', 'reading_comprehension'];
    return drawingModules.contains(widget.module.id);
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
        
        const SizedBox(height: 16),
        
        // Drawing controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _clearDrawing,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
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
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text('Check Answer'),
            ),
          ],
        ),
        
        const SizedBox(height: 10),
        
        // Display recognized text - MODIFIED SECTION
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
                  // Show a more user-friendly message when no text recognized
                  (recognizedText.isEmpty || recognizedText == "No text detected") 
                      ? 'No text was recognized. Please try again with clearer writing.'
                      : recognizedText,
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
          
        const Spacer(flex: 1),
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
        
        // Strong spacer to push feedback up when needed
        const Spacer(flex: 4),
        
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
          
        // Small spacer at bottom
        const Spacer(flex: 1),
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
        
        // Strong spacer to push feedback up
        const Spacer(flex: 4),
        
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
          
        // Small spacer at bottom
        const Spacer(flex: 1),
      ],
    );
  }
}