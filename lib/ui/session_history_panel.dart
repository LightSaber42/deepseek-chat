import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import '../models/chat_session.dart';
import '../providers/chat_provider.dart';

class SessionHistoryPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sessions = Hive.box<ChatSession>('sessions').values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sessions.length,
        separatorBuilder: (_, __) => const Divider(height: 24),
        itemBuilder: (context, index) {
          final session = sessions[index];
          return ListTile(
            title: Text('Session ${index + 1}'),
            subtitle: Text(
              '${session.messages.length} messages - '
              'Last active: ${_formatDate(session.lastModified)}'
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _deleteSession(context, session),
            ),
            onTap: () => _loadSession(context, session),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.hour}:${date.minute} ${date.day}/${date.month}/${date.year}';
  }

  void _loadSession(BuildContext context, ChatSession session) {
    context.read<ChatProvider>().loadSession(session);
    Navigator.pop(context);
  }

  void _deleteSession(BuildContext context, ChatSession session) {
    Hive.box<ChatSession>('sessions').delete(session.sessionId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session deleted'))
    );
  }
}