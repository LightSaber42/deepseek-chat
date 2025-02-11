import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../utils/log_utils.dart';
import 'dart:math' show min;
import 'base_tts_service.dart';

class VoiceService extends BaseTTSService {
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
  final StringBuffer _currentTtsBuffer = StringBuffer();
  static const int _optimalChunkSize = 500;
  static const Duration _minChunkDuration = Duration(milliseconds: 500);
  DateTime _lastChunkTime = DateTime.now();
  bool _hasMoreContent = false;  // Flag to track if more content is expected

  // Add tracking for spoken text
  final Set<String> _spokenSentences = {};

  // Add at class level
  String? _lastSpokenText;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isMuted => _isMuted;

  void setTtsCompleteCallback(Function? callback) {
    _onTtsComplete = callback;
  }

  void setStateChangeCallback(Function? callback) {
    _onStateChange = callback;
  }

  /// Stops all speech and clears the TTS queue
  Future<void> stopSpeaking() async {
    debugPrint('[TTS] Stopping all speech');
    _currentTtsBuffer.clear();
    _ttsQueue.clear();
    _hasMoreContent = false;
    await stop();
  }

  /// Finishes speaking any remaining buffered text
  Future<void> finishSpeaking() async {
    try {
      debugPrint('[TTS] Finishing speaking. Buffer: """${_currentTtsBuffer.toString()}"""');
      debugPrint('[TTS] Speaking: $_isSpeaking, HasMore: $_hasMoreContent');

      // Only proceed if we have content to speak or are still speaking
      if (_currentTtsBuffer.isEmpty && !_isSpeaking && !_hasMoreContent) {
        debugPrint('[TTS] Nothing to finish speaking');
        _onTtsComplete?.call();
        return;
      }

      // Handle any remaining text
      String remainingText = _currentTtsBuffer.toString().trim();
      _currentTtsBuffer.clear();
      _hasMoreContent = false;  // No more content expected

      if (remainingText.isNotEmpty) {
        debugPrint('[TTS] Speaking final text: """$remainingText"""');
        await speak(remainingText);
      }

      // Wait for any ongoing speech to complete
      if (_isSpeaking) {
        debugPrint('[TTS] Waiting for ongoing speech to complete');
        await _tts.awaitSpeakCompletion(true);
      }

      debugPrint('[TTS] All speaking completed, triggering callback');
      _onTtsComplete?.call();
    } catch (e) {
      debugPrint('[TTS] Error in finish speaking: $e');
      throwServiceError(e);
    }
  }

  @override
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

    // Initialize TTS with default options
    _tts.setCompletionHandler(() {
      debugPrint('[TTS] Completed speaking chunk');
      _isSpeaking = false;
      // Only call completion callback if no more content is expected
      if (!_hasMoreContent) {
        debugPrint('[TTS] No more content expected, triggering completion callback');
        _onTtsComplete?.call();
      }
    });

    _tts.setErrorHandler((msg) {
      debugPrint('[TTS] TTS error: $msg');
      _isSpeaking = false;
      throwServiceError(msg);
    });

    await updateOptions(const TTSServiceOptions(
      rate: 0.54,
      pitch: 0.9,
      volume: 1.0,
      language: 'en-US',
    ));

    debugPrint('[TTS] Voice services initialized successfully');
    return available;
  }

  @override
  Future<void> speak(String text) async {
    if (_isMuted) {
      debugPrint('[TTS] Cannot speak - TTS is muted');
      return;
    }

    try {
      // Wait for any ongoing speech to complete
      if (_isSpeaking) {
        debugPrint('[TTS] Already speaking, waiting for completion');
        await _tts.awaitSpeakCompletion(true);
      }

      final cleanedText = cleanTextForTTS(text);
      debugPrint('[TTS] Speaking text: """$cleanedText"""');
      _isSpeaking = true;
      await _tts.speak(cleanedText);
      await _tts.awaitSpeakCompletion(true);
      _isSpeaking = false;
      debugPrint('[TTS] Finished speaking text');
    } catch (e) {
      debugPrint('[TTS] Error in speak: $e');
      _isSpeaking = false;
      throwServiceError(e);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
      _isSpeaking = false;
      _hasMoreContent = false;
    } catch (e) {
      throwServiceError(e);
    }
  }

  @override
  Future<void> updateOptions(TTSServiceOptions options) async {
    try {
      await _tts.setLanguage(options.language);
      await _tts.setSpeechRate(options.rate);
      await _tts.setVolume(options.volume);
      await _tts.setPitch(options.pitch);
      if (options.voice.isNotEmpty) {
        await _tts.setVoice({"name": options.voice});
      }
    } catch (e) {
      throwServiceError(e);
    }
  }

  Future<void> startListening(void Function(String) onResult) async {
    // Don't allow listening while speaking
    if (isSpeaking || _isProcessingTts) {
      debugPrint('[TTS] Cannot start listening - TTS is active');
      return;
    }

    try {
      // Ensure speech is initialized
      if (!_speech.isAvailable) {
        debugPrint('[TTS] Speech not available, attempting to initialize');
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
          throwServiceError('Could not initialize speech recognition', code: 'speech_unavailable');
        }
      }

      if (isMuted) {
        throwServiceError('Microphone is muted', code: 'mic_muted');
      }
      if (_isListening) {
        debugPrint('[TTS] Already listening');
        return;
      }

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
      throwServiceError(e);
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
      debugPrint('[TTS] Skipping reasoning content');
      return;
    }

    try {
      if (text.isEmpty) return;

      debugPrint('[TTS] Buffering new text chunk: """$text"""');
      debugPrint('[TTS] Current buffer before adding: """${_currentTtsBuffer.toString()}"""');

      _hasMoreContent = true;  // Indicate that we're receiving content

      // Add space if needed
      if (_currentTtsBuffer.isNotEmpty && !_currentTtsBuffer.toString().endsWith(' ') &&
          !text.startsWith(' ') && !text.startsWith('.') &&
          !text.startsWith('!') && !text.startsWith('?') &&
          !text.startsWith(',')) {
        _currentTtsBuffer.write(' ');
      }

      // Add new text to buffer
      _currentTtsBuffer.write(text);
      String currentText = _currentTtsBuffer.toString();
      debugPrint('[TTS] Buffer after adding: """$currentText"""');

      // Look for sentence endings not preceded by numbers (to avoid splitting "13.8")
      RegExp sentenceEnd = RegExp(r'(?<!\d)[.!?](?=\s|$)');
      var matches = sentenceEnd.allMatches(currentText).toList();
      debugPrint('[TTS] Found ${matches.length} sentence endings');

      // Only process if we have at least one complete sentence
      if (matches.isNotEmpty) {
        // Find the last complete sentence
        int lastMatchEnd = matches.last.end;
        String toSpeak = currentText.substring(0, lastMatchEnd).trim();
        String remaining = currentText.substring(lastMatchEnd).trim();

        debugPrint('[TTS] Complete sentence to speak: """$toSpeak"""');
        debugPrint('[TTS] Remaining text: """$remaining"""');

        if (toSpeak.isNotEmpty) {
          // Clear buffer and store remaining text
          _currentTtsBuffer.clear();
          if (remaining.isNotEmpty) {
            _currentTtsBuffer.write(remaining);
          }

          // Speak the complete sentences
          await speak(toSpeak);
          debugPrint('[TTS] After speaking, buffer contains: """${_currentTtsBuffer.toString()}"""');
        }
      }
    } catch (e) {
      debugPrint('[TTS] Error in bufferText: $e');
      throwServiceError(e);
    }
  }

  @override
  void dispose() {
    debugPrint('[TTS] Disposing voice service');
    _tts.stop();
    _currentTtsBuffer.clear();
    _ttsQueue.clear();
    _hasMoreContent = false;
    _isSpeaking = false;
    super.dispose();
  }
}