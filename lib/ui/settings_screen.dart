import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/system_tts_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _systemPromptController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _openrouterApiKeyController = TextEditingController();
  final _customModelController = TextEditingController();
  bool _obscureApiKey = true;
  bool _obscureOpenRouterApiKey = true;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _systemPromptController.text = provider.systemPrompt;
    _apiKeyController.text = provider.apiKey;
    _openrouterApiKeyController.text = provider.openrouterApiKey;
    _customModelController.text = provider.customOpenrouterModel;
  }

Widget _buildTTSEngineSelector(ChatProvider provider) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'TTS Engine',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      FutureBuilder<List<dynamic>>(
        future: SystemTTSService.getAvailableEngines(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CircularProgressIndicator();
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return const Text('Error loading TTS engines');
          }

          final engines = snapshot.data!;
          if (engines.isEmpty) {
            return const Text('No TTS engines available');
          }

          // Get current value from provider
          final currentValue = engines.contains(provider.ttsEngine)
              ? provider.ttsEngine
              : engines.contains('com.google.android.tts')
                  ? 'com.google.android.tts'
                  : engines.first;

          return DropdownButtonFormField<String>(
            value: currentValue,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Select TTS Engine',
            ),
            items: engines.map((engine) {
              final name = engine.toString();
              if (name == 'flutter_tts') {
                return DropdownMenuItem(
                  value: name,
                  child: const Text('Flutter TTS (Original)'),
                );
              }
              return DropdownMenuItem(
                value: name,
                child: Text(name.replaceAll('com.', '').replaceAll('.tts', '')),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                provider.updateTTSEngine(value);
              }
            },
          );
        },
      ),
    ],
  );
}

  @override
  void dispose() {
    _systemPromptController.dispose();
    _apiKeyController.dispose();
    _openrouterApiKeyController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'System Prompt',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _systemPromptController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Enter custom system prompt...',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                Provider.of<ChatProvider>(context, listen: false)
                    .updateSystemPrompt(value);
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Model Selection',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Consumer<ChatProvider>(
              builder: (context, provider, _) => Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: provider.selectedModel,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Select Model',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'deepseek-chat',
                        child: Text('DeepSeek Chat'),
                      ),
                      DropdownMenuItem(
                        value: 'deepseek-reasoner',
                        child: Text('DeepSeek Reasoner'),
                      ),
                      DropdownMenuItem(
                        value: 'openrouter-deepseek-r1',
                        child: Text('OpenRouter - DeepSeek R1'),
                      ),
                      DropdownMenuItem(
                        value: 'openrouter-deepseek-r1-distill',
                        child: Text('OpenRouter - DeepSeek R1 Distill (70B)'),
                      ),
                      DropdownMenuItem(
                        value: 'openrouter-custom',
                        child: Text('OpenRouter - Custom Model'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        provider.updateSelectedModel(value);
                      }
                    },
                  ),
                  if (provider.selectedModel == 'openrouter-custom')
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: TextField(
                        controller: _customModelController,
                        decoration: const InputDecoration(
                          hintText: 'Enter custom OpenRouter model name...',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          provider.updateCustomOpenrouterModel(value);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Consumer<ChatProvider>(
              builder: (context, provider, child) => _buildTTSEngineSelector(provider),
            ),
            const SizedBox(height: 24),
            const Text(
              'DeepSeek API Key',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                hintText: 'Enter DeepSeek API key...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureApiKey = !_obscureApiKey;
                    });
                  },
                ),
              ),
              onChanged: (value) {
                Provider.of<ChatProvider>(context, listen: false)
                    .updateApiKey(value);
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'OpenRouter API Key',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _openrouterApiKeyController,
              obscureText: _obscureOpenRouterApiKey,
              decoration: InputDecoration(
                hintText: 'Enter OpenRouter API key...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureOpenRouterApiKey ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureOpenRouterApiKey = !_obscureOpenRouterApiKey;
                    });
                  },
                ),
              ),
              onChanged: (value) {
                Provider.of<ChatProvider>(context, listen: false)
                    .updateOpenRouterApiKey(value);
              },
            ),
            const SizedBox(height: 24),
            Consumer<ChatProvider>(
              builder: (context, provider, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account Balance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        provider.accountBalance ?? 'Not available',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => provider.refreshBalance(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}