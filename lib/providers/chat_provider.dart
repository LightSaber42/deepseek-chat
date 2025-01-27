import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../services/deepseek_service.dart';

class ChatProvider with ChangeNotifier {
  final DeepSeekService _apiService;
  List<ChatMessage> _messages = [];
  bool _isResponding = false;

  ChatProvider(this._apiService);

  List<ChatMessage> get messages => _messages;
  bool get isResponding => _isResponding;

  Future<void> sendMessage(String text) async {
    try {
      _isResponding = true;
      notifyListeners();

      final userMessage = ChatMessage(role: 'user', content: text);
      _messages = [..._messages, userMessage];

      final history = _messages.map((m) => m.toJson()).toList();
      final responseStream = await _apiService.sendMessage(history);

      final assistantMessage = ChatMessage(role: 'assistant', content: '');
      _messages = [..._messages, assistantMessage];

      await for (final content in responseStream) {
        _messages.last.content += content;
        notifyListeners();
      }
    } finally {
      _isResponding = false;
      notifyListeners();
    }
  }
}
