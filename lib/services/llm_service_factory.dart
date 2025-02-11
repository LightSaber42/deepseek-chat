import 'package:flutter/foundation.dart';
import 'base_llm_service.dart';
import 'deepseek_service.dart';
import 'openrouter_service.dart';

/// Enum representing available LLM providers
enum LLMProvider {
  deepseek,
  openRouter,
}

/// Factory for creating LLM service instances
class LLMServiceFactory {
  static const String _defaultDeepSeekBaseUrl = 'https://api.deepseek.com/v1';
  static const String _defaultDeepSeekModel = 'deepseek-chat';

  /// Creates an LLM service instance based on the specified provider
  static BaseLLMService createService({
    required LLMProvider provider,
    required String apiKey,
    String? baseUrl,
    String? model,
  }) {
    switch (provider) {
      case LLMProvider.deepseek:
        return DeepSeekService(
          apiKey: apiKey,
          baseUrl: baseUrl ?? _defaultDeepSeekBaseUrl,
          model: model ?? _defaultDeepSeekModel,
        );

      case LLMProvider.openRouter:
        final service = OpenRouterService();
        service.updateApiKey(apiKey);
        if (model != null) {
          service.setModel(model);
        }
        return service;
    }
  }

  /// Returns a list of available models for the specified provider
  static List<String> getAvailableModels(LLMProvider provider) {
    switch (provider) {
      case LLMProvider.deepseek:
        return ['deepseek-chat', 'deepseek-reasoner'];

      case LLMProvider.openRouter:
        return [
          'deepseek/deepseek-r1',
          'anthropic/claude-2',
          'google/palm-2-chat-bison',
          'meta-llama/llama-2-70b-chat',
          'mistral/mistral-7b-instruct',
        ];
    }
  }

  /// Returns the default model for the specified provider
  static String getDefaultModel(LLMProvider provider) {
    switch (provider) {
      case LLMProvider.deepseek:
        return _defaultDeepSeekModel;

      case LLMProvider.openRouter:
        return 'deepseek/deepseek-r1';
    }
  }

  /// Returns the base URL for the specified provider
  static String? getBaseUrl(LLMProvider provider) {
    switch (provider) {
      case LLMProvider.deepseek:
        return _defaultDeepSeekBaseUrl;

      case LLMProvider.openRouter:
        return null; // OpenRouter uses a fixed base URL internally
    }
  }

  /// Validates the API key format for the specified provider
  static bool isValidApiKeyFormat(LLMProvider provider, String apiKey) {
    switch (provider) {
      case LLMProvider.deepseek:
        // DeepSeek API keys typically start with 'dsk-' and are 32+ chars
        return apiKey.startsWith('dsk-') && apiKey.length >= 32;

      case LLMProvider.openRouter:
        // OpenRouter API keys are typically 32+ characters
        return apiKey.length >= 32;
    }
  }

  /// Creates default service options for the specified provider
  static LLMServiceOptions createDefaultOptions(LLMProvider provider) {
    switch (provider) {
      case LLMProvider.deepseek:
        return const LLMServiceOptions(
          maxTokens: 2000,
          temperature: 0.7,
        );

      case LLMProvider.openRouter:
        return const LLMServiceOptions(
          maxTokens: 2000,
          temperature: 0.7,
          additionalOptions: {
            'top_p': 0.95,
            'frequency_penalty': 0,
            'presence_penalty': 0,
          },
        );
    }
  }
}