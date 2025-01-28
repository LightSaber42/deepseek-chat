import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 0)
class AppSettings extends HiveObject {
  @HiveField(0)
  String apiKey;

  @HiveField(1)
  String systemPrompt;

  @HiveField(2)
  bool useReasoningModel;

  @HiveField(3)
  String selectedModel;

  @HiveField(4)
  String openrouterApiKey;

  @HiveField(5)
  String customOpenrouterModel;

  AppSettings({
    this.apiKey = '',
    this.systemPrompt = 'You having a voice conversation with a user. Please use conversational style and avoid complex formatting. Keep the discussion interactive and refrain from very long monologues. If the user asks for more information, make your responses longer.',
    this.useReasoningModel = false,
    this.selectedModel = 'deepseek-chat',
    this.openrouterApiKey = '',
    this.customOpenrouterModel = '',
  });

  factory AppSettings.defaults() => AppSettings();

  AppSettings copyWith({
    String? apiKey,
    String? systemPrompt,
    bool? useReasoningModel,
    String? selectedModel,
    String? openrouterApiKey,
    String? customOpenrouterModel,
  }) {
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      useReasoningModel: useReasoningModel ?? this.useReasoningModel,
      selectedModel: selectedModel ?? this.selectedModel,
      openrouterApiKey: openrouterApiKey ?? this.openrouterApiKey,
      customOpenrouterModel: customOpenrouterModel ?? this.customOpenrouterModel,
    );
  }
}