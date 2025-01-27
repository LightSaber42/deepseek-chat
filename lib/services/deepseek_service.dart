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
    final client = http.Client();
    try {
      debugPrint('[API] Sending request to DeepSeek with model: $_model');

      final uri = Uri.parse('${_baseUrl}/chat/completions');
      final body = {
        'model': _model,
        'messages': history,
        'stream': true,
        'temperature': 0.7,
        'max_tokens': 2000,
      };

      debugPrint('[API] Request body: ${json.encode(body)}');
      debugPrint('[API] Request URL: $uri');

      final request = http.Request('POST', uri);
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'text/event-stream';
      request.body = json.encode(body);

      debugPrint('[API] Request headers: ${request.headers}');

      debugPrint('[API] Sending streaming request...');
      final response = await client.send(request).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[ERROR] Request timed out after 30 seconds');
          throw TimeoutException('Request timed out');
        },
      );

      debugPrint('[API] Response status: ${response.statusCode}');
      debugPrint('[API] Response headers: ${response.headers}');

      if (response.statusCode == 404) {
        final errorBody = await response.stream.bytesToString();
        debugPrint('[ERROR] Model not found: $_model');
        debugPrint('[ERROR] Error response: $errorBody');
        throw Exception('Model not found: $_model');
      }

      if (response.statusCode == 401) {
        final errorBody = await response.stream.bytesToString();
        debugPrint('[ERROR] Unauthorized: Invalid API key');
        debugPrint('[ERROR] Error response: $errorBody');
        throw Exception('Unauthorized: Invalid API key');
      }

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        debugPrint('[ERROR] API request failed with status ${response.statusCode}');
        debugPrint('[ERROR] Error response body: $errorBody');
        throw Exception('API request failed: $errorBody');
      }

      // Create a new StreamController for this request
      final localController = StreamController<String>();

      // Convert the response stream to a string stream
      debugPrint('[API] Setting up stream processing...');
      final stream = response.stream
          .timeout(
            const Duration(seconds: 60),
            onTimeout: (sink) {
              debugPrint('[ERROR] Stream timed out after 60 seconds');
              sink.close();
            },
          )
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      var hasReceivedData = false;
      var lineCount = 0;
      var lastActivityTime = DateTime.now();
      var currentReasoningContent = StringBuffer();
      var isInReasoningBlock = false;

      // Process the stream
      stream.listen(
        (String line) {
          lastActivityTime = DateTime.now();
          lineCount++;
          debugPrint('[API] Processing line $lineCount: $line');

          if (line.isEmpty) {
            debugPrint('[API] Empty line received');
            return;
          }

          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            debugPrint('[API] Raw data: $data');

            if (data == '[DONE]') {
              debugPrint('[API] Received [DONE] signal');
              // Send any remaining reasoning content
              if (currentReasoningContent.isNotEmpty) {
                localController.add('🤔REASONING_START🤔\n${currentReasoningContent.toString()}\n��REASONING_END🤔');
                currentReasoningContent.clear();
              }
              if (!hasReceivedData) {
                debugPrint('[WARNING] Stream completed without sending any data');
              }
              localController.close();
              return;
            }

            try {
              final jsonData = json.decode(data);
              debugPrint('[API] Parsed JSON: ${json.encode(jsonData)}');

              // Check for reasoning_content first
              if (jsonData['choices']?[0]?['delta']?['reasoning_content'] != null) {
                final reasoningContent = jsonData['choices'][0]['delta']['reasoning_content'];
                if (reasoningContent != null && reasoningContent.isNotEmpty) {
                  debugPrint('[API] Reasoning content: $reasoningContent');
                  if (!isInReasoningBlock) {
                    isInReasoningBlock = true;
                    localController.add('🤔REASONING_START🤔');
                  }
                  localController.add(reasoningContent);
                  hasReceivedData = true;
                }
              }
              // Then check for regular content
              else if (jsonData['choices']?[0]?['delta']?['content'] != null) {
                final content = jsonData['choices'][0]['delta']['content'];
                if (content != null && content.isNotEmpty) {
                  debugPrint('[API] Response content: $content');
                  if (isInReasoningBlock) {
                    isInReasoningBlock = false;
                    localController.add('🤔REASONING_END🤔');
                    localController.add('💫SPLIT_MESSAGE💫');
                  }
                  localController.add(content);
                  hasReceivedData = true;
                }
              }
            } catch (e, stackTrace) {
              debugPrint('[ERROR] Failed to parse chunk: $e');
              debugPrint('[ERROR] Stack trace: $stackTrace');
            }
          } else {
            debugPrint('[API] Non-data line received: $line');
          }
        },
        onError: (error, stackTrace) {
          debugPrint('[ERROR] Stream error: $error');
          debugPrint('[ERROR] Stack trace: $stackTrace');
          localController.addError(error);
          client.close();
          localController.close();
        },
        onDone: () {
          final timeSinceLastActivity = DateTime.now().difference(lastActivityTime);
          debugPrint('[API] Stream processing completed');
          debugPrint('[API] Total lines processed: $lineCount');
          debugPrint('[API] Data received: $hasReceivedData');
          debugPrint('[API] Time since last activity: ${timeSinceLastActivity.inSeconds}s');
          client.close();
          if (!localController.isClosed) {
            localController.close();
          }
        },
        cancelOnError: true,
      );

      return localController.stream;
    } on TimeoutException catch (e) {
      debugPrint('[ERROR] Connection timed out: $e');
      client.close();
      rethrow;
    } on http.ClientException catch (e) {
      debugPrint('[ERROR] HTTP client error: $e');
      client.close();
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('[ERROR] Full error details: ${e.toString()}');
      debugPrint('[ERROR] Stack trace: $stackTrace');
      client.close();
      rethrow;
    }
  }

  Future<bool> testConnection() async {
    final client = http.Client();
    try {
      debugPrint('[TEST] Testing connection with model: $_model');
      final uri = Uri.parse('${_baseUrl}/chat/completions');
      final body = {
        'model': _model,
        'messages': [{'role': 'user', 'content': 'Hello'}],
        'temperature': 0.7,
        'max_tokens': 50,
      };

      debugPrint('[TEST] Request URL: $uri');
      debugPrint('[TEST] Request body: ${json.encode(body)}');

      final response = await client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(body),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[ERROR] Request timed out after 10 seconds');
          throw TimeoutException('Request timed out');
        },
      );

      debugPrint('[TEST] Response status: ${response.statusCode}');
      debugPrint('[TEST] Response headers: ${response.headers}');
      debugPrint('[TEST] Response body: ${response.body}');

      if (response.statusCode == 404) {
        debugPrint('[ERROR] Model not found: $_model');
        return false;
      }

      if (response.statusCode == 401) {
        debugPrint('[ERROR] Unauthorized: Invalid API key');
        return false;
      }

      if (response.statusCode != 200) {
        debugPrint('[ERROR] Unexpected status code: ${response.statusCode}');
        debugPrint('[ERROR] Response body: ${response.body}');
        return false;
      }

      return true;
    } on TimeoutException catch (e) {
      debugPrint('[ERROR] Connection timed out: $e');
      return false;
    } on http.ClientException catch (e) {
      debugPrint('[ERROR] HTTP client error: $e');
      return false;
    } catch (e, stackTrace) {
      debugPrint('[ERROR] Test connection failed: $e');
      debugPrint('[ERROR] Stack trace: $stackTrace');
      return false;
    } finally {
      client.close();
    }
  }

  void dispose() {
    _streamController.close();
  }
}
