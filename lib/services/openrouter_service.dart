import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../utils/log_utils.dart';
import 'dart:math' show min;

class OpenRouterService {
  static const String _baseUrl = 'https://openrouter.ai/api/v1';
  String _apiKey = '';
  String _selectedModel = 'deepseek/deepseek-r1';

  String get apiKey => _apiKey;

  Future<void> updateApiKey(String apiKey) async {
    _apiKey = apiKey;
  }

  void setModel(String model) {
    _selectedModel = model;
  }

  Future<Stream<String>> sendMessage(List<Map<String, dynamic>> messages) async {
    try {
      final url = Uri.parse('$_baseUrl/chat/completions');
      final headers = {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/yourusername/deepseek-frontend',
      };

      debugPrint('[OpenRouter] Sending request with messages: ${messages.length} messages');
      debugPrint('[OpenRouter] First message role: ${messages.first['role']}');
      debugPrint('[OpenRouter] System prompt: ${messages.first['content'].substring(0, min<int>(50, messages.first['content'].length))}...');
      debugPrint('[OpenRouter] Using model: $_selectedModel');

      final body = jsonEncode({
        'model': _selectedModel,
        'messages': messages,
        'stream': true,
      });

      final request = http.Request('POST', url);
      request.headers.addAll(headers);
      request.body = body;

      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('OpenRouter API error: ${response.statusCode} $errorBody');
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
              controller.addError(error);
              controller.close();
            },
          );

      return controller.stream;
    } catch (e) {
      debugPrint('[OpenRouter] Error in service: $e');
      rethrow;
    }
  }

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
          if (jsonResponse['choices'] != null &&
              jsonResponse['choices'].isNotEmpty &&
              jsonResponse['choices'][0]['message'] != null) {
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