import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../utils/log_utils.dart';
import 'dart:math' show min;

class VoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isMuted = false;
  Function? _onTtsComplete;
  Function? _onStateChange;

  // Queue management
  final List<String> _ttsQueue = [];
  bool _isProcessingTts = false;
  final StringBuffer _currentBuffer = StringBuffer();
  static const int _optimalChunkSize = 500;
  static const Duration _minChunkDuration = Duration(milliseconds: 500);
  DateTime _lastChunkTime = DateTime.now();

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isMuted => _isMuted;

  // Clean text only for TTS purposes, not for display
  String _cleanTextForTts(String text) {
    LogUtils.log('[TTS] Text before TTS cleaning: """$text"""');

    // First normalize all spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Fix decimal numbers (13. 8 -> 13.8)
    var matches = RegExp(r'(\d+)\s*\.\s*(\d+)').allMatches(text).toList();
    for (var match in matches.reversed) {
      var start = match.start;
      var end = match.end;
      var num1 = match.group(1);
      var num2 = match.group(2);
      text = text.replaceRange(start, end, '$num1.$num2');
    }

    // Fix contractions and possessives
    text = text
      .replaceAll(" 's", "'s")
      .replaceAll(" 't", "'t")
      .replaceAll(" 'll", "'ll")
      .replaceAll(" 've", "'ve")
      .replaceAll(" 're", "'re")
      .replaceAll(" 'd", "'d")
      .replaceAll(" 'm", "'m");

    // Fix hyphenated words
    text = text
      .replaceAll(' - ', '-')
      .replaceAll(' -', '-')
      .replaceAll('- ', '-');

    // Fix spaces around punctuation
    text = text
      .replaceAll(' ,', ',')
      .replaceAll(' .', '.')
      .replaceAll(' !', '!')
      .replaceAll(' ?', '?')
      .replaceAll(' :', ':')
      .replaceAll(' ;', ';')
      .replaceAll(' )', ')')
      .replaceAll('( ', '(');

    // Add spaces after punctuation, but not in decimal numbers
    text = text.replaceAllMapped(
      RegExp(r'([,.!?:;])(?!\s)(?!\d)'),
      (match) => '${match.group(1)} '
    );

    // Final cleanup of any double spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    LogUtils.log('[TTS] Text after TTS cleaning: """$text"""');
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
    await _tts.setPitch(0.9);

    _tts.setStartHandler(() {
      debugPrint('[TTS] Started speaking');
      _isSpeaking = true;
    });

    _tts.setCompletionHandler(() {
      debugPrint('[TTS] Completed speaking chunk');
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
    // Don't allow listening while speaking
    if (_isSpeaking || _isProcessingTts) {
      debugPrint('[TTS] Cannot start listening - TTS is active');
      return;
    }

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
      _isListening = true;
      _onStateChange?.call();
    } catch (e) {
      debugPrint('[TTS] Error starting speech recognition: $e');
      _isListening = false;
      _onStateChange?.call();
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

  Future<void> bufferText(String text) async {
    if (text.startsWith('🤔')) {
      LogUtils.log('[TTS] Skipping reasoning content');
      return;
    }

    try {
      if (text.isEmpty) return;

      // Add space if needed
      if (_currentBuffer.isNotEmpty && !_currentBuffer.toString().endsWith(' ') &&
          !text.startsWith(' ') && !text.startsWith('.') &&
          !text.startsWith('!') && !text.startsWith('?') &&
          !text.startsWith(',')) {
        _currentBuffer.write(' ');
      }
      _currentBuffer.write(text);

      LogUtils.log('[TTS] Added to buffer (${text.length} chars): """$text"""');
      LogUtils.log('[TTS] Current buffer size: ${_currentBuffer.length} chars');

      // Only process if we have a sentence ending
      String currentText = _currentBuffer.toString();
      if (currentText.contains(RegExp(r'[.!?](\s|$)'))) {
        // Split into sentences, keeping delimiters
        List<String> parts = currentText.split(RegExp(r'(?<=[.!?])(?=\s|$)'));

        if (parts.length > 1) {
          // Take all complete sentences and add to queue
          String toSpeak = parts.sublist(0, parts.length - 1).join('').trim();
          if (toSpeak.isNotEmpty) {
            _ttsQueue.add(toSpeak);
            // Start processing if not already doing so
            if (!_isProcessingTts) {
              _processNextInQueue();
            }
          }

          // Keep the incomplete sentence in the buffer
          _currentBuffer.clear();
          _currentBuffer.write(parts.last.trim());
        }
      }
    } catch (e) {
      LogUtils.log('[TTS] Error buffering text: $e');
    }
  }

  Future<void> finishSpeaking() async {
    if (_currentBuffer.isEmpty) return;

    try {
      String remainingText = _currentBuffer.toString().trim();
      _currentBuffer.clear();
      if (remainingText.isNotEmpty) {
        _ttsQueue.add(remainingText);
        if (!_isProcessingTts) {
          _processNextInQueue();
        }
      }
    } catch (e) {
      debugPrint('[TTS] Error in finish speaking: $e');
      await _resetTtsState();
    }
  }

  Future<void> _processNextInQueue() async {
    if (_ttsQueue.isEmpty || _isProcessingTts || _isSpeaking) return;

    try {
      _isProcessingTts = true;

      while (_ttsQueue.isNotEmpty) {
        String text = _ttsQueue.first;

        // Clean the text only for TTS, not display
        final cleanedText = _cleanTextForTts(text);
        LogUtils.log('[TTS] Speaking chunk (${cleanedText.length} chars):');
        LogUtils.log('[TTS] Raw text for TTS: """$text"""');
        LogUtils.log('[TTS] Cleaned text for TTS: """$cleanedText"""');

        _isSpeaking = true;
        await _tts.speak(cleanedText);
        await _tts.awaitSpeakCompletion(true);
        _isSpeaking = false;

        // Remove the processed text from queue
        _ttsQueue.removeAt(0);
        _lastChunkTime = DateTime.now();
      }

      // All chunks processed
      if (_ttsQueue.isEmpty) {
        LogUtils.log('[TTS] Completed final chunk, triggering completion');
        await _resetTtsState();
        onTtsQueueComplete();
      }
    } catch (e) {
      LogUtils.log('[TTS] Error processing TTS chunk: $e');
      await _resetTtsState();
    } finally {
      _isProcessingTts = false;
      _isSpeaking = false;
    }
  }

  Future<void> _resetTtsState() async {
    _isProcessingTts = false;
    _isSpeaking = false;
    _currentBuffer.clear();
    _ttsQueue.clear();
    await _tts.stop();
  }

  Future<void> stopSpeaking() async {
    debugPrint('[TTS] Stopping all speech');
    await _resetTtsState();
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