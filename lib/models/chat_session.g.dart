// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatSessionAdapter extends TypeAdapter<ChatSession> {
  @override
  final int typeId = 1;

  @override
  ChatSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatSession(
      sessionId: fields[0] as String?,
      messages: (fields[1] as List?)?.cast<ChatMessage>(),
      created: fields[2] as DateTime?,
      lastModified: fields[3] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatSession obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.sessionId)
      ..writeByte(1)
      ..write(obj.messages)
      ..writeByte(2)
      ..write(obj.created)
      ..writeByte(3)
      ..write(obj.lastModified);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
