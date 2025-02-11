import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/app_settings.dart';
import 'models/chat_message.dart';
import 'models/chat_session.dart';
import 'services/deepseek_service.dart';
import 'services/openrouter_service.dart';
import 'services/voice_service.dart';
import 'providers/chat_provider.dart';
import 'ui/chat_screen.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Register Hive adapters if not already registered
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(AppSettingsAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(ChatMessageAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(ChatSessionAdapter());
  }

  // Load environment variables
  await dotenv.load();

  // Get API keys from environment
  final deepseekApiKey = dotenv.env['DEEPSEEK_API_KEY'] ?? '';
  final openrouterApiKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';

  runApp(MyApp(
    deepseekApiKey: deepseekApiKey,
    openrouterApiKey: openrouterApiKey,
  ));
}

class MyApp extends StatelessWidget {
  final String deepseekApiKey;
  final String openrouterApiKey;

  const MyApp({
    Key? key,
    required this.deepseekApiKey,
    required this.openrouterApiKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatProvider(),
      child: MaterialApp(
        title: 'AI Chat',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const ChatScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}