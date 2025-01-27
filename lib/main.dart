import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/app_settings.dart';
import 'models/chat_message.dart';
import 'models/chat_session.dart';
import 'services/deepseek_service.dart';
import 'providers/chat_provider.dart';
import 'ui/chat_screen.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Register Hive adapters
  Hive.registerAdapter(AppSettingsAdapter());
  Hive.registerAdapter(ChatMessageAdapter());
  Hive.registerAdapter(ChatSessionAdapter());

  // Load environment variables
  await dotenv.load();

  // Get API key from environment
  final apiKey = dotenv.env['DEEPSEEK_API_KEY'] ?? '';

  runApp(MyApp(apiKey: apiKey));
}

class MyApp extends StatelessWidget {
  final String apiKey;

  const MyApp({Key? key, required this.apiKey}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatProvider(DeepSeekService(apiKey)),
      child: MaterialApp(
        title: 'DeepSeek Chat',
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