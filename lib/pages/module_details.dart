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
import 'package:readora/services/user_level_service.dart';

class ModuleDetailScreen extends StatefulWidget {
  final PracticeModule module;
  final Function(int)? onProgressUpdate;

  const ModuleDetailScreen({
    Key? key,
    required this.module,
    this.onProgressUpdate,
  }) : super(key: key);

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  int _currentExerciseIndex = 0;
  int _completedExercises = 0;
  bool _isLoading = false;
  bool _showingFeedback = false;
  
  // User level service
  final UserLevelService _userLevelService = UserLevelService();
  
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
    _completedExercises = widget.module.completedExercises;
  }

  void _showFeedbackDialog(bool isCorrect) {
    // Don't show feedback if already showing
    if (_showingFeedback) return;
    
    setState(() {
      _showingFeedback = true;
    });
    
    // Record the exercise attempt
    final exerciseId = '${widget.module.id}_ex_$_currentExerciseIndex';
    _userLevelService.recordExerciseAttempt(
      exerciseId: exerciseId,
      isCorrect: isCorrect,
    );
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(isCorrect ? 'Correct!' : 'Not quite right'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCorrect ? Icons.check_circle : Icons.cancel,
                color: isCorrect ? Colors.green : Colors.red,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                isCorrect
                    ? 'Great job! You got it right.'
                    : 'Keep practicing, you\'ll get it next time!',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _showingFeedback = false;
                });
                
                // If correct, move to next exercise or update progress
                if (isCorrect) {
                  if (_currentExerciseIndex < widget.module.totalExercises - 1) {
                    setState(() {
                      _currentExerciseIndex++;
                    });
                  } else {
                    // Completed all exercises
                    _updateProgress(_completedExercises + 1);
                  }
                }
              },
              child: Text(isCorrect ? 'Continue' : 'Try Again'),
            ),
          ],
        );
      },
    );
  }

  void _updateProgress(int completedCount) {
    setState(() {
      _completedExercises = completedCount;
    });
    
    if (widget.onProgressUpdate != null) {
      widget.onProgressUpdate!(completedCount);
    }
  }

  Widget _buildExerciseContent() {
    // This is a simple placeholder for different exercise types
    // In a real app, this would be much more sophisticated
    final isWritten = widget.module.type == ModuleType.written;
    
    return Column(
      children: [
        // Exercise instructions
        Text(
          'Exercise ${_currentExerciseIndex + 1}/${widget.module.totalExercises}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isWritten 
              ? 'Write the following word correctly:' 
              : 'Pronounce the following word correctly:',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 24),
        
        // Sample exercise content - would be dynamic in real app
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Text(
            // Sample word based on exercise index
            _getSampleWord(_currentExerciseIndex),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 40),
        
        // Response input
        if (isWritten)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Type your answer here',
                border: OutlineInputBorder(),
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: () {
              // This would activate speech recognition in a real app
              _showFeedbackDialog(true); // Simulate correct for demo
            },
            icon: const Icon(Icons.mic),
            label: const Text('Start Speaking'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        const SizedBox(height: 32),
        
        // Submit button for written exercises
        if (isWritten)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                  _showFeedbackDialog(false); // Simulate incorrect
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Incorrect (Test)'),
              ),
              ElevatedButton(
                onPressed: () {
                  _showFeedbackDialog(true); // Simulate correct
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Correct (Test)'),
              ),
            ],
          ),
      ],
    );
  }
  
  // Get sample word based on exercise index
  String _getSampleWord(int index) {
    final words = [
      'through',
      'thought',
      'knowledge',
      'rhythm',
      'pneumonia',
    ];
    
    return index < words.length ? words[index] : 'sample';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Module description
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 233, 240, 252),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              widget.module.type == ModuleType.written
                                  ? Icons.edit
                                  : Icons.record_voice_over,
                              color: widget.module.type == ModuleType.written
                                  ? Colors.blue
                                  : Colors.green,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.module.description,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: widget.module.progressPercentage,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    widget.module.progressPercentage == 1.0
                                        ? Colors.green
                                        : Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Progress: ${widget.module.completedExercises}/${widget.module.totalExercises}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Exercise content
                    _buildExerciseContent(),
                  ],
                ),
              ),
      ),
    );
  }
}