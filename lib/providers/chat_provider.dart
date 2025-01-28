import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/app_settings.dart';
import '../services/deepseek_service.dart';
import '../services/openrouter_service.dart';
import '../services/voice_service.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:math' show min, max;
import 'dart:async';
import 'dart:collection';

class ChatProvider extends ChangeNotifier {
  static const String _settingsBoxName = 'settings';

  final DeepSeekService _deepseekService;
  final OpenRouterService _openrouterService;
  final VoiceService _voiceService;
  final List<ChatMessage> _messages = [];
  final List<ChatMessage> _history = [];
  bool _isResponding = false;
  String _systemPrompt = '';
  String? _accountBalance;
  Box<AppSettings>? _settingsBox;

  final StreamController<String> _ttsController = StreamController<String>();
  StreamSubscription<String>? _ttsSubscription;
  final Queue<String> _ttsQueue = Queue<String>();
  bool _isProcessingTts = false;
  StringBuffer _currentTtsBuffer = StringBuffer();
  DateTime _lastTtsChunkTime = DateTime.now();
  int _lastChunkSize = 100; // Initial chunk size

  bool get isResponding => _isResponding;
  bool get isListening => _voiceService.isListening;
  bool get isSpeaking => _voiceService.isSpeaking;
  bool get isMuted => _voiceService.isMuted;
  String get systemPrompt => _systemPrompt;
  String get apiKey => _deepseekService.apiKey;
  String get openrouterApiKey {
    if (_settingsBox == null) {
      debugPrint('[Settings] Warning: Settings box not initialized yet');
      return '';
    }
    try {
      final settings = _settingsBox!.get(0);
      if (settings == null) {
        debugPrint('[Settings] Warning: No settings found in Hive');
        return '';
      }
      final key = settings.openrouterApiKey;
      debugPrint('[Settings] Retrieved OpenRouter API key from Hive: ${key.isNotEmpty ? "Present" : "Empty"}');
      return key;
    } catch (e) {
      debugPrint('[Settings] Error getting OpenRouter API key: $e');
      return '';
    }
  }
  String? get accountBalance => _accountBalance;
  String get selectedModel => _getSettings().selectedModel;
  String get customOpenrouterModel => _getSettings().customOpenrouterModel;

  ChatProvider(this._deepseekService, this._openrouterService, this._voiceService) {
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
      _currentTtsBuffer.write(text);

      // Get the current buffered text
      final currentText = _currentTtsBuffer.toString();

      // Always wait for at least 100 chars
      if (currentText.length < 100) {
        return; // Keep accumulating text
      }

      // For the first chunk, ensure we have a complete sentence or substantial phrase
      if (_lastChunkSize == 100) {
        // Find a good break point for the first chunk
        final firstBreakPoint = _findBreakPoint(currentText, currentText.length);
        if (firstBreakPoint >= 100) {  // Only process if we have enough text
          final firstChunk = currentText.substring(0, firstBreakPoint).trim();
          if (firstChunk.isNotEmpty && firstChunk.length >= 100) {
            _ttsQueue.add(firstChunk);
            _currentTtsBuffer = StringBuffer(currentText.substring(firstBreakPoint));
            _lastChunkSize = firstChunk.length * 2; // Double the size for next chunk
            _lastTtsChunkTime = DateTime.now();
            debugPrint('[Chat] First chunk size: ${firstChunk.length} chars, next target: $_lastChunkSize');
            _processTtsQueue();
          }
        }
        return;
      }

      // Natural chunking points - only break on strong punctuation and major phrase boundaries
      final naturalBreaks = RegExp(r'[.!?]\s+|\n|\s+(?=and\s|but\s|however\s|nevertheless\s|conversely\s|meanwhile\s|furthermore\s|moreover\s)');

      // Don't break if we're in the middle of a number or abbreviation
      final inNumber = RegExp(r'\d+\.\d+$');
      final inAbbreviation = RegExp(r'[A-Z]\.$');

      // Check if we should flush based on conditions - removed timeout condition
      bool shouldFlush = currentText.length >= _lastChunkSize ||
                        (naturalBreaks.hasMatch(currentText) &&
                         !inNumber.hasMatch(currentText) &&
                         !inAbbreviation.hasMatch(currentText) &&
                         currentText.length >= max(100, _lastChunkSize));

      if (shouldFlush && _currentTtsBuffer.isNotEmpty) {
        final breakPoint = _findBreakPoint(currentText, currentText.length);
        if (breakPoint >= 100) {  // Only process if we have enough text
          final chunk = currentText.substring(0, breakPoint).trim();
          if (chunk.isNotEmpty && chunk.length >= 100) {
            _ttsQueue.add(chunk);
            // Double the target size for next chunk, but don't exceed all remaining text
            _lastChunkSize = min(chunk.length * 2, currentText.length);
            _currentTtsBuffer = StringBuffer(currentText.substring(breakPoint));
            _lastTtsChunkTime = DateTime.now();
            debugPrint('[Chat] Chunk size: ${chunk.length} chars, next target: $_lastChunkSize');
            _processTtsQueue();
          }
        }
      }
    });
  }

  // Helper method to find a good break point in text
  int _findBreakPoint(String text, int targetLength) {
    // First try to find a sentence end near target length
    final sentenceEnd = text.lastIndexOf(RegExp(r'[.!?]\s+'), targetLength);
    if (sentenceEnd != -1 && sentenceEnd >= 100) {
      return sentenceEnd + 1;
    }

    // Then try to find a comma or conjunction near target length
    final phraseBoundary = text.lastIndexOf(RegExp(r',\s+|\s+(?=and\s|but\s|or\s)'), targetLength);
    if (phraseBoundary != -1 && phraseBoundary >= 100) {
      return phraseBoundary + 1;
    }

    // If we have enough text but no good break point, look for any break point after 100 chars
    final anyBreak = text.lastIndexOf(RegExp(r'[.!?,]\s+|\s+(?=and\s|but\s|or\s)'), targetLength);
    if (anyBreak != -1 && anyBreak >= 100) {
      return anyBreak + 1;
    }

    // Finally, just find the last space after minimum length
    final lastSpace = text.lastIndexOf(' ', targetLength);
    return lastSpace != -1 && lastSpace >= 100 ? lastSpace : max(100, targetLength);
  }

  void _processTtsQueue() async {
    if (_isProcessingTts || _ttsQueue.isEmpty) return;

    _isProcessingTts = true;
    try {
      while (_ttsQueue.isNotEmpty) {
        final text = _ttsQueue.first;
        // Only speak non-reasoning content
        if (!text.contains('REASONING_START') && !text.contains('SPLIT_MESSAGE')) {
          debugPrint('[Chat] Speaking phrase (${text.length} chars): ${text.substring(0, min(50, text.length))}...');
          await _voiceService.speak(text);
          await Future.delayed(const Duration(milliseconds: 50)); // Shorter pause between chunks
        }
        _ttsQueue.removeFirst();
      }

      // Speak any remaining buffered content
      if (_currentTtsBuffer.isNotEmpty) {
        final remainingText = _currentTtsBuffer.toString();
        _currentTtsBuffer.clear();
        if (!remainingText.contains('REASONING_START') && !remainingText.contains('SPLIT_MESSAGE')) {
          debugPrint('[Chat] Speaking final phrase (${remainingText.length} chars): ${remainingText.substring(0, min(50, remainingText.length))}...');
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

  // Add method to clear TTS state
  void clearTtsState() {
    debugPrint('[Chat] Clearing TTS state');
    _ttsQueue.clear();
    _currentTtsBuffer.clear();
    _isProcessingTts = false;
    _lastChunkSize = 100; // Reset chunk size
  }

  Future<void> stopSpeaking() async {
    clearTtsState();
    await _voiceService.stopSpeaking();
  }

  @override
  void dispose() {
    _ttsQueue.clear();
    _ttsSubscription?.cancel();
    _ttsController.close();
    super.dispose();
  }

  Future<void> _initServices() async {
    try {
      debugPrint('[Settings] Starting initialization...');

      // Initialize Hive box first
      _settingsBox = await Hive.openBox<AppSettings>(_settingsBoxName);
      debugPrint('[Settings] Opened Hive settings box');

      // Get current settings or create new ones
      AppSettings settings;
      if (_settingsBox!.isEmpty) {
        settings = AppSettings.defaults();
        await _settingsBox!.put(0, settings);
        debugPrint('[Settings] Created new settings in Hive');
      } else {
        settings = _settingsBox!.get(0)!;
        debugPrint('[Settings] Loaded existing settings from Hive');
      }

      // Debug print the actual settings content
      debugPrint('[Settings] Current settings state:');
      debugPrint('  - System Prompt: ${settings.systemPrompt.substring(0, min(20, settings.systemPrompt.length))}...');
      debugPrint('  - Selected Model: ${settings.selectedModel}');
      debugPrint('  - DeepSeek API Key: ${settings.apiKey.isNotEmpty ? "Present" : "Empty"}');
      debugPrint('  - OpenRouter API Key: ${settings.openrouterApiKey.isNotEmpty ? "Present" : "Empty"}');

      // Update system prompt
      _systemPrompt = settings.systemPrompt;

      // Initialize services with stored keys
      debugPrint('[Settings] Initializing services with stored keys...');

      // Initialize DeepSeek service
      if (settings.apiKey.isNotEmpty) {
        await _deepseekService.updateApiKey(settings.apiKey);
        debugPrint('[Settings] Initialized DeepSeek service with stored key');
      } else {
        debugPrint('[Settings] No DeepSeek API key found in settings');
      }

      // Initialize OpenRouter service
      if (settings.openrouterApiKey.isNotEmpty) {
        await _openrouterService.updateApiKey(settings.openrouterApiKey);
        debugPrint('[Settings] Initialized OpenRouter service with key: ${settings.openrouterApiKey.substring(0, min(10, settings.openrouterApiKey.length))}...');
      } else {
        debugPrint('[Settings] No OpenRouter API key found in settings');
      }

      // Set the appropriate model
      debugPrint('[Settings] Setting model: ${settings.selectedModel}');
      if (settings.selectedModel.startsWith('openrouter')) {
        if (settings.selectedModel == 'openrouter-custom' && settings.customOpenrouterModel.isNotEmpty) {
          _openrouterService.setModel(settings.customOpenrouterModel);
          debugPrint('[Settings] Set custom OpenRouter model: ${settings.customOpenrouterModel}');
        } else if (settings.selectedModel == 'openrouter-deepseek-r1') {
          _openrouterService.setModel('deepseek/deepseek-r1');
          debugPrint('[Settings] Set OpenRouter model: deepseek/deepseek-r1');
        } else if (settings.selectedModel == 'openrouter-deepseek-r1-distill') {
          _openrouterService.setModel('deepseek/deepseek-r1-distill-llama-70b');
          debugPrint('[Settings] Set OpenRouter model: deepseek/deepseek-r1-distill-llama-70b');
        }
      } else {
        final model = settings.selectedModel == 'deepseek-reasoner' ? 'deepseek-reasoner' : 'deepseek-chat';
        await _deepseekService.setModel(model);
        debugPrint('[Settings] Set DeepSeek model: $model');
      }

      // Initialize voice service
      await _initVoiceService();

      // Refresh balance last
      await refreshBalance();

      notifyListeners();
      debugPrint('[Settings] Initialization complete');
    } catch (e, stackTrace) {
      debugPrint('[Settings] Error in _initServices: $e');
      debugPrint('[Settings] Stack trace: $stackTrace');
      // Create a default settings if Hive fails
      _systemPrompt = AppSettings.defaults().systemPrompt;
      notifyListeners();
    }
  }

  Future<void> _initVoiceService() async {
    final available = await _voiceService.init();
    if (!available) {
      debugPrint('Speech recognition not available on this device');
    }
  }

  Future<void> updateSystemPrompt(String prompt) async {
    _systemPrompt = prompt;
    final settings = _getSettings() ?? AppSettings.defaults();
    settings.systemPrompt = prompt;
    await _settingsBox!.put(0, settings);
    notifyListeners();
  }

  Future<void> updateApiKey(String apiKey) async {
    debugPrint('[Settings] Updating DeepSeek API key');

    try {
      // Update service first
      await _deepseekService.updateApiKey(apiKey);

      // Then update Hive storage
      AppSettings settings = _settingsBox!.get(0) ?? AppSettings.defaults();
      settings.apiKey = apiKey;
      await _settingsBox!.put(0, settings);
      debugPrint('[Settings] Saved DeepSeek API key to Hive');

      await refreshBalance();
      notifyListeners();
    } catch (e) {
      debugPrint('[Settings] Error saving DeepSeek API key: $e');
      rethrow;
    }
  }

  Future<void> updateOpenRouterApiKey(String apiKey) async {
    debugPrint('[Settings] Updating OpenRouter API key');

    if (_settingsBox == null) {
      debugPrint('[Settings] Error: Cannot update OpenRouter API key - settings box not initialized');
      return;
    }

    try {
      // Get current settings
      AppSettings settings = _settingsBox!.get(0) ?? AppSettings.defaults();

      // Update both storage and service
      settings.openrouterApiKey = apiKey;
      await _settingsBox!.put(0, settings);
      await _openrouterService.updateApiKey(apiKey);

      debugPrint('[Settings] Saved OpenRouter API key to Hive: ${apiKey.substring(0, min(10, apiKey.length))}...');

      if (selectedModel.startsWith('openrouter')) {
        await refreshBalance();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[Settings] Error saving OpenRouter API key: $e');
      rethrow;
    }
  }

  Future<void> updateSelectedModel(String model) async {
    final settings = _getSettings();
    final previousModel = settings.selectedModel;
    settings.selectedModel = model;
    await _settingsBox!.put(0, settings);

    // If switching to OpenRouter, ensure we have the API key set
    if (model.startsWith('openrouter') && settings.openrouterApiKey.isNotEmpty) {
      await _openrouterService.updateApiKey(settings.openrouterApiKey);
    }

    if (model.startsWith('openrouter')) {
      if (model == 'openrouter-custom') {
        _openrouterService.setModel(settings.customOpenrouterModel);
      } else if (model == 'openrouter-deepseek-r1') {
        _openrouterService.setModel('deepseek/deepseek-r1');
      } else if (model == 'openrouter-deepseek-r1-distill') {
        _openrouterService.setModel('deepseek/deepseek-r1-distill-llama-70b');
      }
      // Only fetch balance for OpenRouter
      await refreshBalance();
    } else {
      await _deepseekService.setModel(model == 'deepseek-reasoner' ? 'deepseek-reasoner' : 'deepseek-chat');
      _accountBalance = 'Not available for DeepSeek';
      notifyListeners();
    }

    // Only refresh balance if switching between services
    if (model.startsWith('openrouter') != previousModel.startsWith('openrouter')) {
      await refreshBalance();
    }
    notifyListeners();
  }

  Future<void> updateCustomOpenrouterModel(String model) async {
    final settings = _getSettings() ?? AppSettings.defaults();
    settings.customOpenrouterModel = model;
    await _settingsBox!.put(0, settings);

    if (settings.selectedModel == 'openrouter-custom') {
      _openrouterService.setModel(model);
    }

    notifyListeners();
  }

  Future<void> refreshBalance() async {
    try {
      final settings = _getSettings();
      if (settings.selectedModel.startsWith('openrouter')) {
        _accountBalance = await _openrouterService.getAccountBalance();
        debugPrint('[Settings] Fetched OpenRouter balance: $_accountBalance');
      } else {
        // DeepSeek doesn't support balance checking
        _accountBalance = 'Not available for DeepSeek';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Settings] Error fetching account balance: $e');
      _accountBalance = 'Not available';
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

      final settings = _getSettings() ?? AppSettings.defaults();

      // Create initial response message immediately
      responseMessage = ChatMessage(role: 'assistant', content: '');
      _messages.add(responseMessage);
      notifyListeners();

      // Prepare messages with system prompt
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': _systemPrompt},
        ..._history.map((m) => m.toJson()).toList()
      ];

      debugPrint('[Chat] Sending messages with system prompt: ${messages.length} messages');
      debugPrint('[Chat] First message role: ${messages.first['role']}');
      debugPrint('[Chat] System prompt: ${_systemPrompt.substring(0, min(50, _systemPrompt.length))}...');

      // Get the stream
      final stream = settings.selectedModel.startsWith('openrouter')
          ? await _openrouterService.sendMessage(messages)
          : await _deepseekService.sendMessage(messages);

      // Process each chunk as it arrives
      await for (String chunk in stream) {
        // Process special tokens
        if (chunk == '🤔REASONING_START🤔') {
          isInReasoning = true;
          if (reasoningMessage == null) {
            reasoningMessage = ChatMessage(role: 'assistant', content: '[Reasoning]\n');
            _messages.add(reasoningMessage);
            notifyListeners();
          }
          continue;
        }
        if (chunk == '🤔REASONING_END🤔') {
          isInReasoning = false;
          continue;
        }
        if (chunk == '💫SPLIT_MESSAGE💫') {
          if (!settings.selectedModel.startsWith('openrouter')) {
            responseMessage = ChatMessage(role: 'assistant', content: '');
            _messages.add(responseMessage);
            notifyListeners();
          }
          continue;
        }

        // Process content chunks
        if (isInReasoning) {
          currentReasoningBuffer.write(chunk);
          if (reasoningMessage != null) {
            reasoningMessage.content = '[Reasoning]\n${currentReasoningBuffer.toString()}';
            notifyListeners();
          }
        } else {
          // For regular content, update both display and TTS immediately
          if (responseMessage != null) {
            currentResponseBuffer.write(chunk);
            responseMessage.content = currentResponseBuffer.toString();
            notifyListeners();
          }
          // Send chunk to TTS immediately
          if (chunk.trim().isNotEmpty) {
            _ttsController.add(chunk);
          }
        }
      }

      // Add final message to history
      if (responseMessage != null) {
        _history.add(responseMessage);
      }

    } catch (e) {
      debugPrint('Error in sendMessage: $e');
      final errorMessage = ChatMessage(
        role: 'assistant',
        content: 'I apologize, but I encountered an error while processing your message. Please try again.',
      );
      _messages.add(errorMessage);
    } finally {
      _isResponding = false;
      notifyListeners();
    }
  }

  Future<bool> testApiConnection() async {
    try {
      final settings = _getSettings() ?? AppSettings.defaults();
      final isConnected = settings.selectedModel.startsWith('openrouter')
          ? await _openrouterService.testConnection()
          : await _deepseekService.testConnection();
      return isConnected;
    } catch (e) {
      debugPrint('Error testing API connection: $e');
      return false;
    }
  }

  void toggleMute() {
    _voiceService.toggleMute();
    notifyListeners();
  }

  Future<void> updateUseReasoningModel(bool value) async {
    final settings = _getSettings() ?? AppSettings.defaults();
    settings.useReasoningModel = value;
    await _settingsBox!.put(0, settings);
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

  // Helper method to safely get settings
  AppSettings _getSettings() {
    if (_settingsBox == null || !_settingsBox!.isOpen) {
      debugPrint('[Settings] Warning: Settings box not initialized or not open');
      return AppSettings.defaults();
    }
    try {
      return _settingsBox!.get(0) ?? AppSettings.defaults();
    } catch (e) {
      debugPrint('[Settings] Error accessing settings: $e');
      return AppSettings.defaults();
    }
  }
}
