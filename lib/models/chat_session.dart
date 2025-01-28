import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'chat_message.dart';

part 'chat_session.g.dart';

@HiveType(typeId: 2)
class ChatSession extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime timestamp;

  @HiveField(2)
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.timestamp,
    required this.messages,
  });
}
