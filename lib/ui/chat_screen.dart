import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'chat_bubble.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeepSeek Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.network_check),
            onPressed: () => _testConnection(context),
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
          SizedBox(width: 8),
          Consumer<ChatProvider>(
            builder: (context, provider, _) => FloatingActionButton(
              onPressed: () => provider.toggleVoiceInput(),
              backgroundColor: provider.isListening ? Colors.red : null,
              child: Icon(provider.isListening ? Icons.mic_off : Icons.mic),
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
