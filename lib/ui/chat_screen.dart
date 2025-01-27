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
          FloatingActionButton(
            onPressed: () async {
              // TODO: Implement voice input
              // final transcript = await provider.startVoiceInput();
              // if (transcript != null) {
              //   provider.sendMessage(transcript);
              // }
            },
            child: Icon(Icons.mic),
          ),
        ],
      ),
    );
  }

  void _showSessionHistory(BuildContext context) {
    // TODO: Implement session history
  }
}
