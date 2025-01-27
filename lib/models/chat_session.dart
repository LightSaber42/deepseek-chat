import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'chat_message.dart';

part 'chat_session.g.dart';

@HiveType(typeId: 1)
class ChatSession extends HiveObject {
  @HiveField(0)
  final String sessionId;

  @HiveField(1)
  final List<ChatMessage> messages;

  @HiveField(2)
  final DateTime created;

  @HiveField(3)
  DateTime lastModified;

  ChatSession({
    String? sessionId,
    List<ChatMessage>? messages,
    DateTime? created,
    DateTime? lastModified,
  }) : sessionId = sessionId ?? const Uuid().v4(),
       messages = messages ?? [],
       created = created ?? DateTime.now(),
       lastModified = lastModified ?? DateTime.now();
}
