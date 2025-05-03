import 'package:audioplayers/audioplayers.dart';

class AudioService {
  // Singleton pattern with private constructor
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  // Players - one for background music, multiple for sound effects
  final AudioPlayer _backgroundMusicPlayer = AudioPlayer();
  
  // State tracking
  bool _isInitialized = false;
  bool _isMusicPlaying = false;

  // Initialize the service - make this safe to call multiple times
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Configure background music player
      await _backgroundMusicPlayer.setReleaseMode(ReleaseMode.loop);
      await _backgroundMusicPlayer.setSourceAsset('audio/background_music.mp3');
      await _backgroundMusicPlayer.setVolume(0.5);
      
      _isInitialized = true;
      print('AudioService initialized successfully');
    } catch (e) {
      print('Error initializing AudioService: $e');
    }
  }

  // Play background music - safe to call multiple times
  Future<void> playBackgroundMusic() async {
    if (!_isInitialized) await initialize();
    
    try {
      await _backgroundMusicPlayer.resume();
      _isMusicPlaying = true;
      print('Background music started');
    } catch (e) {
      print('Error playing background music: $e');
    }
  }

  // Pause background music
  Future<void> pauseBackgroundMusic() async {
    try {
      await _backgroundMusicPlayer.pause();
      _isMusicPlaying = false;
      print('Background music paused');
    } catch (e) {
      print('Error pausing background music: $e');
    }
  }

  // Play correct answer sound
  Future<void> playCorrectSound() async {
    try {
      print('Attempting to play correct sound effect');
      
      // Remember if music was playing
      bool wasPlaying = _isMusicPlaying;
      
      // Pause background music temporarily
      if (wasPlaying) {
        await pauseBackgroundMusic();
      }
      
      // Create a temporary player for the sound effect
      final effectPlayer = AudioPlayer();
      await effectPlayer.setVolume(1.0);
      
      // Play the sound effect and wait for it to complete
      await effectPlayer.play(AssetSource('audio/correct.mp3'));
      
      // Set up a listener to restart background music when the effect finishes
      effectPlayer.onPlayerComplete.listen((event) {
        // Clean up the effect player
        effectPlayer.dispose();
        print('Correct sound effect completed');
        
        // Restart background music if it was playing before
        if (wasPlaying) {
          playBackgroundMusic();
        }
      });
      
      print('Correct sound effect started');
    } catch (e) {
      print('Error playing correct sound: $e');
      // Ensure music restarts if there was an error
      if (_isMusicPlaying) {
        playBackgroundMusic();
      }
    }
  }

  // Play wrong answer sound
  Future<void> playWrongSound() async {
    try {
      print('Attempting to play wrong sound effect');
      
      // Remember if music was playing
      bool wasPlaying = _isMusicPlaying;
      
      // Pause background music temporarily
      if (wasPlaying) {
        await pauseBackgroundMusic();
      }
      
      // Create a temporary player for the sound effect
      final effectPlayer = AudioPlayer();
      await effectPlayer.setVolume(1.0);
      
      // Play the sound effect
      await effectPlayer.play(AssetSource('audio/wrong.mp3'));
      
      // Set up a listener to restart background music when the effect finishes
      effectPlayer.onPlayerComplete.listen((event) {
        // Clean up the effect player
        effectPlayer.dispose();
        print('Wrong sound effect completed');
        
        // Restart background music if it was playing before
        if (wasPlaying) {
          playBackgroundMusic();
        }
      });
      
      print('Wrong sound effect started');
    } catch (e) {
      print('Error playing wrong sound: $e');
      // Ensure music restarts if there was an error
      if (_isMusicPlaying) {
        playBackgroundMusic();
      }
    }
  }

  // Dispose of resources - only call when app is shutting down
  Future<void> dispose() async {
    try {
      await _backgroundMusicPlayer.dispose();
      _isInitialized = false;
      _isMusicPlaying = false;
      print('AudioService disposed');
    } catch (e) {
      print('Error disposing AudioService: $e');
    }
  }
  
  // Check if music is currently playing
  bool get isMusicPlaying => _isMusicPlaying;
}