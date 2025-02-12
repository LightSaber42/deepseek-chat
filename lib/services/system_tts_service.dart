import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';
import 'base_tts_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SystemTTSService extends BaseTTSService {
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  TTSServiceOptions _options;
  String _engine;

  SystemTTSService({
    TTSServiceOptions options = const TTSServiceOptions(),
    String engine = "com.google.android.tts",
  }) : _options = options,
       _engine = engine;

  @override
  bool get isListening => _isListening;

  static Future<List<dynamic>> getAvailableEngines() async {
    final FlutterTts tts = FlutterTts();
    try {
      final systemEngines = await tts.getEngines;
      final engines = List<dynamic>.from(systemEngines); // Create a new modifiable list
      engines.add('flutter_tts');  // Add Flutter TTS as an option
      debugPrint('[TTS] Available engines: $engines');
      return engines;
    } catch (e) {
      debugPrint('[TTS] Error getting engines: $e');
      return ['flutter_tts', 'com.google.android.tts'];  // Return both as fallback
    }
  }

  String get currentEngine => _engine;

  @override
  Future<bool> init() async {
    try {
      if (_engine == 'flutter_tts') {
        // For Flutter TTS, don't set the engine
        await _flutterTts.setLanguage(_options.language);
        await _flutterTts.setSpeechRate(_options.rate);
        await _flutterTts.setVolume(_options.volume);
        await _flutterTts.setPitch(_options.pitch);

        if (_options.voice.isNotEmpty) {
          await _flutterTts.setVoice({"name": _options.voice});
        }
      } else {
        // For system TTS engines, set the engine
        await _flutterTts.setEngine(_engine);
        await _flutterTts.setLanguage(_options.language);
        await _flutterTts.setSpeechRate(_options.rate);
        await _flutterTts.setVolume(_options.volume);
        await _flutterTts.setPitch(_options.pitch);

        if (_options.voice.isNotEmpty) {
          await _flutterTts.setVoice({"name": _options.voice});
        }
      }

      // Set up handlers
      _flutterTts.setStartHandler(() {
        debugPrint('[TTS] Started speaking');
        isSpeaking = true;
      });

      _flutterTts.setCompletionHandler(() {
        debugPrint('[TTS] Completed speaking');
        isSpeaking = false;
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('[TTS] Error: $msg');
        isSpeaking = false;
      });

      _flutterTts.setCancelHandler(() {
        debugPrint('[TTS] Cancelled');
        isSpeaking = false;
      });

      await _speech.initialize();
      return true;
    } catch (e) {
      debugPrint('[TTS] Error initializing: $e');
      return false;
    }
  }

  @override
  Future<void> speak(String text) async {
    if (isMuted) return;

    try {
      text = cleanTextForTTS(text);
      debugPrint('[TTS] Speaking text: """$text"""');

      final completer = Completer<void>();

      // Set up one-time completion handler for this utterance
      void completionHandler() {
        debugPrint('[TTS] Completion handler called');
        isSpeaking = false;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      _flutterTts.setCompletionHandler(completionHandler);

      // Start speaking
      isSpeaking = true;
      await _flutterTts.speak(text);

      // Wait for completion or timeout
      try {
        await completer.future.timeout(
          Duration(milliseconds: (text.length * 100) + 1000), // Rough estimate plus buffer
          onTimeout: () {
            debugPrint('[TTS] Speak timeout - forcing completion');
            completionHandler();
          },
        );
      } catch (e) {
        debugPrint('[TTS] Error waiting for completion: $e');
        isSpeaking = false;
      }

    } catch (e) {
      debugPrint('[TTS] Error during speech: $e');
      isSpeaking = false;
      throwServiceError(e);
    }
  }

  @override
  Future<void> bufferText(String text) async {
    if (text.trim().isEmpty) return;
    debugPrint('[TTS] Buffering new text chunk: """$text"""');

    try {
      // Wait for any current speech to finish
      if (isSpeaking) {
        debugPrint('[TTS] Waiting for current speech to finish');
        await stop();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Speak the new text
      await speak(text);

    } catch (e) {
      debugPrint('[TTS] Error in bufferText: $e');
      isSpeaking = false;
      throwServiceError(e);
    }
  }

  @override
  Future<void> stop() async {
    try {
      debugPrint('[TTS] Stopping speech');
      await _flutterTts.stop();
      isSpeaking = false;
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('[TTS] Error stopping speech: $e');
      throwServiceError(e);
    }
  }

  @override
  Future<void> updateOptions(TTSServiceOptions options) async {
    _options = options;
    await init();
  }

  Future<void> updateEngine(String engine) async {
    _engine = engine;
    await init();
  }

  @override
  Future<void> finishSpeaking() async {
    debugPrint('[TTS] Finishing speaking. Buffer: """"""');
    debugPrint('[TTS] Speaking: $isSpeaking');

    if (isSpeaking) {
      debugPrint('[TTS] Waiting for ongoing speech to complete');
      // Add a timeout to prevent infinite waiting
      int attempts = 0;
      while (isSpeaking && attempts < 50) { // 5 second timeout
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (isSpeaking) {
        debugPrint('[TTS] Force stopping speech due to timeout');
        await stop();
      }
      debugPrint('[TTS] Speech completed or stopped');
    }
  }

  @override
  Future<void> stopSpeaking() async {
    await stop();
  }

  @override
  Future<void> startListening(void Function(String) onResult) async {
    if (!await _speech.initialize()) {
      debugPrint('[TTS] Could not initialize speech recognition');
      return;
    }

    _isListening = true;
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: false,
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
    await _speech.stop();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}