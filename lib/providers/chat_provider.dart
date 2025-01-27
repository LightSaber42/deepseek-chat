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

class ChatProvider with ChangeNotifier {
  static const String _settingsBoxName = 'settings';

  final DeepSeekService _apiService;
  final VoiceService _voiceService;
  List<ChatMessage> _messages = [];
  bool _isResponding = false;
  String _systemPrompt = '';
  String? _accountBalance;
  late Box<AppSettings> _settingsBox;

  final StreamController<String> _ttsController = StreamController<String>();
  StreamSubscription<String>? _ttsSubscription;
  final Queue<String> _ttsQueue = Queue<String>();
  bool _isProcessingTts = false;

  bool get isResponding => _isResponding;
  bool get isListening => _voiceService.isListening;
  bool get isSpeaking => _voiceService.isSpeaking;
  bool get isMuted => _voiceService.isMuted;
  String get systemPrompt => _systemPrompt;
  String get apiKey => _apiService.apiKey;
  String? get accountBalance => _accountBalance;
  bool get useReasoningModel => _settingsBox.get(0)?.useReasoningModel ?? false;

  ChatProvider(this._apiService) : _voiceService = VoiceService() {
    _initServices();
    _initTtsListener();
    // Set up TTS completion callback
    _voiceService.setTtsCompleteCallback(() {
      if (!_voiceService.isListening) {
        toggleVoiceInput();
      }
    });
  }

  void _initTtsListener() {
    _ttsSubscription = _ttsController.stream.listen((text) {
      _ttsQueue.add(text);
      _processTtsQueue();
    });
  }

  Future<void> _processTtsQueue() async {
    if (_isProcessingTts || _ttsQueue.isEmpty) return;

    _isProcessingTts = true;
    while (_ttsQueue.isNotEmpty) {
      final text = _ttsQueue.first;
      await _voiceService.speak(text);
      _ttsQueue.removeFirst();
    }
    _isProcessingTts = false;
    // Only trigger the TTS completion callback after all chunks are spoken
    if (_ttsQueue.isEmpty && !_isProcessingTts) {
      _voiceService.onTtsQueueComplete();
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
    if (settings.apiKey != _apiService.apiKey) {
      await _apiService.updateApiKey(settings.apiKey);
    }

    // Set the model
    await _apiService.setModel(settings.useReasoningModel ? 'deepseek-reasoner' : 'deepseek-chat');

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
    await _apiService.updateApiKey(apiKey);

    final settings = _settingsBox.get(0) ?? AppSettings.defaults();
    settings.apiKey = apiKey;
    await _settingsBox.put(0, settings);

    // Refresh balance with new API key
    await refreshBalance();
    notifyListeners();
  }

  Future<void> refreshBalance() async {
    try {
      _accountBalance = await _apiService.getAccountBalance();
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

  int _findSplitIndex(String text, int startIndex) {
    final sentenceEnd = text.lastIndexOf(RegExp(r'[.!?]'), startIndex);
    if (sentenceEnd != -1) return sentenceEnd + 1;

    final wordBoundary = text.lastIndexOf(' ', startIndex);
    return wordBoundary != -1 ? wordBoundary : startIndex;
  }

  Future<void> sendMessage(String text) async {
    try {
      _isResponding = true;
      notifyListeners();

      final userMessage = ChatMessage(role: 'user', content: text);
      _messages = [..._messages, userMessage];

      final history = _systemPrompt.isNotEmpty
          ? [
              {'role': 'system', 'content': _systemPrompt},
              ..._messages.map((m) => m.toJson()).toList()
            ]
          : _messages.map((m) => m.toJson()).toList();

      final responseStream = await _apiService.sendMessage(history);
      final assistantMessage = ChatMessage(role: 'assistant', content: '');
      _messages = [..._messages, assistantMessage];

      String displayBuffer = '';
      String ttsBuffer = '';
      bool initialChunkSent = false;
      const int initialChunkSize = 100;
      const int subsequentChunkSize = 500;

      // Clear any existing TTS queue before starting new message
      _ttsQueue.clear();

      // Immediate display updates
      await for (final content in responseStream) {
        // Update display immediately
        displayBuffer += content;
        _messages.last.content = displayBuffer;
        notifyListeners();

        // Accumulate for TTS
        ttsBuffer += content;

        // Handle initial chunk with natural breaks
        if (!initialChunkSent && ttsBuffer.length >= initialChunkSize) {
          final splitIndex = _findSplitIndex(ttsBuffer, initialChunkSize);
          _ttsController.add(ttsBuffer.substring(0, splitIndex));
          ttsBuffer = ttsBuffer.substring(splitIndex);
          initialChunkSent = true;
        }

        // Handle subsequent chunks with natural breaks
        if (initialChunkSent && ttsBuffer.length >= subsequentChunkSize) {
          final splitIndex = _findSplitIndex(ttsBuffer, subsequentChunkSize);
          _ttsController.add(ttsBuffer.substring(0, splitIndex));
          ttsBuffer = ttsBuffer.substring(splitIndex);
        }
      }

      // Process any remaining content
      if (ttsBuffer.isNotEmpty) {
        _ttsController.add(ttsBuffer);
      }

      _isResponding = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Error] Failed to get response: $e');
      _messages = [..._messages, ChatMessage(role: 'assistant', content: 'Error: Failed to get response from API')];
      _isResponding = false;
      notifyListeners();
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
    await _apiService.setModel(value ? 'deepseek-reasoner' : 'deepseek-chat');
    notifyListeners();
  }

  void clearMessages() {
    _messages = [];
    _ttsQueue.clear();
    _isProcessingTts = false;
    _voiceService.stopSpeaking();
    notifyListeners();
  }
}
