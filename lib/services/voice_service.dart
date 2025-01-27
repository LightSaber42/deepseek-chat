import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' show min;

class VoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isMuted = false;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isMuted => _isMuted;

  String _cleanMarkdown(String text) {
    // Remove code blocks
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');

    // Remove inline code
    text = text.replaceAll(RegExp(r'`[^`]*`'), '');

    // Remove headers
    text = text.replaceAll(RegExp(r'#{1,6}\s'), '');

    // Remove bold/italic markers
    text = text.replaceAll(RegExp(r'\*\*|__|\*|_'), '');

    // Remove links but keep text
    text = text.replaceAll(RegExp(r'\[([^\]]*)\]\([^\)]*\)'), r'$1');

    // Remove bullet points
    text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');

    // Remove numbered lists
    text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // Remove blockquotes
    text = text.replaceAll(RegExp(r'^\s*>\s+', multiLine: true), '');

    // Clean up extra whitespace
    text = text.replaceAll(RegExp(r'\n\s*\n'), '\n')
               .replaceAll(RegExp(r'\s+'), ' ')
               .trim();

    return text;
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted && _isListening) {
      stopListening();
    }
  }

  Future<bool> init() async {
    debugPrint('[TTS] Initializing voice services');
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint('[TTS] Microphone permission denied');
      return false;
    }

    bool available = await _speech.initialize(
      onStatus: (status) {
        debugPrint('[TTS] Speech status: $status');
        if (status == 'notListening') {
          _isListening = false;
        }
      },
      onError: (error) => debugPrint('[TTS] Speech recognition error: $error'),
    );

    if (!available) {
      debugPrint('[TTS] Speech recognition initialization failed');
    }

    // Initialize TTS
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.54);  // 54% of original speed for better comprehension
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      debugPrint('[TTS] Started speaking');
      _isSpeaking = true;
    });

    _tts.setCompletionHandler(() {
      debugPrint('[TTS] Completed speaking');
      _isSpeaking = false;
    });

    _tts.setErrorHandler((msg) {
      debugPrint('[TTS] TTS error: $msg');
      _isSpeaking = false;
    });

    debugPrint('[TTS] Voice services initialized successfully');
    return available;
  }

  Future<void> startListening(void Function(String) onResult) async {
    if (!_speech.isAvailable) {
      throw Exception('Speech recognition not available');
    }
    if (_isMuted) {
      throw Exception('Microphone is muted');
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
    if (text.trim().isEmpty) {
      debugPrint('[TTS] Skipping empty text');
      return;
    }

    // Clean the text before speaking
    final cleanText = _cleanMarkdown(text);
    if (cleanText.isEmpty) {
      debugPrint('[TTS] Skipping - text was empty after cleaning markdown');
      return;
    }

    try {
      debugPrint('[TTS] Starting to speak: "${cleanText.substring(0, min(30, cleanText.length))}..."');

      // If already speaking, queue this text instead of stopping
      if (_isSpeaking) {
        debugPrint('[TTS] Already speaking, waiting for completion before next chunk');
        await _tts.awaitSpeakCompletion(true);
      }

      _isSpeaking = true;
      await _tts.speak(cleanText);
    } catch (e) {
      debugPrint('[TTS] Error in TTS: $e');
      _isSpeaking = false;
    }
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    _isSpeaking = false;
  }
}