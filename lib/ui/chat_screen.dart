import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../models/chat_message.dart';
import 'chat_bubble.dart';
import 'settings_screen.dart';
import 'debug_window.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _showDebug = false;

  String _formatConversation(List<ChatMessage> messages) {
    final buffer = StringBuffer();

    for (final message in messages) {
      // Add timestamp
      final time = '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}';

      // Format based on message type
      if (message.role == 'user') {
        buffer.writeln('[$time] User:');
        buffer.writeln(message.content.trim());
      } else {
        buffer.writeln('[$time] Assistant:');

        // Handle reasoning content
        if (message.content.startsWith('[Reasoning]')) {
          final parts = message.content.split('\n');
          if (parts.length > 1) {
            buffer.writeln('Reasoning:');
            buffer.writeln(parts.sublist(1).join('\n').trim());
          }
        } else {
          buffer.writeln(message.content.trim());
        }
      }
      buffer.writeln(); // Add blank line between messages
    }

    return buffer.toString().trim();
  }

  void _copyConversation(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final formattedConversation = _formatConversation(provider.messages);

    Clipboard.setData(ClipboardData(text: formattedConversation)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversation copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<ChatProvider>(
          builder: (context, provider, _) {
            String modelName = switch (provider.selectedModel) {
              'deepseek-chat' => 'DeepSeek Chat',
              'deepseek-reasoner' => 'DeepSeek Reasoner',
              'openrouter-deepseek-r1' => 'DeepSeek R1 (OpenRouter)',
              'openrouter-deepseek-r1-distill' => 'DeepSeek R1 Distill (OpenRouter)',
              'openrouter-custom' => 'Custom Model (OpenRouter)',
              _ => 'Chat',
            };
            return Text(modelName);
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsScreen()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy Conversation',
            onPressed: () => _copyConversation(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Conversation',
            onPressed: () => Provider.of<ChatProvider>(context, listen: false).clearMessages(),
          ),
          IconButton(
            icon: const Icon(Icons.network_check),
            onPressed: () => _testConnection(context),
          ),
          Consumer<ChatProvider>(
            builder: (context, provider, _) => IconButton(
              icon: const Icon(Icons.volume_off),
              onPressed: provider.isSpeaking ? () => provider.stopSpeaking() : null,
            ),
          ),
          Consumer<ChatProvider>(
            builder: (context, provider, _) => IconButton(
              icon: Icon(provider.isMuted ? Icons.mic_off : Icons.mic),
              onPressed: () => provider.toggleMute(),
              color: provider.isMuted ? Colors.red : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => _showSessionHistory(context),
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => setState(() => _showDebug = !_showDebug),
            color: _showDebug ? Colors.green : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Consumer<ChatProvider>(
                  builder: (context, provider, _) {
                    return ListView.builder(
                      reverse: true,
                      itemCount: provider.messages.length,
                      itemBuilder: (context, index) {
                        final message = provider.messages.reversed.toList()[index];
                        return ChatBubble(
                          message: message,
                          isResponding: provider.isResponding && index == 0,
                        );
                      },
                    );
                  }
                ),
              ),
              _buildInputControls(context),
            ],
          ),
          if (_showDebug)
            Positioned(
              right: 16,
              top: 16,
              child: Consumer<ChatProvider>(
                builder: (context, provider, _) => DebugWindow(
                  messages: provider.debugMessages,
                  onClose: () => setState(() => _showDebug = false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Type or voice input...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (text) {
                if (text.isNotEmpty) {
                  Provider.of<ChatProvider>(context, listen: false).sendMessage(text);
                }
              },
            ),
          ),
          SizedBox(width: 16),
          Consumer<ChatProvider>(
            builder: (context, provider, _) => SizedBox(
              width: 120,
              height: 120,
              child: FloatingActionButton(
                onPressed: provider.isInitialized ? () => provider.toggleVoiceInput() : null,
                backgroundColor: provider.isListening ? Colors.red : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  provider.isListening ? Icons.mic_off : Icons.mic,
                  size: 60,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSessionHistory(BuildContext context) {
    // TODO: Implement session history
  }

  void _testConnection(BuildContext context) async {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final isConnected = await provider.testApiConnection();
    final serviceName = provider.selectedModel.startsWith('openrouter') ? 'OpenRouter' : 'DeepSeek';

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('$serviceName API Connection ${isConnected ? 'Successful' : 'Failed'}'),
        backgroundColor: isConnected ? Colors.green : Colors.red,
      ),
    );
  }
}
