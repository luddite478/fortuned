import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/pattern_selection_screen.dart';
import 'screens/tracker_screen.dart';
import 'state/patterns_state.dart';
import 'state/tracker_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const NiyyaApp());
}

class NiyyaApp extends StatelessWidget {
  const NiyyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NIYYA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => PatternsState()),
        ],
        child: const MainPage(),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  void initState() {
    super.initState();
    // Initialize patterns state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatternsState>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PatternsState>(
      builder: (context, patternsState, child) {
        if (patternsState.isLoading) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          );
        }
        
        // Show pattern selection screen by default
        return const PatternSelectionScreen();
      },
    );
  }
}

