import 'package:just_audio/just_audio.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isInitialized = false;

  Future<void> playBackgroundMusic() async {
    if (_isInitialized) return;

    try {
      await _player.setAsset('assets/lofi.mp3');
      await _player.setLoopMode(LoopMode.one); // Loop the track
      await _player.play();

      _isInitialized = true;
      print('🎵 Background music started');
    } catch (e) {
      print('Error playing background music: $e');
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
    _isInitialized = false;
  }

  void dispose() {
    _player.dispose();
  }
}