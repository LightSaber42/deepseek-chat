import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';
import 'base_llm_service.dart';

class DeepSeekService extends BaseLLMService {
  final String _baseUrl;
  late OpenAI _client;
  String _apiKey;
  String _model;

  @override
  String get apiKey => _apiKey;

  @override
  String get currentModel => _model;

  DeepSeekService({
    required String apiKey,
    required String baseUrl,
    String model = 'deepseek-chat',
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl,
        _model = model {
    // Configure OpenAI client for DeepSeek
    OpenAI.baseUrl = baseUrl;  // Set base URL first
    OpenAI.apiKey = apiKey;    // Then set API key
    _client = OpenAI.instance;  // Get the configured instance
    debugPrint('OpenAI client initialized with base URL: $baseUrl');
  }

  @override
  Future<void> setModel(String model) async {
    if (model != 'deepseek-chat' && model != 'deepseek-reasoner') {
      throwServiceError('Invalid model name. Must be deepseek-chat or deepseek-reasoner',
          code: 'invalid_model');
    }
    _model = model;
    debugPrint('Model set to: $_model');
  }

  @override
  Future<void> updateApiKey(String newApiKey) async {
    _apiKey = newApiKey;
    OpenAI.apiKey = newApiKey;
    final isValid = await testConnection();
    if (!isValid) {
      throwServiceError('Invalid API key', code: 'invalid_api_key');
    }
  }

  @override
  Future<Stream<String>> sendMessage(
    List<Map<String, dynamic>> history, {
    LLMServiceOptions? options,
  }) async {
    try {
      debugPrint('[API] Sending request to DeepSeek with model: $_model');
      final formattedHistory = formatHistory(history);

      final requestBody = {
        'model': _model,
        'messages': formattedHistory,
        'max_tokens': options?.maxTokens ?? 2000,
        'temperature': options?.temperature ?? 1.0,
        'stream': true,
        if (options?.additionalOptions != null) ...options!.additionalOptions!,
      };

      debugPrint('[API] Request JSON:\n${const JsonEncoder.withIndent('  ').convert(requestBody)}');

      final uri = Uri.parse('${_baseUrl}/chat/completions');
      final request = http.Request('POST', uri);
      request.headers.addAll({
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      });

      request.body = json.encode(requestBody);

      final streamedResponse = await http.Client().send(request);
      if (streamedResponse.statusCode != 200) {
        throwServiceError('API returned ${streamedResponse.statusCode}',
            code: 'api_error_${streamedResponse.statusCode}');
      }

      // Create a StreamController to handle the response stream
      final controller = StreamController<String>();

      // Process the stream in the background
      streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.startsWith('data: ')) {
                final data = line.substring(6);
                if (data == '[DONE]') return;

                try {
                  final json = jsonDecode(data);
                  if (!validateResponseFormat(json)) {
                    debugPrint('[ERROR] Invalid response format');
                    return;
                  }

                  final delta = json['choices'][0]['delta'];

                  // Handle reasoning content
                  if (delta.containsKey('reasoning_content')) {
                    final reasoningContent = delta['reasoning_content'];
                    if (reasoningContent != null && reasoningContent.isNotEmpty) {
                      debugPrint('[API] Reasoning content: $reasoningContent');
                      controller.add('🤔REASONING_START🤔');
                      controller.add(reasoningContent);
                      controller.add('🤔REASONING_END🤔');
                    }
                  }

                  // Handle regular content
                  if (delta.containsKey('content')) {
                    final content = delta['content'];
                    if (content != null && content.isNotEmpty) {
                      debugPrint('[API] Content: $content');
                      controller.add(content);
                    }
                  }
                } catch (e) {
                  debugPrint('[ERROR] Failed to parse chunk: $e');
                }
              }
            },
            onDone: () => controller.close(),
            onError: (error) {
              debugPrint('[ERROR] Error in stream: $error');
              controller.addError(LLMServiceException('Stream error', originalError: error));
              controller.close();
            },
          );

      return controller.stream;
    } catch (e) {
      debugPrint('[ERROR] Error in sendMessage: $e');
      throwServiceError(e);
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      debugPrint('[TEST] Testing connection with model: $_model');

      final uri = Uri.parse('${_baseUrl}/chat/completions');
      debugPrint('[TEST] Sending test request to: $uri');

      final requestBody = {
        'model': _model,
        'messages': [
          {
            'role': 'user',
            'content': 'Hello'
          }
        ],
        'max_tokens': 50
      };

      debugPrint('[TEST] Request JSON:\n${const JsonEncoder.withIndent('  ').convert(requestBody)}');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      debugPrint('[TEST] Response status code: ${response.statusCode}');
      debugPrint('[TEST] Response JSON:\n${const JsonEncoder.withIndent('  ').convert(json.decode(response.body))}');

      if (response.statusCode == 200) {
        try {
          final jsonResponse = json.decode(response.body);
          if (validateResponseFormat(jsonResponse)) {
            debugPrint('[TEST] Connection successful');
            return true;
          }
        } catch (e) {
          debugPrint('[ERROR] Failed to parse response: $e');
        }
      }

      debugPrint('[ERROR] API returned non-200 status code: ${response.statusCode}');
      debugPrint('[ERROR] Response body: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('[ERROR] Test connection error: $e');
      return false;
    }
  }

  @override
  Future<String?> getAccountBalance() async {
    try {
      final uri = Uri.parse('${_baseUrl}/dashboard/billing/credit_grants');
      debugPrint('[API] Fetching balance from: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final total = data['total_granted'] ?? 0.0;
        final used = data['total_used'] ?? 0.0;
        final available = total - used;
        return '\$${available.toStringAsFixed(2)}';
      } else {
        debugPrint('[ERROR] Error fetching balance: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[ERROR] Error fetching balance: $e');
      return null;
    }
  }
}
