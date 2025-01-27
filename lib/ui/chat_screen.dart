import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'chat_bubble.dart';
import 'settings_screen.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeepSeek Chat'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsScreen()),
          ),
        ),
        actions: [
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
        ],
      ),
      body: Column(
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
    );
  }

  Widget _buildInputControls(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context, listen: false);

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
                  provider.sendMessage(text);
                }
              },
            ),
          ),
          SizedBox(width: 16),
          Consumer<ChatProvider>(
            builder: (context, provider, _) => SizedBox(
              width: 120,  // Increased from 80 to 120
              height: 120, // Increased from 80 to 120
              child: FloatingActionButton(
                onPressed: () => provider.toggleVoiceInput(),
                backgroundColor: provider.isListening ? Colors.red : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  provider.isListening ? Icons.mic_off : Icons.mic,
                  size: 60,  // Increased from 40 to 60
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

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(isConnected ? 'API Connection Successful' : 'API Connection Failed'),
        backgroundColor: isConnected ? Colors.green : Colors.red,
      ),
    );
  }
}
