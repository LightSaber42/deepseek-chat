import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class DeepSeekService {
  static const String _baseUrl = 'https://api.deepseek.com';
  String _apiKey;
  String _model = 'deepseek-chat';  // Default model

  String get apiKey => _apiKey;
  String get currentModel => _model;

  DeepSeekService(this._apiKey) {
    debugPrint('DeepSeekService initialized with API key length: ${_apiKey.length}');
  }

  Future<void> setModel(String model) async {
    if (model != 'deepseek-chat' && model != 'deepseek-reasoner') {
      throw Exception('Invalid model name. Must be deepseek-chat or deepseek-reasoner');
    }
    _model = model;
    debugPrint('Model set to: $_model');
  }

  Future<void> updateApiKey(String newApiKey) async {
    _apiKey = newApiKey;
    // Test the new key
    final isValid = await testConnection();
    if (!isValid) {
      throw Exception('Invalid API key');
    }
  }

  Future<String?> getAccountBalance() async {
    try {
      final uri = Uri.parse('${_baseUrl}/v1/dashboard/billing/credit_grants');
      debugPrint('Fetching balance from: $uri');

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
        debugPrint('Error fetching balance: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching balance: $e');
      return null;
    }
  }

  String _parseContent(String line) {
    try {
      if (line.trim() == 'data: [DONE]') {
        return '';
      }

      final jsonData = json.decode(line.substring(5));
      String content = '';
      if (jsonData['choices']?[0]?['delta']?['content'] != null) {
        content = jsonData['choices'][0]['delta']['content'];
      } else if (jsonData['choices']?[0]?['delta']?['reasoning_content'] != null) {
        content = '[Reasoning] ' + jsonData['choices'][0]['delta']['reasoning_content'];
      }

      return content;
    } catch (e) {
      debugPrint('[Error] Failed to parse content: $e');
      return '';
    }
  }

  Stream<String> _processStream(Stream<List<int>> stream, http.Client client) {
    return stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().startsWith('data:'))
        .map((line) => _parseContent(line))
        .where((content) => content.isNotEmpty)
        .handleError((error) {
          debugPrint('[Error] Stream processing failed: $error');
          client.close();
          throw error;
        });
  }

  Future<Stream<String>> sendMessage(List<Map<String, dynamic>> history) async {
    final uri = Uri.parse('${_baseUrl}/v1/chat/completions');

    try {
      final client = http.Client();
      final request = http.Request('POST', uri);
      request.headers.addAll({
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      });

      final body = {
        'model': _model,
        'messages': history,
        'stream': true,
        'max_tokens': 4096,
        'temperature': 0.7,
      };
      request.body = json.encode(body);

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        debugPrint('[Error] API request failed (${response.statusCode}): $errorBody');
        throw Exception('API request failed');
      }

      return _processStream(response.stream, client);
    } catch (e) {
      debugPrint('[Error] Failed to send message: $e');
      rethrow;
    }
  }

  Future<bool> testConnection() async {
    try {
      final uri = Uri.parse('${_baseUrl}/v1/chat/completions');
      debugPrint('Testing connection to: $uri');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': 'deepseek-chat',
          'messages': [{'role': 'user', 'content': 'Hello'}],
          'max_tokens': 50,
          'stream': false,
        }),
      );

      debugPrint('Test connection status code: ${response.statusCode}');
      debugPrint('Test connection response: ${response.body}');

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error testing connection: $e');
      return false;
    }
  }
}
