import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/app_settings.dart';
import '../services/deepseek_service.dart';
import '../services/voice_service.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:math' show min;
import 'dart:async';
import 'dart:collection';

class ChatProvider extends ChangeNotifier {
  static const String _settingsBoxName = 'settings';

  final DeepSeekService _deepseekService;
  final VoiceService _voiceService;
  final List<ChatMessage> _messages = [];
  final List<ChatMessage> _history = [];
  bool _isResponding = false;
  String _systemPrompt = '';
  String? _accountBalance;
  late Box<AppSettings> _settingsBox;

  final StreamController<String> _ttsController = StreamController<String>();
  StreamSubscription<String>? _ttsSubscription;
  final Queue<String> _ttsQueue = Queue<String>();
  bool _isProcessingTts = false;
  StringBuffer _currentTtsBuffer = StringBuffer();
  DateTime _lastTtsChunkTime = DateTime.now();

  bool get isResponding => _isResponding;
  bool get isListening => _voiceService.isListening;
  bool get isSpeaking => _voiceService.isSpeaking;
  bool get isMuted => _voiceService.isMuted;
  String get systemPrompt => _systemPrompt;
  String get apiKey => _deepseekService.apiKey;
  String? get accountBalance => _accountBalance;
  bool get useReasoningModel => _settingsBox.get(0)?.useReasoningModel ?? false;

  ChatProvider(this._deepseekService, this._voiceService) {
    _initServices();
    _initTtsListener();
    _voiceService.setTtsCompleteCallback(_onTtsComplete);
    _voiceService.setStateChangeCallback(() {
      debugPrint('[Chat] Voice service state changed, notifying listeners');
      notifyListeners();
    });
  }

  void _initTtsListener() {
    _ttsSubscription = _ttsController.stream.listen((text) {
      // Add to current buffer
      _currentTtsBuffer.write(text);

      // Check if we should flush the buffer (after a short delay or on punctuation)
      if (text.contains(RegExp(r'[.!?,]')) ||
          DateTime.now().difference(_lastTtsChunkTime) > const Duration(milliseconds: 500)) {
        if (_currentTtsBuffer.isNotEmpty) {
          _ttsQueue.add(_currentTtsBuffer.toString());
          _currentTtsBuffer.clear();
          _processTtsQueue();
        }
      }
      _lastTtsChunkTime = DateTime.now();
    });
  }

  void _processTtsQueue() async {
    if (_isProcessingTts || _ttsQueue.isEmpty) return;

    _isProcessingTts = true;
    try {
      while (_ttsQueue.isNotEmpty) {
        final text = _ttsQueue.first;
        // Only speak non-reasoning content
        if (!text.contains('REASONING_START') && !text.contains('SPLIT_MESSAGE')) {
          debugPrint('[Chat] Speaking phrase: $text');
          await _voiceService.speak(text);
        }
        _ttsQueue.removeFirst();
      }

      // Speak any remaining buffered content
      if (_currentTtsBuffer.isNotEmpty) {
        final remainingText = _currentTtsBuffer.toString();
        _currentTtsBuffer.clear();
        if (!remainingText.contains('REASONING_START') && !remainingText.contains('SPLIT_MESSAGE')) {
          debugPrint('[Chat] Speaking final phrase: $remainingText');
          await _voiceService.speak(remainingText);
        }
      }

      if (_ttsQueue.isEmpty) {
        debugPrint('[Chat] All TTS chunks completed, triggering completion');
        _voiceService.onTtsQueueComplete();
      }
    } finally {
      _isProcessingTts = false;
    }
  }

  @override
  void dispose() {
    _ttsQueue.clear();
    _ttsSubscription?.cancel();
    _ttsController.close();
    super.dispose();
  }

  Future<void> _initServices() async {
    await _initVoiceService();
    await _initSettings();
    refreshBalance();
  }

  Future<void> _initSettings() async {
    // Open Hive box
    _settingsBox = await Hive.openBox<AppSettings>(_settingsBoxName);

    // Load settings or create defaults
    final settings = _settingsBox.get(0) ?? AppSettings.defaults();
    _systemPrompt = settings.systemPrompt;

    // Update API key if different
    if (settings.apiKey != _deepseekService.apiKey) {
      await _deepseekService.updateApiKey(settings.apiKey);
    }

    // Set the model
    await _deepseekService.setModel(settings.useReasoningModel ? 'deepseek-reasoner' : 'deepseek-chat');

    notifyListeners();
  }

  Future<void> _initVoiceService() async {
    final available = await _voiceService.init();
    if (!available) {
      debugPrint('Speech recognition not available on this device');
    }
  }

  Future<void> updateSystemPrompt(String prompt) async {
    _systemPrompt = prompt;
    final settings = _settingsBox.get(0) ?? AppSettings.defaults();
    settings.systemPrompt = prompt;
    await _settingsBox.put(0, settings);
    notifyListeners();
  }

  Future<void> updateApiKey(String apiKey) async {
    await _deepseekService.updateApiKey(apiKey);

    final settings = _settingsBox.get(0) ?? AppSettings.defaults();
    settings.apiKey = apiKey;
    await _settingsBox.put(0, settings);

    // Refresh balance with new API key
    await refreshBalance();
    notifyListeners();
  }

  Future<void> refreshBalance() async {
    try {
      _accountBalance = await _deepseekService.getAccountBalance();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching account balance: $e');
      _accountBalance = null;
      notifyListeners();
    }
  }

  Future<void> toggleVoiceInput() async {
    try {
      if (_voiceService.isListening) {
        debugPrint('[Chat] Stopping voice input');
        await _voiceService.stopListening();
      } else {
        debugPrint('[Chat] Starting voice input');
        await _voiceService.startListening((text) {
          if (text.isNotEmpty) {
            debugPrint('[Chat] Voice input received: $text');
            sendMessage(text);
          }
        });
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Chat] Error during voice input: $e');
      // Ensure UI is updated even if there's an error
      notifyListeners();
    }
  }

  List<ChatMessage> get messages => _messages;

  int _findSplitIndex(String text, int startIndex) {
    final sentenceEnd = text.lastIndexOf(RegExp(r'[.!?]'), startIndex);
    if (sentenceEnd != -1) return sentenceEnd + 1;

    final wordBoundary = text.lastIndexOf(' ', startIndex);
    return wordBoundary != -1 ? wordBoundary : startIndex;
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    try {
      _isResponding = true;
      final userMessage = ChatMessage(role: 'user', content: message);
      _messages.add(userMessage);
      _history.add(userMessage);
      notifyListeners();

      var currentReasoningBuffer = StringBuffer();
      var currentResponseBuffer = StringBuffer();
      var isInReasoning = false;
      ChatMessage? reasoningMessage;
      ChatMessage? responseMessage;

      final stream = await _deepseekService.sendMessage(_history.map((m) => m.toJson()).toList());
      await for (String chunk in stream) {
        if (chunk == '🤔REASONING_START🤔') {
          isInReasoning = true;
          // Create reasoning message if it doesn't exist
          if (reasoningMessage == null) {
            reasoningMessage = ChatMessage(role: 'assistant', content: '[Reasoning]\n');
            _messages.add(reasoningMessage);
          }
          continue;
        }
        if (chunk == '🤔REASONING_END🤔') {
          isInReasoning = false;
          continue;
        }
        if (chunk == '💫SPLIT_MESSAGE💫') {
          // Create response message when we transition to it
          responseMessage = ChatMessage(role: 'assistant', content: '');
          _messages.add(responseMessage);
          continue;
        }

        if (isInReasoning) {
          currentReasoningBuffer.write(chunk);
          if (reasoningMessage != null) {
            reasoningMessage.content = '[Reasoning]\n${currentReasoningBuffer.toString().trim()}';
          }
        } else {
          // Only process response content if we're not in reasoning
          if (responseMessage != null) {
            currentResponseBuffer.write(chunk);
            responseMessage.content = currentResponseBuffer.toString().trim();
            // Only send non-reasoning content to TTS
            _ttsController.add(chunk);
          }
        }
        notifyListeners();
      }

      // Add the final response to history
      if (responseMessage != null) {
        _history.add(responseMessage);
      }
      _processTtsQueue();
    } catch (e) {
      debugPrint('[Chat] Error sending message: $e');
      _messages.add(ChatMessage(
        role: 'assistant',
        content: 'I apologize, but I encountered an error. Please try again.'
      ));
    } finally {
      _isResponding = false;
      notifyListeners();
    }
  }

  Future<bool> testApiConnection() async {
    try {
      final isConnected = await _deepseekService.testConnection();
      return isConnected;
    } catch (e) {
      debugPrint('Error testing API connection: $e');
      return false;
    }
  }

  // Add method to stop TTS
  Future<void> stopSpeaking() async {
    _ttsQueue.clear();
    _isProcessingTts = false;
    await _voiceService.stopSpeaking();
  }

  void toggleMute() {
    _voiceService.toggleMute();
    notifyListeners();
  }

  Future<void> updateUseReasoningModel(bool value) async {
    final settings = _settingsBox.get(0) ?? AppSettings.defaults();
    settings.useReasoningModel = value;
    await _settingsBox.put(0, settings);
    await _deepseekService.setModel(value ? 'deepseek-reasoner' : 'deepseek-chat');
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _ttsQueue.clear();
    _isProcessingTts = false;
    _voiceService.stopSpeaking();
    notifyListeners();
  }

  void _onTtsComplete() {
    if (!_voiceService.isListening) {
      toggleVoiceInput();
    }
  }
}
