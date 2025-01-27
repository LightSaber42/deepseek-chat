import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 3)
class AppSettings extends HiveObject {
  @HiveField(0)
  String systemPrompt;

  @HiveField(1)
  String apiKey;

  @HiveField(2)
  bool useReasoningModel;  // true for deepseek-reasoner, false for deepseek-chat

  AppSettings({
    this.systemPrompt = '',
    this.apiKey = '',
    this.useReasoningModel = false,
  });

  factory AppSettings.defaults() {
    return AppSettings(
      systemPrompt: '',
      apiKey: '',
      useReasoningModel: false,
    );
  }
}