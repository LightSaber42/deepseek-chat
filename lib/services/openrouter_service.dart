import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../utils/log_utils.dart';
import 'dart:math' show min;
import 'base_llm_service.dart';

class OpenRouterService extends BaseLLMService {
  static const String _baseUrl = 'https://openrouter.ai/api/v1';
  String _apiKey = '';
  String _selectedModel = 'deepseek/deepseek-r1';

  @override
  String get apiKey => _apiKey;

  @override
  String get currentModel => _selectedModel;

  @override
  Future<void> updateApiKey(String apiKey) async {
    _apiKey = apiKey;
    final isValid = await testConnection();
    if (!isValid) {
      throwServiceError('Invalid API key', code: 'invalid_api_key');
    }
  }

  @override
  Future<void> setModel(String model) async {
    _selectedModel = model;
    debugPrint('OpenRouter model set to: $_selectedModel');
  }

  @override
  Future<Stream<String>> sendMessage(
    List<Map<String, dynamic>> messages, {
    LLMServiceOptions? options,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/chat/completions');
      final headers = {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/yourusername/deepseek-frontend',
      };

      final formattedMessages = formatHistory(messages);
      debugPrint('[OpenRouter] Sending request with messages: ${formattedMessages.length} messages');
      debugPrint('[OpenRouter] First message role: ${formattedMessages.first['role']}');
      debugPrint('[OpenRouter] System prompt: ${formattedMessages.first['content'].substring(0, min<int>(50, formattedMessages.first['content'].length))}...');
      debugPrint('[OpenRouter] Using model: $_selectedModel');

      final requestBody = {
        'model': _selectedModel,
        'messages': formattedMessages,
        'stream': true,
        'max_tokens': options?.maxTokens ?? 2000,
        'temperature': options?.temperature ?? 1.0,
        if (options?.additionalOptions != null) ...options!.additionalOptions!,
      };

      final request = http.Request('POST', url);
      request.headers.addAll(headers);
      request.body = jsonEncode(requestBody);

      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throwServiceError('OpenRouter API error: ${response.statusCode} $errorBody',
            code: 'api_error_${response.statusCode}');
      }

      // Create a StreamController to handle the response stream
      final controller = StreamController<String>();

      // Process the stream in the background
      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.startsWith('data: ')) {
                final jsonStr = line.substring(6);
                if (jsonStr == '[DONE]') return;

                try {
                  final Map<String, dynamic> data = jsonDecode(jsonStr);
                  if (!validateResponseFormat(data)) {
                    debugPrint('[OpenRouter] Invalid response format');
                    return;
                  }

                  final content = data['choices'][0]['delta']['content'];
                  if (content != null && content.isNotEmpty) {
                    controller.add(content);
                  }
                } catch (e) {
                  debugPrint('[OpenRouter] Error parsing response: $e');
                }
              }
            },
            onDone: () => controller.close(),
            onError: (error) {
              debugPrint('[OpenRouter] Error in stream: $error');
              controller.addError(LLMServiceException('Stream error', originalError: error));
              controller.close();
            },
          );

      return controller.stream;
    } catch (e) {
      debugPrint('[OpenRouter] Error in service: $e');
      throwServiceError(e);
    }
  }

  @override
  Future<String?> getAccountBalance() async {
    try {
      final url = Uri.parse('$_baseUrl/auth/balance');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['balance']?.toString() ?? 'N/A';
      }
      return null;
    } catch (e) {
      LogUtils.log('Error fetching OpenRouter balance: $e');
      return null;
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      final url = Uri.parse('$_baseUrl/chat/completions');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://github.com/yourusername/deepseek-frontend',
        },
        body: jsonEncode({
          'model': _selectedModel,
          'messages': [
            {
              'role': 'user',
              'content': 'Hello'
            }
          ],
          'stream': false,
        }),
      );

      LogUtils.log('[TEST] OpenRouter response status code: ${response.statusCode}');
      if (response.statusCode == 200) {
        try {
          final jsonResponse = jsonDecode(response.body);
          if (validateResponseFormat(jsonResponse)) {
            LogUtils.log('[TEST] OpenRouter connection successful');
            return true;
          }
        } catch (e) {
          LogUtils.log('[ERROR] Failed to parse OpenRouter response: $e');
        }
      }

      LogUtils.log('[ERROR] OpenRouter API returned non-200 status code: ${response.statusCode}');
      LogUtils.log('[ERROR] Response body: ${response.body}');
      return false;
    } catch (e) {
      LogUtils.log('[ERROR] OpenRouter test connection error: $e');
      return false;
    }
  }
}