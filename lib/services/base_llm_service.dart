import 'dart:async';
import 'package:flutter/foundation.dart';

/// Base exception class for LLM service errors
class LLMServiceException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  LLMServiceException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'LLMServiceException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Configuration options for LLM services
class LLMServiceOptions {
  final int maxTokens;
  final double temperature;
  final String model;
  final Map<String, dynamic>? additionalOptions;

  const LLMServiceOptions({
    this.maxTokens = 2000,
    this.temperature = 1.0,
    this.model = '',
    this.additionalOptions,
  });

  Map<String, dynamic> toJson() => {
    'max_tokens': maxTokens,
    'temperature': temperature,
    'model': model,
    if (additionalOptions != null) ...additionalOptions!,
  };
}

/// Abstract base class for LLM service implementations
abstract class BaseLLMService {
  String get apiKey;
  String get currentModel;

  /// Sends a message to the LLM and returns a stream of response chunks
  Future<Stream<String>> sendMessage(
    List<Map<String, dynamic>> history, {
    LLMServiceOptions? options,
  });

  /// Updates the API key for the service
  Future<void> updateApiKey(String newApiKey);

  /// Tests the connection to the service
  Future<bool> testConnection();

  /// Retrieves the account balance if available
  Future<String?> getAccountBalance();

  /// Updates the current model
  Future<void> setModel(String model);

  /// Validates the response format
  @protected
  bool validateResponseFormat(Map<String, dynamic> response) {
    try {
      return response.containsKey('choices') &&
             response['choices'] is List &&
             response['choices'].isNotEmpty;
    } catch (e) {
      debugPrint('[LLM] Error validating response format: $e');
      return false;
    }
  }

  /// Handles common error scenarios
  @protected
  Never throwServiceError(dynamic error, {String? code}) {
    final message = error is Exception ? error.toString() : 'Unknown error occurred';
    throw LLMServiceException(message, code: code, originalError: error);
  }

  /// Formats the chat history for API requests
  @protected
  List<Map<String, dynamic>> formatHistory(List<Map<String, dynamic>> history) {
    return history.map((message) {
      // Ensure required fields are present
      if (!message.containsKey('role') || !message.containsKey('content')) {
        throw LLMServiceException('Invalid message format: missing required fields');
      }
      return {
        'role': message['role'],
        'content': message['content'],
      };
    }).toList();
  }
}