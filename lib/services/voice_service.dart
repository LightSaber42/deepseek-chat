import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<bool> init() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      print('Microphone permission denied');
      return false;
    }

    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening') {
          _isListening = false;
        }
      },
      onError: (error) => print('Speech recognition error: $error'),
    );

    if (!available) {
      print('Speech recognition initialization failed');
    }

    await _tts.setSharedInstance(true);
    return available;
  }

  Future<void> startListening(void Function(String) onResult) async {
    if (!_speech.isAvailable) {
      throw Exception('Speech recognition not available');
    }

    _isListening = true;
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
        }
      },
      listenMode: ListenMode.dictation,
      partialResults: false,
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
  }
}