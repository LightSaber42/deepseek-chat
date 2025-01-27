import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;

  Future<void> init() async {
    await _speech.initialize();
    await _tts.setSharedInstance(true);
  }

  Future<String> listen() async {
    String transcript = '';
    _isListening = true;

    await _speech.listen(
      onResult: (result) => transcript = result.recognizedWords,
      listenFor: const Duration(seconds: 30),
    );

    _isListening = false;
    return transcript;
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
  }
}