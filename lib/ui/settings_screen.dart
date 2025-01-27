import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _systemPromptController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _systemPromptController.text = provider.systemPrompt;
    _apiKeyController.text = provider.apiKey;
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    _apiKeyController.dispose();
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
              'API Key',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
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
                ),
              ],
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
              builder: (context, provider, _) => SwitchListTile(
                title: const Text('Use Reasoning Model'),
                subtitle: Text(
                  provider.useReasoningModel
                      ? 'Using deepseek-reasoner (shows reasoning steps)'
                      : 'Using deepseek-chat (faster responses)',
                ),
                value: provider.useReasoningModel,
                onChanged: (bool value) {
                  provider.updateUseReasoningModel(value);
                },
              ),
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