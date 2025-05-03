import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Enum for module types
enum ModuleType { written, speech }

// Practice module model class
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

// PracticeModuleService to manage modules across the app
class PracticeModuleService {
  static const String _modulesKey = 'practice_modules';
  static const String _completedModulesKey = 'completed_modules_today';
  static List<PracticeModule>? _cachedModules;
  static final StreamController<List<PracticeModule>> _moduleStreamController = 
      StreamController<List<PracticeModule>>.broadcast();
  
  // Get stream for reactive UI updates
  static Stream<List<PracticeModule>> get moduleStream => _moduleStreamController.stream;
  
  // Get default modules
  static List<PracticeModule> getDefaultModules() {
    return [
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
  }
  
  // Initialize the service
  static Future<void> initialize() async {
    await getModules();
  }

  // Get modules from SharedPreferences
  static Future<List<PracticeModule>> getModules() async {
    // Return cached modules if available
    if (_cachedModules != null) {
      return _cachedModules!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final savedModules = prefs.getString(_modulesKey);
    
    if (savedModules != null) {
      try {
        final List<dynamic> decodedModules = json.decode(savedModules);
        _cachedModules = decodedModules
            .map((moduleJson) => PracticeModule.fromJson(moduleJson))
            .toList();
        
        // Make sure all existing modules are included
        final defaultModules = getDefaultModules();
        for (final defaultModule in defaultModules) {
          final existingModuleIndex = _cachedModules!.indexWhere((m) => m.id == defaultModule.id);
          if (existingModuleIndex == -1) {
            _cachedModules!.add(defaultModule);
          }
        }
      } catch (e) {
        print('Error loading saved modules: $e');
        _cachedModules = getDefaultModules();
        // Save the default modules to fix corrupt data
        await _saveModules(_cachedModules!);
      }
    } else {
      _cachedModules = getDefaultModules();
      // Save the default modules for first-time initialization
      await _saveModules(_cachedModules!);
    }
    
    // Notify listeners
    _moduleStreamController.add(_cachedModules!);
    
    return _cachedModules!;
  }
  
  // Get popular modules (subset of all modules)
  static Future<List<PracticeModule>> getPopularModules() async {
    final allModules = await getModules();
    // Return first 4 modules as popular
    return allModules.take(4).toList();
  }
  
  // Get a single module by ID
  static Future<PracticeModule?> getModuleById(String id) async {
    final modules = await getModules();
    final moduleIndex = modules.indexWhere((m) => m.id == id);
    
    if (moduleIndex != -1) {
      return modules[moduleIndex];
    }
    return null;
  }
  
  // Update a module's progress
  static Future<void> updateModuleProgress(String moduleId, int completedExercises) async {
    if (_cachedModules == null) {
      await getModules();
    }
    
    final moduleIndex = _cachedModules!.indexWhere((m) => m.id == moduleId);
    
    if (moduleIndex != -1) {
      final module = _cachedModules![moduleIndex];
      // Only update if the new completion count is higher than the current one
      if (completedExercises > module.completedExercises) {
        _cachedModules![moduleIndex] = module.copyWith(
          completedExercises: completedExercises
        );
        
        await _saveModules(_cachedModules!);
        // Notify listeners
        _moduleStreamController.add(_cachedModules!);
        
        print('Module "$moduleId" progress updated: $completedExercises');
        
        // If the module is now fully completed, record it
        if (completedExercises >= module.totalExercises && 
            module.completedExercises < module.totalExercises) {
          await recordModuleCompletion(moduleId);
        }
      }
    }
  }
  
  // Record that a module was fully completed today
  static Future<void> recordModuleCompletion(String moduleId) async {
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
      
      if (docSnapshot.exists) {
        // Update existing document
        await dailyStatsRef.update({
          'completedModules': FieldValue.increment(1),
          'moduleIds': FieldValue.arrayUnion([moduleId]),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new document
        await dailyStatsRef.set({
          'userId': user.uid,
          'date': dateStr,
          'completedModules': 1,
          'moduleIds': [moduleId],
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      
      // Also store locally to prevent duplicate counting if user completes again
      await _storeLocalCompletion(moduleId);
      
      print('Module completion recorded for $moduleId on $dateStr');
    } catch (e) {
      print('Error recording module completion: $e');
    }
  }
  
  // Store completed module locally to prevent duplicate counting
  static Future<void> _storeLocalCompletion(String moduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      // Get existing completed modules for today
      final completedModules = prefs.getStringList('$_completedModulesKey:$dateStr') ?? [];
      
      if (!completedModules.contains(moduleId)) {
        completedModules.add(moduleId);
        await prefs.setStringList('$_completedModulesKey:$dateStr', completedModules);
      }
    } catch (e) {
      print('Error storing local completion: $e');
    }
  }
  
  // Get the number of modules completed today
  static Future<int> getCompletedModulesToday() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 0;
      
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      // Check Firebase for today's stats
      final docSnapshot = await FirebaseFirestore.instance
          .collection('userStats')
          .doc('${user.uid}_$dateStr')
          .get();
      
      if (docSnapshot.exists && docSnapshot.data()!.containsKey('completedModules')) {
        return docSnapshot.data()!['completedModules'] as int;
      }
      
      return 0;
    } catch (e) {
      print('Error getting completed modules count: $e');
      return 0;
    }
  }
  
  // Reset a module's progress
  static Future<void> resetModuleProgress(String moduleId) async {
    if (_cachedModules == null) {
      await getModules();
    }
    
    final moduleIndex = _cachedModules!.indexWhere((m) => m.id == moduleId);
    
    if (moduleIndex != -1) {
      _cachedModules![moduleIndex] = _cachedModules![moduleIndex].copyWith(
        completedExercises: 0
      );
      
      await _saveModules(_cachedModules!);
      // Notify listeners
      _moduleStreamController.add(_cachedModules!);
      
      print('Module "$moduleId" progress reset');
    }
  }
  
  // Save modules to SharedPreferences
  static Future<void> _saveModules(List<PracticeModule> modules) async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      final modulesJson = modules.map((module) => module.toJson()).toList();
      await prefs.setString(_modulesKey, json.encode(modulesJson));
      print('Modules saved successfully: ${modulesJson.length} modules');
    } catch (e) {
      print('Error saving modules: $e');
    }
  }
  
  // Dispose resources
  static void dispose() {
    _moduleStreamController.close();
  }
}