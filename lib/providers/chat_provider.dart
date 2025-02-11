import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/app_settings.dart';
import '../services/base_llm_service.dart';
import '../services/base_tts_service.dart';
import '../services/llm_service_factory.dart';
import '../services/tts_service_factory.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:math' show min, max;
import 'dart:async';
import 'dart:collection';

class ChatProvider extends ChangeNotifier {
  static const String _settingsBoxName = 'settings';

  late BaseLLMService _llmService;
  late BaseTTSService _ttsService;
  final List<ChatMessage> _messages = [];
  final List<ChatMessage> _history = [];
  final List<String> _debugMessages = [];
  bool _isResponding = false;
  String _systemPrompt = '';
  String? _accountBalance;
  Box<AppSettings>? _settingsBox;
  LLMProvider _currentProvider = LLMProvider.deepseek;
  bool _isInitialized = false;

  final StreamController<String> _ttsController = StreamController<String>();
  StreamSubscription<String>? _ttsSubscription;
  final Queue<String> _ttsQueue = Queue<String>();
  bool _isProcessingTts = false;
  StringBuffer _currentTtsBuffer = StringBuffer();
  DateTime _lastChunkTime = DateTime.now();
  static const double _charsPerSecond = 15.0;  // Approximate characters per second for TTS

  bool get isResponding => _isResponding;
  bool get isListening => _isInitialized ? _ttsService.isListening : false;
  bool get isSpeaking => _isInitialized ? _ttsService.isSpeaking : false;
  bool get isMuted => _isInitialized ? _ttsService.isMuted : false;
  bool get isInitialized => _isInitialized;
  String get systemPrompt => _systemPrompt;
  String get apiKey => _llmService.apiKey;
  String get openrouterApiKey => _getSettings().openrouterApiKey;
  String? get accountBalance => _accountBalance;
  String get selectedModel => _getSettings().selectedModel;
  String get customOpenrouterModel => _getSettings().customOpenrouterModel;

  List<ChatMessage> get messages => _messages;
  List<String> get debugMessages => _debugMessages;

  ChatProvider() {
    _initServices().then((_) {
      _isInitialized = true;
      notifyListeners();
    });
    _initTtsListener();
  }

  void _initTtsListener() {
    _ttsSubscription = _ttsController.stream.listen((text) {
      _currentTtsBuffer.write(text);

      // Get the current buffered text
      final currentText = _currentTtsBuffer.toString();

      // For chunks, only break on sentence endings
      // Negative lookbehind (?<!\d) ensures we don't break on decimal points in numbers
      final sentenceBreaks = RegExp(r'(?<!\d)[.!?](?:\s+|\n)');
      final matches = sentenceBreaks.allMatches(currentText).toList();

      // Process if we have at least one sentence break
      if (matches.isNotEmpty) {
        if (_ttsQueue.isEmpty) {
          // For the first chunk, just take the first complete sentence
          final breakPoint = matches.first.end;
          final chunk = currentText.substring(0, breakPoint).trim();

          if (chunk.isNotEmpty) {
            _ttsQueue.add(chunk);
            _currentTtsBuffer = StringBuffer(currentText.substring(breakPoint));
            _lastChunkTime = DateTime.now();
            debugPrint('[Chat] Queuing first sentence (${chunk.length} chars, ~${(chunk.length / _charsPerSecond).toStringAsFixed(1)}s):\n$chunk');
          }
        } else {
          // For subsequent chunks, wait for minimum time based on last chunk
          final now = DateTime.now();
          final timeSinceLastChunk = now.difference(_lastChunkTime).inMilliseconds;
          final lastChunkDuration = (_ttsQueue.last.length / _charsPerSecond * 1000).round();

          // Only process if enough time has passed
          if (timeSinceLastChunk >= lastChunkDuration) {
            // Take all complete sentences available
            final lastBreakPoint = matches.last.end;
            final chunk = currentText.substring(0, lastBreakPoint).trim();

            if (chunk.isNotEmpty) {
              final sentenceCount = matches.length;
              _ttsQueue.add(chunk);
              _currentTtsBuffer = StringBuffer(currentText.substring(lastBreakPoint));
              _lastChunkTime = now;
              debugPrint('[Chat] Queuing large chunk with $sentenceCount sentences (${chunk.length} chars, ~${(chunk.length / _charsPerSecond).toStringAsFixed(1)}s):\n$chunk');
            }
          }
        }

        // Start processing if not already processing
        if (!_isProcessingTts) {
          _processTtsQueue();
        }
      }
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
          final expectedDuration = (text.length / _charsPerSecond).toStringAsFixed(1);
          debugPrint('[Chat] Speaking chunk (${text.length} chars, ~${expectedDuration}s):\n$text');

          try {
            await _ttsService.bufferText(text);
          } catch (e) {
            debugPrint('[Chat] Error during TTS: $e');
          }
        }
        _ttsQueue.removeFirst();
      }

      // Handle any remaining buffered content
      if (_currentTtsBuffer.isNotEmpty) {
        final remainingText = _currentTtsBuffer.toString().trim();
        if (remainingText.isNotEmpty &&
            !remainingText.contains('REASONING_START') &&
            !remainingText.contains('SPLIT_MESSAGE')) {
          await _ttsService.bufferText(remainingText);
        }
        _currentTtsBuffer.clear();
      }

      debugPrint('[Chat] All TTS chunks completed');
      await _ttsService.finishSpeaking();
    } finally {
      _isProcessingTts = false;
    }
  }

  void clearTtsState() {
    debugPrint('[Chat] Clearing TTS state');
    _ttsQueue.clear();
    _currentTtsBuffer.clear();
    _isProcessingTts = false;
    _lastChunkTime = DateTime.now();
  }

  Future<void> stopSpeaking() async {
    if (!_isInitialized) return;
    clearTtsState();
    await _ttsService.stopSpeaking();
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

      // Initialize TTS service
      _ttsService = TTSServiceFactory.createService(
        provider: TTSProvider.system,
        options: TTSServiceFactory.getDefaultOptions(TTSProvider.system),
      );

      // Initialize LLM service based on settings
      await _initializeLLMService(settings);

      debugPrint('[Settings] Services initialized successfully');
    } catch (e) {
      debugPrint('[ERROR] Error initializing services: $e');
      rethrow;
    }
  }

  Future<void> _initializeLLMService(AppSettings settings) async {
    // Determine which provider to use based on settings
    if (settings.selectedModel.startsWith('deepseek')) {
      _currentProvider = LLMProvider.deepseek;
      if (settings.apiKey.isEmpty) {
        debugPrint('[Settings] No DeepSeek API key found in settings');
        return;
      }

      _llmService = LLMServiceFactory.createService(
        provider: LLMProvider.deepseek,
        apiKey: settings.apiKey,
        model: settings.selectedModel,
      );
    } else {
      _currentProvider = LLMProvider.openRouter;
      if (settings.openrouterApiKey.isEmpty) {
        debugPrint('[Settings] No OpenRouter API key found in settings');
        return;
      }

      _llmService = LLMServiceFactory.createService(
        provider: LLMProvider.openRouter,
        apiKey: settings.openrouterApiKey,
        model: settings.customOpenrouterModel.isNotEmpty
            ? settings.customOpenrouterModel
            : LLMServiceFactory.getDefaultModel(LLMProvider.openRouter),
      );
    }

    // Test connection and update balance
    if (await _llmService.testConnection()) {
      _accountBalance = await _llmService.getAccountBalance();
      notifyListeners();
    }
  }

  AppSettings _getSettings() {
    if (_settingsBox == null || _settingsBox!.isEmpty) {
      return AppSettings.defaults();
    }
    return _settingsBox!.get(0)!;
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    if (_settingsBox == null) return;

    await _settingsBox!.put(0, newSettings);
    _systemPrompt = newSettings.systemPrompt;

    // Reinitialize services with new settings
    await _initializeLLMService(newSettings);
    notifyListeners();
  }

  Future<void> updateSystemPrompt(String prompt) async {
    _systemPrompt = prompt;
    final settings = _getSettings();
    settings.systemPrompt = prompt;
    await _settingsBox!.put(0, settings);
    notifyListeners();
  }

  Future<void> updateApiKey(String apiKey) async {
    debugPrint('[Settings] Updating DeepSeek API key');

    try {
      // Update service first
      await _llmService.updateApiKey(apiKey);

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
      await _llmService.updateApiKey(apiKey);

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
      await _llmService.updateApiKey(settings.openrouterApiKey);
    }

    if (model.startsWith('openrouter')) {
      if (model == 'openrouter-custom') {
        await _llmService.updateApiKey(settings.openrouterApiKey);
      } else if (model == 'openrouter-deepseek-r1') {
        await _llmService.updateApiKey('deepseek/deepseek-r1');
      } else if (model == 'openrouter-deepseek-r1-distill') {
        await _llmService.updateApiKey('deepseek/deepseek-r1-distill-llama-70b');
      }
      // Only fetch balance for OpenRouter
      await refreshBalance();
    } else {
      await _llmService.updateApiKey(model == 'deepseek-reasoner' ? 'deepseek-reasoner' : 'deepseek-chat');
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
      await _llmService.updateApiKey(settings.openrouterApiKey);
    }

    notifyListeners();
  }

  Future<void> refreshBalance() async {
    try {
      final settings = _getSettings();
      if (settings.selectedModel.startsWith('openrouter')) {
        _accountBalance = await _llmService.getAccountBalance();
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
    if (!_isInitialized) return;
    try {
      if (_ttsService.isListening) {
        debugPrint('[Chat] Stopping voice input');
        await _ttsService.stopListening();
      } else {
        debugPrint('[Chat] Starting voice input');
        await _ttsService.startListening((text) {
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

  int _findSplitIndex(String text, int startIndex) {
    final sentenceEnd = text.lastIndexOf(RegExp(r'[.!?]'), startIndex);
    if (sentenceEnd != -1) return sentenceEnd + 1;

    final wordBoundary = text.lastIndexOf(' ', startIndex);
    return wordBoundary != -1 ? wordBoundary : startIndex;
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    try {
      _debugMessages.clear();
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

      // Get the stream
      final stream = settings.selectedModel.startsWith('openrouter')
          ? await _llmService.sendMessage(messages)
          : await _llmService.sendMessage(messages);

      // Process each chunk as it arrives
      await for (String chunk in stream) {
        // Add to debug messages
        _debugMessages.add('Chunk: "${chunk}"');
        notifyListeners();

        // Skip empty chunks
        if (chunk.trim().isEmpty) {
          debugPrint('[Chat] Skipping empty chunk');
          continue;
        }

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
            // Create new message without waiting for TTS
            if (responseMessage != null && currentResponseBuffer.isNotEmpty) {
              // Queue the current buffer for TTS without waiting
              _ttsController.add(currentResponseBuffer.toString());
            }

            // Reset for new message
            currentResponseBuffer.clear();
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
          // Update display immediately without waiting for TTS
          if (responseMessage != null) {
            currentResponseBuffer.write(chunk);
            responseMessage.content = currentResponseBuffer.toString();
            notifyListeners();

            // Queue the chunk for TTS without waiting
            _ttsController.add(chunk);
          }
        }
      }

      // Add final message to history
      if (responseMessage != null) {
        _history.add(responseMessage);
      }

      // Wait for TTS to complete before activating mic
      await _ttsService.finishSpeaking();

    } catch (e, stackTrace) {
      debugPrint('[Chat] Error in sendMessage: $e');
      debugPrint('[Chat] Stack trace: $stackTrace');
      final errorMessage = ChatMessage(
        role: 'assistant',
        content: 'I apologize, but I encountered an error while processing your message. Please try again.',
      );
      _messages.add(errorMessage);

      // Ensure voice service is reset
      await _ttsService.stopSpeaking();
    } finally {
      _isResponding = false;
      notifyListeners();
    }
  }

  Future<bool> testApiConnection() async {
    try {
      final settings = _getSettings() ?? AppSettings.defaults();
      final isConnected = settings.selectedModel.startsWith('openrouter')
          ? await _llmService.testConnection()
          : await _llmService.testConnection();
      return isConnected;
    } catch (e) {
      debugPrint('Error testing API connection: $e');
      return false;
    }
  }

  void toggleMute() {
    _ttsService.toggleMute();
    notifyListeners();
  }

  Future<void> updateUseReasoningModel(bool value) async {
    final settings = _getSettings() ?? AppSettings.defaults();
    settings.useReasoningModel = value;
    await _settingsBox!.put(0, settings);
    await _llmService.updateApiKey(value ? 'deepseek-reasoner' : 'deepseek-chat');
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _ttsService.stopSpeaking();
    notifyListeners();
  }

  Future<void> processText(String text) async {
    if (text.trim().isEmpty) return;
    await _ttsService.bufferText(text);
    await _ttsService.finishSpeaking();
  }

  Future<void> processChunk(String chunk, bool isLastChunk) async {
    if (chunk.trim().isEmpty) return;
    await _ttsService.bufferText(chunk);
    if (isLastChunk) {
      await _ttsService.finishSpeaking();
    }
  }

  void clearDebugMessages() {
    _debugMessages.clear();
    notifyListeners();
  }
}
