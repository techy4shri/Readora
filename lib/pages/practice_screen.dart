import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:readora/services/custom_practice_service.dart';
import 'package:readora/services/practice_stats_service.dart';
import 'package:readora/services/audio_service.dart';
import 'package:readora/services/user_level_service.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// DrawingArea for handwriting input
class DrawingArea {
  Offset point;
  Paint areaPaint;

  DrawingArea({required this.point, required this.areaPaint});
}

// Enum for feedback states
enum FeedbackState {
  correct,
  wrong,
  noText,
}

class PracticeScreen extends StatefulWidget {
  final PracticeModule practice;

  const PracticeScreen({Key? key, required this.practice}) : super(key: key);

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  int _currentIndex = 0;
  bool _isCompleted = false;
  List<bool> _itemStatus = [];
  bool _isSubmitting = false;
  bool _isProcessingDrawing = false;
  String _recognizedText = '';
  bool _showingFeedback = false;
  
  // Add user level service
  final UserLevelService _userLevelService = UserLevelService();
  
  // Add audio service
  final AudioService _audioService = AudioService();
  
  // Controllers for written responses
  final List<TextEditingController> _textControllers = [];
  
  // Speech recognition (for phonetic practices)
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _speechText = '';
  
  // Drawing capabilities
  List<DrawingArea?> points = [];
  Color selectedColor = Colors.black;
  double strokeWidth = 5.0;
  final textRecognizer = TextRecognizer();
  
  // Add image picker
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  
  @override
  void initState() {
    super.initState();
    _isCompleted = widget.practice.completed;
    
    // Initialize item status and text controllers
    _itemStatus = List.generate(widget.practice.content.length, (_) => false);
    
    // Initialize text controllers
    for (int i = 0; i < widget.practice.content.length; i++) {
      _textControllers.add(TextEditingController());
    }
    
    // Initialize speech recognition for phonetic practices
    if (widget.practice.type == PracticeType.phonetic) {
      _initSpeech();
    }
  }
  
  @override
  void dispose() {
    // Dispose text controllers
    for (var controller in _textControllers) {
      controller.dispose();
    }
    textRecognizer.close();
    super.dispose();
  }
  
  // Initialize speech recognition
  Future<void> _initSpeech() async {
    _speechEnabled = await _speech.initialize();
    setState(() {});
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
      _isListening = true;
      _speechText = '';
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
      
      // For phonetic exercise, check if the spoken word matches the target
      if (widget.practice.type == PracticeType.phonetic) {
        final targetWord = widget.practice.content[_currentIndex].toLowerCase();
        if (_speechText.contains(targetWord)) {
          _itemStatus[_currentIndex] = true;
          // Show feedback popup for correct answer
          _showFeedbackPopup(FeedbackState.correct);
        } else if (_speechText.isNotEmpty) {
          // Show feedback popup for wrong answer
          _showFeedbackPopup(FeedbackState.wrong);
        }
      }
    });
  }
  
  Future<void> _checkWrittenResponse() async {
    final response = _textControllers[_currentIndex].text.trim().toLowerCase();
    final target = widget.practice.content[_currentIndex].toLowerCase();
    
    bool isCorrect = false;
    
    // Different comparison logic based on practice type
    switch (widget.practice.type) {
      case PracticeType.letterWriting:
        isCorrect = response == target;
        break;
      case PracticeType.sentenceWriting:
        // More lenient check for sentences - remove punctuation and extra spaces
        final cleanTarget = target.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ');
        final cleanResponse = response.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ');
        isCorrect = cleanResponse == cleanTarget;
        break;
      case PracticeType.letterReversal:
        // Check if user entered either of the two options in the pair
        final options = target.split('/');
        isCorrect = options.contains(response);
        break;
      case PracticeType.vowelSounds:
        isCorrect = response == target;
        break;
      default:
        isCorrect = response == target;
    }
    
    setState(() {
      _itemStatus[_currentIndex] = isCorrect;
    });
    
    // Show feedback popup based on result
    if (response.isEmpty) {
      _showFeedbackPopup(FeedbackState.noText);
    } else if (isCorrect) {
      _showFeedbackPopup(FeedbackState.correct);
    } else {
      _showFeedbackPopup(FeedbackState.wrong);
    }
  }
  
  Future<void> _processDrawing() async {
    if (points.isEmpty) {
      _showFeedbackPopup(FeedbackState.noText);
      return;
    }
    
    setState(() {
      _isProcessingDrawing = true;
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
      
      // Draw the points - scale them to fit the image size
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
        
        // Add debugging
        debugPrint('Raw recognized text: $extracted');
        
        setState(() {
          // Always set the recognized text, even if empty
          if (extracted.isEmpty) {
            _recognizedText = "No text detected";
          } else {
            _recognizedText = extracted;
          }
          debugPrint('Recognized text set to: "$_recognizedText"');
          
          // Default to incorrect
          _itemStatus[_currentIndex] = false;
          
          // Check if the recognized text matches the target
          final target = widget.practice.content[_currentIndex].toLowerCase();
          
          if (widget.practice.type == PracticeType.letterWriting) {
            // For letters, be more specific in matching
            debugPrint('Letter writing check: extracted="$extracted", target="$target"');
            // Convert both to single characters if possible
            final firstCharExtracted = extracted.isNotEmpty ? extracted[0] : '';
            final firstCharTarget = target.isNotEmpty ? target[0] : '';
            
            // Check exact match or first character match
            if (extracted == target) {
              _itemStatus[_currentIndex] = true;
              debugPrint('Letter match found: ${_itemStatus[_currentIndex]}');
            }
          } else if (widget.practice.type == PracticeType.sentenceWriting) {
            // For sentences, use more lenient comparison
            final cleanTarget = target.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
            final cleanExtracted = extracted.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
            
            // Check if the extracted text contains at least 75% of the target words
            final targetWords = cleanTarget.split(' ');
            final extractedWords = cleanExtracted.split(' ');
            
            int matchedWords = 0;
            for (final targetWord in targetWords) {
              if (targetWord.isNotEmpty && extractedWords.any((word) => 
                  word.isNotEmpty && 
                  (word.contains(targetWord) || targetWord.contains(word)))) {
                matchedWords++;
              }
            }
            
            final matchPercentage = targetWords.isEmpty ? 0 : (matchedWords / targetWords.length) * 100;
            
            // Debug the matching process
            print('Target: $cleanTarget');
            print('Extracted: $cleanExtracted');
            print('Match percentage: $matchPercentage%');
            
            if (matchPercentage >= 75) {
              _itemStatus[_currentIndex] = true;
            }
          } else if (widget.practice.type == PracticeType.letterReversal) {
            // Process letter reversal - check for either option in pair
            final options = target.split('/');
            if (options.any((option) => extracted.contains(option))) {
              _itemStatus[_currentIndex] = true;
            }
          } else if (widget.practice.type == PracticeType.vowelSounds) {
            // For vowel sounds, be a bit more lenient
            if (extracted == target) {
              _itemStatus[_currentIndex] = true;
            }
          } else {
            // For other types, use more specific checks
            if (extracted == target) {
              _itemStatus[_currentIndex] = true;
            }
          }
          
          // Add a final debug statement
          debugPrint('Final status: ${_itemStatus[_currentIndex]}');
        });
        
        // Show feedback popup based on result
        if (extracted.isEmpty) {
          _showFeedbackPopup(FeedbackState.noText);
        } else if (_itemStatus[_currentIndex]) {
          _showFeedbackPopup(FeedbackState.correct);
        } else {
          _showFeedbackPopup(FeedbackState.wrong);
        }
      }
    } catch (e) {
      debugPrint('Error in _processDrawing: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing drawing: ${e.toString()}')),
      );
      
      // Show no text detected popup
      _showFeedbackPopup(FeedbackState.noText);
    } finally {
      setState(() {
        _isProcessingDrawing = false;
        // If text is still empty after processing, set a message but don't change status
        if (_recognizedText.isEmpty) {
          _recognizedText = "No text detected";
          // Only set to false if we don't already have a status for this item
          if (!_itemStatus[_currentIndex]) {
            _itemStatus[_currentIndex] = false;
          }
          
          // Show no text detected popup
          _showFeedbackPopup(FeedbackState.noText);
        }
      });
    }
  }
  
  // Show feedback popup
  void _showFeedbackPopup(FeedbackState state) {
    // Don't show feedback if already showing another feedback
    if (_showingFeedback) return;
    
    setState(() {
      _showingFeedback = true;
    });
    
    // Define content based on state
    String gifAsset;
    String heading;
    String message;
    Color headerColor;
    
    switch (state) {
      case FeedbackState.correct:
        gifAsset = 'assets/gifs/correct.gif';
        heading = 'Great job!';
        message = 'Your answer is correct. Keep up the good work!';
        headerColor = Colors.green;
        _audioService.playCorrectSound(); // Play correct sound
        
        // Record successful attempt
        _userLevelService.recordExerciseAttempt(
          exerciseId: '${widget.practice.id}_$_currentIndex',
          isCorrect: true,
        );
        break;
      case FeedbackState.wrong:
        gifAsset = 'assets/gifs/wrong.gif';
        heading = 'Oops!';
        message = 'Your answer is incorrect. Keep practicing!';
        headerColor = const Color.fromARGB(255, 194, 185, 18);
        _audioService.playWrongSound(); // Play wrong sound
        
        // Record unsuccessful attempt
        _userLevelService.recordExerciseAttempt(
          exerciseId: '${widget.practice.id}_$_currentIndex',
          isCorrect: false,
        );
        break;
      case FeedbackState.noText:
        gifAsset = 'assets/gifs/confused.gif';
        heading = 'No Text Detected';
        message = 'I couldn\'t read your answer. Please try again.';
        headerColor = const Color.fromARGB(255, 114, 63, 151);
        _audioService.playWrongSound(); // Play wrong sound for this too
        
        // Don't record no-text attempts as they are ambiguous
        break;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button at the top right
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _showingFeedback = false;
                      });
                    },
                    child: const Icon(
                      Icons.close,
                      color: Colors.grey,
                      size: 24,
                    ),
                  ),
                ),

                // GIF animation
                SizedBox(
                  height: 120,
                  width: 120,
                  child: Image.asset(
                    gifAsset,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),

                // Heading
                Text(
                  heading,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: headerColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Message
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF324259),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Continue button
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _showingFeedback = false;
                    });
                    
                    // If answer is correct, move to next item automatically
                    if (state == FeedbackState.correct && _itemStatus[_currentIndex]) {
                      _nextItem();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: headerColor,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    state == FeedbackState.correct ? 'Continue' : 'Try Again',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  } 
  
  // Helper method for vowel sound comparison
  bool _compareVowelSounds(String extracted, String target) {
    // Get all vowels from both strings
    final targetVowels = target.replaceAll(RegExp(r'[^aeiou]'), '');
    final extractedVowels = extracted.replaceAll(RegExp(r'[^aeiou]'), '');
    
    // If vowel count and pattern are similar, consider it correct
    return targetVowels.length == extractedVowels.length &&
          targetVowels.length > 0 &&
          extractedVowels.length > 0;
  }
  
  void _clearDrawing() {
    setState(() {
      points.clear();
      _recognizedText = '';
      // Don't reset status - only the drawing
    });
  }
  
  void _nextItem() {
    if (_currentIndex < widget.practice.content.length - 1) {
      setState(() {
        _currentIndex++;
        _speechText = '';
        _recognizedText = '';
        points.clear();
      });
    } else {
      _completePractice();
    }
  }
  
  void _previousItem() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _speechText = '';
        _recognizedText = '';
        points.clear();
      });
    }
  }
  
  Future<void> _completePractice() async {
    // Check if all items have been answered correctly
    final allCorrect = _itemStatus.every((status) => status);
    
    if (!allCorrect) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not all items completed'),
          content: const Text('Please complete all items correctly before finishing.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    
    setState(() {
      _isSubmitting = true;
    });
    
    try {
      // Mark the practice as completed
      await CustomPracticeService.markPracticeCompleted(widget.practice.id);
      
      // Update practice statistics
      await PracticeStatsService.updateStatsAfterCompletion(
        widget.practice.type.toString().split('.').last
      );
      
      // Record practice completion in daily stats
      await _recordPracticeCompletion();
      
      setState(() {
        _isCompleted = true;
        _isSubmitting = false;
      });
      
      // Show success dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Practice Completed!'),
            content: const Text('Great job! You have successfully completed this practice.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Return to home
                },
                child: const Text('Return to Home'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error completing practice: ${e.toString()}')),
      );
    }
  }
  
  // Record daily practice completion in Firebase
  Future<void> _recordPracticeCompletion() async {
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
      
      // Get current stats document or create if it doesn't exist
      final docSnapshot = await dailyStatsRef.get();
      
      final practiceId = widget.practice.id;
      final practiceType = widget.practice.type.toString().split('.').last;
      
      if (docSnapshot.exists) {
        // Check if this practice has already been recorded to avoid duplicates
        final data = docSnapshot.data() as Map<String, dynamic>;
        final practiceIds = List<String>.from(data['practiceIds'] ?? []);
        
        if (practiceIds.contains(practiceId)) {
          print('Practice $practiceId already recorded for today, skipping');
          return; // Skip if already recorded
        }
        
        // Update existing document
        await dailyStatsRef.update({
          'completedPractices': FieldValue.increment(1),
          'practiceIds': FieldValue.arrayUnion([practiceId]),
          'practiceTypes': FieldValue.arrayUnion([practiceType]),
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        print('Updated existing stats document for $dateStr with practice $practiceId');
      } else {
        // Create new document with both module and practice fields
        await dailyStatsRef.set({
          'userId': user.uid,
          'date': dateStr,
          'completedModules': 0, // Initialize module count
          'moduleIds': [], // Initialize module ids array
          'completedPractices': 1, // First practice completion
          'practiceIds': [practiceId],
          'practiceTypes': [practiceType],
          'timestamp': FieldValue.serverTimestamp(),
        });

        print('Created new stats document for $dateStr with practice $practiceId');
      }

      // Verify the data was saved correctly
      final verificationDoc = await dailyStatsRef.get();
      if (verificationDoc.exists) {
        final data = verificationDoc.data() as Map<String, dynamic>;
        final practiceIds = List<String>.from(data['practiceIds'] ?? []);
        print('Verification: Document contains ${practiceIds.length} practices: $practiceIds');
      } else {
        print('ERROR: Failed to verify document - not found after save!');
      }
      
      print('Practice completion recorded: $practiceId on $dateStr');
      
      // Also store locally to prevent duplicate counting
      await _storeLocalPracticeCompletion(practiceId);
      
    } catch (e) {
      print('Error recording practice completion: $e');
      // Continue execution - this isn't a critical error that should block the user
    }
  }

  // Store completed practice locally to prevent duplicate counting
  Future<void> _storeLocalPracticeCompletion(String practiceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      // Get existing completed practices for today
      final completedPractices = prefs.getStringList('completed_practices:$dateStr') ?? [];

      if (!completedPractices.contains(practiceId)) {
        completedPractices.add(practiceId);
        await prefs.setStringList('completed_practices:$dateStr', completedPractices);
        print('Stored practice $practiceId in local storage');
      }
    } catch (e) {
      print('Error storing local practice completion: $e');
    }
  }
  
  String _getInstructionText() {
    switch (widget.practice.type) {
      case PracticeType.letterWriting:
        return 'Draw the letter below:';
      case PracticeType.sentenceWriting:
        return 'Write the sentence below:';
      case PracticeType.phonetic:
        return 'Say the word below out loud:';
      case PracticeType.letterReversal:
        return 'Draw one of the words from the pair:';
      case PracticeType.vowelSounds:
        return 'Write the word with the correct vowel sounds:';
      default:
        return 'Complete the exercise:';
    }
  }
  
  // Take photo for OCR
  Future<void> _takePhoto() async {
    setState(() {
      _isProcessingDrawing = true;
      _recognizedText = '';
      _itemStatus[_currentIndex] = false;
    });
    
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) {
        setState(() {
          _isProcessingDrawing = false;
        });
        return;
      }
      
      _imageFile = File(photo.path);
      final inputImage = InputImage.fromFilePath(photo.path);
      final recognizedText = await textRecognizer.processImage(inputImage);
      
      final extractedText = recognizedText.text.trim();
      
      setState(() {
        _recognizedText = extractedText.isEmpty 
            ? "No text detected in image" 
            : extractedText;
        
        // Always set to false if empty text is detected
        if (extractedText.isEmpty) {
          _itemStatus[_currentIndex] = false;
          _isProcessingDrawing = false;
          _showFeedbackPopup(FeedbackState.noText);
          return;
        }
        
        // Check if the recognized text matches the current exercise
        final currentContent = widget.practice.content[_currentIndex].toLowerCase();
        final cleanRecognized = extractedText.toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();
        final cleanTarget = currentContent
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();
          
        // Extra check for empty text after cleaning
        if (cleanRecognized.isEmpty) {
          _itemStatus[_currentIndex] = false;
          _isProcessingDrawing = false;
          _showFeedbackPopup(FeedbackState.noText);
          return;
        }
          
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
        _itemStatus[_currentIndex] = matchPercentage >= 100;
        _isProcessingDrawing = false;
        
        // Show appropriate feedback
        if (_itemStatus[_currentIndex]) {
          _showFeedbackPopup(FeedbackState.correct);
        } else {
          _showFeedbackPopup(FeedbackState.wrong);
        }
      });
      
    } catch (e) {
      setState(() {
        _recognizedText = 'Error: ${e.toString()}';
        _isProcessingDrawing = false;
        _itemStatus[_currentIndex] = false;
      });
      
      _showFeedbackPopup(FeedbackState.noText);
    }
  }

  // Pick image from gallery
  Future<void> _pickImage() async {
    setState(() {
      _isProcessingDrawing = true;
      _recognizedText = '';
      _itemStatus[_currentIndex] = false;
    });
    
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
      if (photo == null) {
        setState(() {
          _isProcessingDrawing = false;
        });
        return;
      }
      
      _imageFile = File(photo.path);
      final inputImage = InputImage.fromFilePath(photo.path);
      final recognizedText = await textRecognizer.processImage(inputImage);
      
      final extractedText = recognizedText.text.trim();
      
      setState(() {
        _recognizedText = extractedText.isEmpty 
            ? "No text detected in image" 
            : extractedText;
        
        // Always set to false if empty text is detected
        if (extractedText.isEmpty) {
          _itemStatus[_currentIndex] = false;
          _isProcessingDrawing = false;
          _showFeedbackPopup(FeedbackState.noText);
          return;
        }
        
        // Check if the recognized text matches the current exercise
        final currentContent = widget.practice.content[_currentIndex].toLowerCase();
        final cleanRecognized = extractedText.toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();
        final cleanTarget = currentContent
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();
        
        // Extra check for empty text after cleaning
        if (cleanRecognized.isEmpty) {
          _itemStatus[_currentIndex] = false;
          _isProcessingDrawing = false;
          _showFeedbackPopup(FeedbackState.noText);
          return;
        }
          
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
        _itemStatus[_currentIndex] = matchPercentage >= 75;
        _isProcessingDrawing = false;
        
        // Show appropriate feedback
        if (_itemStatus[_currentIndex]) {
          _showFeedbackPopup(FeedbackState.correct);
        } else {
          _showFeedbackPopup(FeedbackState.wrong);
        }
      });
      
    } catch (e) {
      setState(() {
        _recognizedText = 'Error: ${e.toString()}';
        _isProcessingDrawing = false;
        _itemStatus[_currentIndex] = false;
      });
      
      _showFeedbackPopup(FeedbackState.noText);
    }
  }
  
  // Process image with OCR
  Future<void> _processImageWithOCR(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await textRecognizer.processImage(inputImage);
      
      final extractedText = recognizedText.text.trim();
      debugPrint('OCR extracted text: $extractedText');
      
      setState(() {
        _recognizedText = extractedText.isEmpty 
            ? "No text detected in image" 
            : extractedText;
        
        // Set to false immediately if no text was detected
        if (extractedText.isEmpty) {
          _itemStatus[_currentIndex] = false;
          _showFeedbackPopup(FeedbackState.noText);
          return;
        }
        
        // Check if the text matches the expected sentence
        final target = widget.practice.content[_currentIndex].toLowerCase();
        final extracted = extractedText.toLowerCase();
        
        // For sentences, use more lenient comparison
        final cleanTarget = target.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
        final cleanExtracted = extracted.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
        
        // Additional check for empty extracted text after cleaning
        if (cleanExtracted.isEmpty) {
          _itemStatus[_currentIndex] = false;
          _showFeedbackPopup(FeedbackState.noText);
          return;
        }
        
        // Check if the extracted text contains at least 75% of the target words
        final targetWords = cleanTarget.split(' ');
        final extractedWords = cleanExtracted.split(' ');
        
        int matchedWords = 0;
        for (final targetWord in targetWords) {
          if (targetWord.isNotEmpty && extractedWords.any((word) => 
              word.isNotEmpty && 
              (word.contains(targetWord) || targetWord.contains(word)))) {
            matchedWords++;
          }
        }
        
        final matchPercentage = targetWords.isEmpty ? 0 : (matchedWords / targetWords.length) * 100;
        
        // Debug the matching process
        debugPrint('Target: $cleanTarget');
        debugPrint('Extracted: $cleanExtracted');
        debugPrint('Match percentage: $matchPercentage%');
        
        if (matchPercentage >= 75) {
          _itemStatus[_currentIndex] = true;
          _showFeedbackPopup(FeedbackState.correct);
        } else {
          _itemStatus[_currentIndex] = false;
          _showFeedbackPopup(FeedbackState.wrong);
        }
      });
    } catch (e) {
      debugPrint('Error in OCR processing: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: ${e.toString()}')),
      );
      // Make sure to set status to false on error
      setState(() {
        _itemStatus[_currentIndex] = false;
      });
      
      _showFeedbackPopup(FeedbackState.noText);
    } finally {
      setState(() {
        _isProcessingDrawing = false;
      });
    }
  }
  
  Widget _buildOCRControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Camera button - removed gallery button and made camera button full width
        ElevatedButton.icon(
          onPressed: _takePhoto,
          icon: const Icon(Icons.camera_alt,color: Colors.white, size:16),
          label: const Text('Take Photo',
            style: TextStyle(fontSize: 14, color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F5377),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Even smaller padding
            minimumSize: const Size(80, 28), // Fixed smaller size
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Show image preview if available
        if (_imageFile != null)
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _imageFile!,
                fit: BoxFit.cover,
              ),
            ),
          ),
        
        const SizedBox(height: 16),
        
        // Recognized text display (if available)
        if (_recognizedText.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _itemStatus[_currentIndex] ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _itemStatus[_currentIndex] ? Colors.green : Colors.red,
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
                  _recognizedText,
                  style: TextStyle(
                    fontSize: 16,
                    color: _itemStatus[_currentIndex] ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _itemStatus[_currentIndex] ? Icons.check_circle : Icons.cancel,
                      color: _itemStatus[_currentIndex] ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _itemStatus[_currentIndex] ? 'You got this one!' : 'Try again',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _itemStatus[_currentIndex] ? Colors.green[700] : Colors.red[700],
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

  @override
  Widget build(BuildContext context) {
    // If already completed, show completed screen
    if (_isCompleted) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.practice.title,
            style: const TextStyle(
              color: Color(0xFF324259),
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF324259),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 80,
              ),
              const SizedBox(height: 24),
              const Text(
                'Practice Completed!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF324259),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You have already completed ${widget.practice.title}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F5377),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Return to Home'),
              ),
            ],
          ),
        ),
      );
    }
    
    final currentItem = widget.practice.content[_currentIndex];
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.practice.title,
          style: const TextStyle(
            color: Color(0xFF324259),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF324259),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress indicator
                LinearProgressIndicator(
                  value: (_currentIndex + 1) / widget.practice.content.length,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1F5377)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Item ${_currentIndex + 1} of ${widget.practice.content.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Instructions
                Text(
                  _getInstructionText(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF324259),
                  ),
                ),
                const SizedBox(height: 4),
                
                // Target content display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
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
                  child: Text(
                    currentItem,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF324259),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),
                
                // Input method based on practice type
                if (widget.practice.type == PracticeType.phonetic)
                  _buildPhoneticInput()
                else if (widget.practice.type == PracticeType.sentenceWriting)
                  _buildOCRControls() // Use OCR controls for sentence writing
                else if (widget.practice.type == PracticeType.letterWriting || 
                         widget.practice.type == PracticeType.vowelSounds ||
                         widget.practice.type == PracticeType.letterReversal)
                  _buildDrawingInput()
                else
                  _buildWrittenInput(),
                
                // Input feedback
                if (_itemStatus[_currentIndex] && (_recognizedText.isNotEmpty || widget.practice.type != PracticeType.letterWriting))
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Correct!',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const Spacer(),
                
                // Navigation buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    if (_currentIndex > 0)
                      ElevatedButton(
                        onPressed: _previousItem,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[300],
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Previous'),
                      )
                    else
                      const SizedBox(width: 40), // Placeholder for alignment
                    
                    // Next/Finish button
                    ElevatedButton(
                      onPressed: _itemStatus[_currentIndex]
                          ? (_currentIndex < widget.practice.content.length - 1
                              ? _nextItem
                              : _completePractice)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F5377),
                        disabledBackgroundColor: Colors.grey,
                      ),
                      child: Text(
                        _currentIndex < widget.practice.content.length - 1
                            ? 'Next'
                            : 'Finish',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Overlay loading indicator
          if (_isSubmitting || _isProcessingDrawing)
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
  
  Widget _buildPhoneticInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Click the microphone and say the word above',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isListening ? _stopListening : _startListening,
          icon: Icon(_isListening ? Icons.stop : Icons.mic),
          label: Text(_isListening ? 'Stop' : 'Start Speaking'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isListening ? Colors.red : const Color(0xFF1F5377),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        if (_speechText.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _itemStatus[_currentIndex] ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _itemStatus[_currentIndex] ? Colors.green : Colors.red,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You said:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _speechText,
                  style: TextStyle(
                    fontSize: 18,
                    color: _itemStatus[_currentIndex] ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  Widget _buildDrawingInput() {
    // If it's sentence writing, show camera options instead of drawing pad
    if (widget.practice.type == PracticeType.sentenceWriting) {
      return _buildImageCaptureInput();
    }
    
    // Otherwise, keep the original drawing input
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: MediaQuery.of(context).size.height * 0.15, // Reduced from 0.18
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8), // Reduced from 12
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2), // Lighter shadow
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
                  borderRadius: BorderRadius.circular(8), // Reduced from 12
                  child: CustomPaint(
                    painter: MyCustomPainter(points: points),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 4), // Reduced from 8
          
          // Drawing controls - More compact buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _clearDrawing,
                icon: const Icon(Icons.clear, size: 14, color: Colors.white), // Smaller icon
                label: const Text(
                  'Clear', 
                  style: TextStyle(fontSize: 12, color: Colors.white), // Smaller text
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Even smaller padding
                  minimumSize: const Size(70, 28), // Fixed smaller size
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12), // Reduced from 16
              ElevatedButton.icon(
                onPressed: _processDrawing,
                icon: const Icon(Icons.check, size: 14, color: Colors.white), // Smaller icon
                label: const Text(
                  'Analyze', 
                  style: TextStyle(fontSize: 12, color: Colors.white), // Smaller text
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F5377),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Even smaller padding
                  minimumSize: const Size(80, 28), // Fixed smaller size
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 4), // Reduced from 8
          
          // Display recognized text with a smaller fixed height
          Container(
            height: MediaQuery.of(context).size.height * 0.06,
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _recognizedText.isEmpty
                  ? Colors.grey.withOpacity(0.1)
                  : (_itemStatus[_currentIndex] ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _recognizedText.isEmpty
                    ? Colors.grey
                    : (_itemStatus[_currentIndex] ? Colors.green : Colors.red),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recognized:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  // Here's the fix - show the recognized text even if empty
                  _recognizedText.isEmpty 
                      ? 'Draw and click "Analyze"' 
                      : _recognizedText,
                  style: TextStyle(
                    fontSize: 12,
                    color: _recognizedText.isEmpty
                        ? Colors.grey
                        : (_itemStatus[_currentIndex] ? Colors.green : Colors.red),
                  ),
                  maxLines: 1, // Reduced to 1 line since it's just a letter
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Add a new method for image capture interface
  Widget _buildImageCaptureInput() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Show captured image or placeholder
          Container(
            height: MediaQuery.of(context).size.height * 0.25,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withOpacity(0.5)),
            ),
            child: _imageFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _imageFile!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.camera_alt_outlined,
                          size: 40,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Take a picture of your written sentence',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),
          
          const SizedBox(height: 8),
          
          // Camera button only
          ElevatedButton.icon(
            onPressed: () => _captureImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('Take Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F5377),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(80, 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Display recognized text with scrollable container for longer sentences
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _recognizedText.isEmpty
                    ? Colors.grey.withOpacity(0.1)
                    : (_itemStatus[_currentIndex] ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _recognizedText.isEmpty
                      ? Colors.grey
                      : (_itemStatus[_currentIndex] ? Colors.green : Colors.red),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Recognized Text:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_recognizedText.isNotEmpty)
                        Icon(
                          _itemStatus[_currentIndex] ? Icons.check_circle : Icons.error,
                          color: _itemStatus[_currentIndex] ? Colors.green : Colors.red,
                          size: 16,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        _recognizedText.isEmpty
                            ? 'Take a picture to scan text'
                            : _recognizedText,
                        style: TextStyle(
                          fontSize: 14,
                          color: _recognizedText.isEmpty
                              ? Colors.grey
                              : (_itemStatus[_currentIndex] ? Colors.green[800] : Colors.red[800]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Add method to capture image
  Future<void> _captureImage(ImageSource source) async {
    try {
      setState(() {
        _isProcessingDrawing = true; // Reuse this flag for image processing
      });
      
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      
      if (pickedFile == null) {
        setState(() {
          _isProcessingDrawing = false;
        });
        return;
      }
      
      final File imageFile = File(pickedFile.path);
      setState(() {
        _imageFile = imageFile;
      });
      
      // Process the image with OCR
      await _processImageWithOCR(imageFile);
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing image: ${e.toString()}')),
      );
      setState(() {
        _isProcessingDrawing = false;
      });
      
      _showFeedbackPopup(FeedbackState.noText);
    }
  }
  
  Widget _buildWrittenInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _textControllers[_currentIndex],
          decoration: InputDecoration(
            hintText: 'Type your answer here...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          style: const TextStyle(fontSize: 18),
          maxLines: widget.practice.type == PracticeType.sentenceWriting ? 3 : 1,
          onChanged: (value) {
            // For sentence writing, check as typing
            if (widget.practice.type == PracticeType.sentenceWriting) {
              _checkWrittenResponse();
            }
          },
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _checkWrittenResponse,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F5377),
          ),
          child: const Text('Check Answer'),
        ),
      ],
    );
  }
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

    // Draw points with thicker lines for better visibility
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
    // Always repaint when points change to ensure immediate feedback
    return true;
  }
}