import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 1)
class ChatMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String role;  // 'user', 'assistant', or 'system'

  @HiveField(2)
  String content;  // Main message content

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  String? reasoningContent;  // Optional reasoning content from the model

  @HiveField(5)
  String? name;  // Optional name field for system messages

  ChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent,
    this.name,
    DateTime? timestamp,
  }) : id = const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'role': role,
      'content': content,
    };

    if (name != null) {
      json['name'] = name!;
    }

    return json;
  }

  // Helper for creating system messages
  static ChatMessage system(String content, {String? name}) {
    return ChatMessage(
      role: 'system',
      content: content,
      name: name,
    );
  }

  // Helper for creating user messages
  static ChatMessage user(String content) {
    return ChatMessage(
      role: 'user',
      content: content,
    );
  }

  // Helper for creating assistant messages
  static ChatMessage assistant(String content, {String? reasoningContent}) {
    return ChatMessage(
      role: 'assistant',
      content: content,
      reasoningContent: reasoningContent,
    );
  }
}
