import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DeepSeekService {
  String _apiKey;
  final String _baseUrl;
  String _model;
  final StreamController<String> _streamController = StreamController<String>.broadcast();

  String get apiKey => _apiKey;
  String get currentModel => _model;

  DeepSeekService({
    required String apiKey,
    required String baseUrl,
    String model = 'deepseek-chat',
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl,
        _model = model {
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
    final isValid = await testConnection();
    if (!isValid) {
      throw Exception('Invalid API key');
    }
  }

  Future<String?> getAccountBalance() async {
    try {
      final uri = Uri.parse('${_baseUrl}/dashboard/billing/credit_grants');
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

  Stream<String> get stream => _streamController.stream;

  Future<Stream<String>> sendMessage(List<Map<String, dynamic>> history) async {
    try {
      debugPrint('[API] Sending request to DeepSeek');

      final uri = Uri.parse('${_baseUrl}/chat/completions');
      final body = {
        'model': _model,
        'messages': history,
        'stream': true,
      };

      debugPrint('[API] Request body: ${json.encode(body)}');

      final request = http.Request('POST', uri);
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode(body);

      final response = await http.Client().send(request);
      debugPrint('[API] Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('API request failed: $body');
      }

      // Create a new StreamController for this request
      final localController = StreamController<String>();

      // Convert the response stream to a string stream
      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      // Process the stream
      stream.listen(
        (String line) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              debugPrint('[API] Received [DONE] signal');
              localController.close();
              return;
            }

            try {
              final jsonData = json.decode(data);
              String? content;

              if (jsonData['choices']?[0]?['delta']?['reasoning_content'] != null) {
                content = '[Reasoning] ${jsonData['choices'][0]['delta']['reasoning_content']}';
                debugPrint('[API] Reasoning content: $content');
              } else if (jsonData['choices']?[0]?['delta']?['content'] != null) {
                content = jsonData['choices'][0]['delta']['content'];
                debugPrint('[API] Response content: $content');
              }

              if (content != null && content.isNotEmpty) {
                localController.add(content);
              }
            } catch (e) {
              debugPrint('[Error] Failed to parse chunk: $e');
            }
          }
        },
        onError: (error) {
          debugPrint('[Error] Stream error: $error');
          localController.addError(error);
          localController.close();
        },
        onDone: () {
          debugPrint('[API] Stream processing completed');
          if (!localController.isClosed) {
            localController.close();
          }
        },
        cancelOnError: true,
      );

      return localController.stream;
    } catch (e) {
      debugPrint('[Error] Full error details: ${e.toString()}');
      rethrow;
    }
  }

  Future<bool> testConnection() async {
    try {
      final uri = Uri.parse('${_baseUrl}/chat/completions');
      final body = {
        'model': _model,
        'messages': [{'role': 'user', 'content': 'Hello'}],
      };

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      debugPrint('[API] Test connection status: ${response.statusCode}');
      debugPrint('[API] Test connection response: ${response.body}');

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error testing connection: $e');
      return false;
    }
  }

  void dispose() {
    _streamController.close();
  }
}
