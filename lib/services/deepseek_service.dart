import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DeepSeekService {
  static const String _baseUrl = 'https://api.deepseek.com/v1';
  final String _apiKey;

  DeepSeekService(this._apiKey);

  Future<Stream<String>> sendMessage(List<Map<String, dynamic>> history) async {
    final uri = Uri.parse('\/chat/completions');
    final request = http.StreamedRequest('POST', uri);

    request.headers.addAll({
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
    });

    final body = {
      'model': 'deepseek-chat',
      'messages': history,
      'stream': true,
    };

    request.sink.add(utf8.encode(json.encode(body)));
    final response = await request.send();

    return response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data:'))
        .map((line) => _parseContent(line));
  }

  String _parseContent(String line) {
    try {
      final jsonData = json.decode(line.substring(5));
      return jsonData['choices'][0]['delta']['content'] ?? '';
    } catch (e) {
      return '';
    }
  }
}
