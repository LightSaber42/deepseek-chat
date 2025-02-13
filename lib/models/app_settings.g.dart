// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 0;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      apiKey: fields[0] as String,
      systemPrompt: fields[1] as String,
      useReasoningModel: fields[2] as bool,
      selectedModel: fields[3] as String,
      openrouterApiKey: fields[4] as String,
      customOpenrouterModel: fields[5] as String,
      ttsEngine: fields[6] as String?,
      ttsSpeed: fields[7] as double,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.apiKey)
      ..writeByte(1)
      ..write(obj.systemPrompt)
      ..writeByte(2)
      ..write(obj.useReasoningModel)
      ..writeByte(3)
      ..write(obj.selectedModel)
      ..writeByte(4)
      ..write(obj.openrouterApiKey)
      ..writeByte(5)
      ..write(obj.customOpenrouterModel)
      ..writeByte(6)
      ..write(obj.ttsEngine)
      ..writeByte(7)
      ..write(obj.ttsSpeed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
