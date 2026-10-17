import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/chat/presentation/screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: OfflineDiffusionApp(),
    ),
  );
}

class OfflineDiffusionApp extends StatelessWidget {
  const OfflineDiffusionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Stable Diffusion 2.1',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF6750A4),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF9E86E6),
        scaffoldBackgroundColor: const Color(0xFF131318),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B1B22),
          elevation: 0,
        ),
      ),
      home: const ChatScreen(),
    );
  }
}
