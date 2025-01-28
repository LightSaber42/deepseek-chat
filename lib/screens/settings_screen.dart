import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            leading: IconButton(
              icon: const Text('Back'),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text('System Prompt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: TextEditingController(text: chatProvider.systemPrompt),
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                    ),
                    onChanged: (value) => chatProvider.updateSystemPrompt(value),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Model Selection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: DropdownButtonFormField<String>(
                    value: chatProvider.selectedModel,
                    decoration: const InputDecoration(
                      labelText: 'Select Model',
                      border: InputBorder.none,
                    ),
                    items: [
                      const DropdownMenuItem(value: 'deepseek-chat', child: Text('DeepSeek Chat')),
                      const DropdownMenuItem(value: 'deepseek-reasoner', child: Text('DeepSeek Reasoner')),
                      const DropdownMenuItem(value: 'openrouter-deepseek-r1', child: Text('OpenRouter DeepSeek R1')),
                      const DropdownMenuItem(value: 'openrouter-deepseek-r1-distill', child: Text('OpenRouter DeepSeek R1 Distill')),
                      const DropdownMenuItem(value: 'openrouter-custom', child: Text('OpenRouter Custom Model')),
                    ],
                    onChanged: (String? value) {
                      if (value != null) {
                        chatProvider.updateSelectedModel(value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('DeepSeek API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextFormField(
                    initialValue: chatProvider.apiKey,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Enter DeepSeek API key...',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () {},
                      ),
                    ),
                    obscureText: true,
                    onChanged: (value) async {
                      await chatProvider.updateApiKey(value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('OpenRouter API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextFormField(
                    initialValue: chatProvider.openrouterApiKey,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Enter OpenRouter API key...',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () {},
                      ),
                    ),
                    obscureText: true,
                    onChanged: (value) async {
                      await chatProvider.updateOpenRouterApiKey(value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Account Balance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Card(
                child: ListTile(
                  title: Text(chatProvider.accountBalance ?? 'Not available'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => chatProvider.refreshBalance(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}