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
  Function? _onTtsComplete;
  bool _isProcessingLastChunk = false;
  Function? _onStateChange;

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
        bool wasListening = _isListening;
        if (status == 'notListening' || status == 'done') {
          _isListening = false;
        } else if (status == 'listening') {
          _isListening = true;
        }
        // Notify if state changed
        if (wasListening != _isListening) {
          _onStateChange?.call();
        }
      },
      onError: (error) {
        debugPrint('[TTS] Speech recognition error: $error');
        _isListening = false;
        _onStateChange?.call();
      },
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
      debugPrint('[TTS] Completed speaking chunk');
      _isSpeaking = false;
      if (_isProcessingLastChunk) {
        debugPrint('[TTS] This was the last chunk, triggering completion');
        _isProcessingLastChunk = false;
        onTtsQueueComplete();
      }
    });

    _tts.setErrorHandler((msg) {
      debugPrint('[TTS] TTS error: $msg');
      _isSpeaking = false;
      _isProcessingLastChunk = false;
    });

    debugPrint('[TTS] Voice services initialized successfully');
    return available;
  }

  Future<void> startListening(void Function(String) onResult) async {
    if (!_speech.isAvailable) {
      debugPrint('[TTS] Speech recognition not available');
      throw Exception('Speech recognition not available');
    }
    if (_isMuted) {
      debugPrint('[TTS] Cannot start listening - microphone is muted');
      throw Exception('Microphone is muted');
    }
    if (_isListening) {
      debugPrint('[TTS] Already listening');
      return;
    }

    try {
      debugPrint('[TTS] Starting speech recognition');
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            debugPrint('[TTS] Final result received: ${result.recognizedWords}');
            onResult(result.recognizedWords);
          }
        },
        listenMode: ListenMode.dictation,
        partialResults: false,
      );
    } catch (e) {
      debugPrint('[TTS] Error starting speech recognition: $e');
      _isListening = false;
      rethrow;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) {
      debugPrint('[TTS] Not listening - no need to stop');
      return;
    }
    debugPrint('[TTS] Stopping speech recognition');
    await _speech.stop();
    _isListening = false;
  }

  Future<void> speak(String text, {bool isLastChunk = false}) async {
    if (text.startsWith('🤔')) {
      debugPrint('[TTS] Skipping reasoning content: $text');
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

      // Set the last chunk flag before starting to speak
      _isProcessingLastChunk = isLastChunk;
      debugPrint(isLastChunk ? '[TTS] Processing last chunk' : '[TTS] Processing intermediate chunk');

      _isSpeaking = true;
      await _tts.speak(cleanText);
      // Wait for the speech to complete
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('[TTS] Error in TTS: $e');
      _isSpeaking = false;
      _isProcessingLastChunk = false;
    }
  }

  Future<void> stopSpeaking() async {
    _isProcessingLastChunk = false;  // Reset the flag when stopping
    await _tts.stop();
    // Clear any pending speech in the queue
    await _tts.pause();  // Pause first to ensure we can clear properly
    await _tts.stop();   // Stop again to clear any queued items
    _isSpeaking = false;
    _onTtsComplete = null;  // Clear the callback to prevent any pending callbacks
  }

  void setTtsCompleteCallback(Function callback) {
    _onTtsComplete = callback;
  }

  void onTtsQueueComplete() {
    debugPrint('[TTS] All queued text has been spoken');
    if (!_isMuted) {
      _onTtsComplete?.call();
    }
  }

  void setStateChangeCallback(Function callback) {
    _onStateChange = callback;
  }
}