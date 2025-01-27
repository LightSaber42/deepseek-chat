import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isResponding;

  const ChatBubble({
    required this.message,
    this.isResponding = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showCopyMenu(context),
      child: Align(
        alignment: message.role == 'user'
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: message.role == 'user'
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: Theme.of(context).textTheme.bodyLarge,
                  code: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    fontFamily: 'FiraCode',
                  ),
                  codeblockPadding: const EdgeInsets.all(12),
                  codeblockDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (isResponding)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCopyMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.content_copy),
            title: Text('Copy Message'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.content));
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.schedule),
            title: Text('${_formatTime(message.timestamp)}'),
            enabled: false,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}