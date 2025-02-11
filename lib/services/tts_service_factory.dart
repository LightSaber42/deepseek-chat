import 'package:flutter/foundation.dart';
import 'base_tts_service.dart';
import 'voice_service.dart';

/// Enum representing available TTS providers
enum TTSProvider {
  system,  // Default system TTS
  // Add more providers as needed (e.g., azure, google, amazon)
}

/// Factory for creating TTS service instances
class TTSServiceFactory {
  /// Creates a TTS service instance based on the specified provider
  static BaseTTSService createService({
    required TTSProvider provider,
    TTSServiceOptions? options,
  }) {
    switch (provider) {
      case TTSProvider.system:
        final service = VoiceService();
        if (options != null) {
          service.updateOptions(options);
        }
        return service;
    }
  }

  /// Returns a list of available voices for the specified provider
  static Future<List<String>> getAvailableVoices(TTSProvider provider) async {
    // This would typically query the provider for available voices
    // For now, we'll return an empty list as the system TTS handles this internally
    return [];
  }

  /// Returns the default options for the specified provider
  static TTSServiceOptions getDefaultOptions(TTSProvider provider) {
    switch (provider) {
      case TTSProvider.system:
        return const TTSServiceOptions(
          rate: 0.54,  // 54% of normal speed for better comprehension
          pitch: 0.9,
          volume: 1.0,
          language: 'en-US',
        );
    }
  }

  /// Returns supported languages for the specified provider
  static List<String> getSupportedLanguages(TTSProvider provider) {
    switch (provider) {
      case TTSProvider.system:
        return [
          'en-US',
          'en-GB',
          'es-ES',
          'fr-FR',
          'de-DE',
          'it-IT',
          'ja-JP',
          'ko-KR',
          'zh-CN',
          'zh-TW',
        ];
    }
  }

  /// Validates the voice name format for the specified provider
  static bool isValidVoiceName(TTSProvider provider, String voice) {
    switch (provider) {
      case TTSProvider.system:
        // System TTS handles voice validation internally
        return true;
    }
  }

  /// Creates service-specific options for the specified provider
  static Map<String, dynamic>? createProviderSpecificOptions(
    TTSProvider provider, {
    Map<String, dynamic>? customOptions,
  }) {
    switch (provider) {
      case TTSProvider.system:
        return {
          'enableSpeechMarks': true,
          'useSSML': false,
          if (customOptions != null) ...customOptions,
        };
    }
  }
}