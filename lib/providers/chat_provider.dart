import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../services/deepseek_service.dart';
import '../services/voice_service.dart';
import 'dart:convert';

class ChatProvider with ChangeNotifier {
  final DeepSeekService _apiService;
  final VoiceService _voiceService;
  List<ChatMessage> _messages = [];
  bool _isResponding = false;
  bool get isResponding => _isResponding;
  bool get isListening => _voiceService.isListening;

  ChatProvider(this._apiService) : _voiceService = VoiceService() {
    _initVoiceService();
  }

  Future<void> _initVoiceService() async {
    final available = await _voiceService.init();
    if (!available) {
      debugPrint('Speech recognition not available on this device');
    }
  }

  Future<void> toggleVoiceInput() async {
    try {
      if (_voiceService.isListening) {
        await _voiceService.stopListening();
      } else {
        await _voiceService.startListening((text) {
          if (text.isNotEmpty) {
            sendMessage(text);
          }
        });
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error during voice input: $e');
    }
  }

  List<ChatMessage> get messages => _messages;

  Future<void> sendMessage(String text) async {
    try {
      debugPrint('Starting to send message: $text');
      _isResponding = true;
      notifyListeners();

      final userMessage = ChatMessage(role: 'user', content: text);
      _messages = [..._messages, userMessage];
      debugPrint('Added user message to chat history');

      final history = _messages.map((m) => m.toJson()).toList();
      debugPrint('Prepared message history for API: ${json.encode(history)}');

      final responseStream = await _apiService.sendMessage(history);
      debugPrint('Received response stream from API');

      final assistantMessage = ChatMessage(role: 'assistant', content: '');
      _messages = [..._messages, assistantMessage];
      debugPrint('Added empty assistant message to chat history');

      await for (final content in responseStream) {
        debugPrint('Received content chunk: $content');
        _messages.last.content += content;
        notifyListeners();
      }
      debugPrint('Finished processing response stream');
    } catch (e, stackTrace) {
      debugPrint('Error in sendMessage: $e');
      debugPrint('Stack trace: $stackTrace');
      // Add error message to chat
      _messages = [..._messages, ChatMessage(role: 'assistant', content: 'Error: Failed to get response from API')];
    } finally {
      _isResponding = false;
      notifyListeners();
      debugPrint('Message handling completed');
    }
  }

  Future<bool> testApiConnection() async {
    try {
      final isConnected = await _apiService.testConnection();
      return isConnected;
    } catch (e) {
      debugPrint('Error testing API connection: $e');
      return false;
    }
  }
}
