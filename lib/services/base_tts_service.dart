import 'dart:async';
import 'package:flutter/foundation.dart';

/// Base exception class for TTS service errors
class TTSServiceException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  TTSServiceException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'TTSServiceException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Configuration options for TTS services
class TTSServiceOptions {
  final double rate;
  final double pitch;
  final double volume;
  final String voice;
  final String language;
  final Map<String, dynamic>? additionalOptions;

  const TTSServiceOptions({
    this.rate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.voice = '',
    this.language = 'en-US',
    this.additionalOptions,
  });

  Map<String, dynamic> toJson() => {
    'rate': rate,
    'pitch': pitch,
    'volume': volume,
    'voice': voice,
    'language': language,
    if (additionalOptions != null) ...additionalOptions!,
  };
}

/// Abstract base class for TTS service implementations
abstract class BaseTTSService {
  bool _isSpeaking = false;
  bool _isMuted = false;
  final StreamController<String> _ttsController = StreamController<String>.broadcast();
  final List<String> _ttsQueue = [];

  bool get isSpeaking => _isSpeaking;
  bool get isMuted => _isMuted;
  bool get isListening;  // Each implementation must provide this
  Stream<String> get ttsStream => _ttsController.stream;

  /// Initializes the TTS service
  Future<bool> init();

  /// Speaks the given text
  Future<void> speak(String text);

  /// Stops current speech
  Future<void> stop();

  /// Updates TTS options
  Future<void> updateOptions(TTSServiceOptions options);

  /// Buffers text for speaking
  Future<void> bufferText(String text);

  /// Finishes speaking any remaining buffered text
  Future<void> finishSpeaking();

  /// Stops all speech and clears the queue
  Future<void> stopSpeaking();

  /// Starts listening for voice input
  Future<void> startListening(void Function(String) onResult);

  /// Stops listening for voice input
  Future<void> stopListening();

  /// Toggles mute state
  void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted && _isSpeaking) {
      stop();
    }
  }

  /// Cleans text for TTS processing
  @protected
  String cleanTextForTTS(String text) {
    debugPrint('[TTS] Text before TTS cleaning: """$text"""');

    // Basic space normalization
    text = text.replaceAll(RegExp(r'\s{3,}'), ' ').trim();

    // Fix decimal numbers
    text = text.replaceAllMapped(
      RegExp(r'(\d+)\s*\.\s*(\d+)'),
      (match) => '${match.group(1)!}.${match.group(2)!}'
    );

    // Fix contractions and possessives
    text = text
      .replaceAll(" 's", "'s")
      .replaceAll(" 't", "'t")
      .replaceAll(" 'll", "'ll")
      .replaceAll(" 've", "'ve")
      .replaceAll(" 're", "'re")
      .replaceAll(" 'd", "'d")
      .replaceAll(" 'm", "'m");

    // Fix spaces around punctuation
    text = text
      .replaceAll('  ,', ',')
      .replaceAll('  .', '.')
      .replaceAll('  !', '!')
      .replaceAll('  ?', '?')
      .replaceAll('  :', ':')
      .replaceAll('  ;', ';');

    // Add spaces after punctuation if missing
    text = text.replaceAllMapped(
      RegExp(r'([,.!?:;])(?=\S)(?!\d)'),
      (match) => '${match.group(1)!} '
    );

    debugPrint('[TTS] Text after TTS cleaning: """$text"""');
    return text;
  }

  /// Handles common error scenarios
  @protected
  Never throwServiceError(dynamic error, {String? code}) {
    final message = error is Exception ? error.toString() : 'Unknown error occurred';
    throw TTSServiceException(message, code: code, originalError: error);
  }

  /// Disposes of resources
  void dispose() {
    _ttsController.close();
    _ttsQueue.clear();
  }
}