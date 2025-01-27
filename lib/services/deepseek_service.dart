import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class DeepSeekService {
  static const String _baseUrl = 'https://api.deepseek.com';
  final String _apiKey;

  DeepSeekService(this._apiKey) {
    debugPrint('DeepSeekService initialized with API key length: ${_apiKey.length}');
  }

  Future<Stream<String>> sendMessage(List<Map<String, dynamic>> history) async {
    final uri = Uri.parse('${_baseUrl}/v1/chat/completions');
    debugPrint('Sending request to: $uri');
    debugPrint('Request history: ${json.encode(history)}');

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
        'model': 'deepseek-chat',
        'messages': history,
        'stream': true,
        'max_tokens': 4096,
        'temperature': 0.7,
      };
      request.body = json.encode(body);
      debugPrint('Request body: ${request.body}');

      final response = await client.send(request);
      debugPrint('Response status code: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        debugPrint('Error response body: $errorBody');
        throw Exception('API request failed with status ${response.statusCode}: $errorBody');
      }

      // Create a broadcast stream so we can listen to it multiple times
      final broadcastStream = response.stream.asBroadcastStream();

      // Debug stream to log raw response
      broadcastStream.transform(utf8.decoder).listen(
        (data) => debugPrint('Raw response data: $data'),
        onError: (e) => debugPrint('Error in raw response stream: $e'),
        onDone: () {
          debugPrint('Raw response stream completed');
          client.close();
        },
      );

      // Process stream for actual use
      return broadcastStream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) {
            debugPrint('Checking line: $line');
            final isData = line.trim().startsWith('data:');
            if (!isData) {
              debugPrint('Skipping non-data line: $line');
            }
            return isData;
          })
          .map((line) {
            debugPrint('Processing line: $line');
            return _parseContent(line);
          })
          .where((content) => content.isNotEmpty) // Filter out empty content
          .handleError((error) {
            debugPrint('Error in stream processing: $error');
            client.close();
            throw error;
          });
    } catch (e, stackTrace) {
      debugPrint('Error in sendMessage: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  String _parseContent(String line) {
    try {
      if (line.trim() == 'data: [DONE]') {
        debugPrint('Received DONE signal');
        return '';
      }

      final jsonData = json.decode(line.substring(5));
      debugPrint('Parsed JSON data: $jsonData');

      String content = '';
      if (jsonData['choices']?[0]?['delta']?['content'] != null) {
        content = jsonData['choices'][0]['delta']['content'];
      } else if (jsonData['choices']?[0]?['delta']?['reasoning_content'] != null) {
        content = '[Reasoning] ' + jsonData['choices'][0]['delta']['reasoning_content'];
      }

      debugPrint('Parsed content: $content');
      return content;
    } catch (e) {
      debugPrint('Error parsing content: $e');
      debugPrint('Problematic line: $line');
      return '';
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
