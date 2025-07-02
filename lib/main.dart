import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/users_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'state/sequencer_state.dart';
import 'state/threads_state.dart';
// import 'state/patterns_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  print('Loaded .env file');
  print('API_TOKEN: "${dotenv.env['API_TOKEN']}"');
  print('All env keys: ${dotenv.env.keys.toList()}');
  runApp(const NiyyaApp());
}

class NiyyaApp extends StatelessWidget {
  const NiyyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthService()),
        ChangeNotifierProvider(create: (context) => SequencerState()),
        ChangeNotifierProvider(create: (context) => ThreadsState()),
      ],
      child: MaterialApp(
        title: 'NIYYA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // TEMPORARY: Always show MainPage, bypassing login
    return const MainPage();
    // Original code below:
    /*
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        if (authService.isLoading) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
              ),
            ),
          );
        }
        
        if (authService.isAuthenticated) {
          return const MainPage();
        } else {
          return const LoginScreen();
        }
      },
    );
    */
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
    // Sync current user from AuthService to ThreadsState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCurrentUser();
    });
  }

  void _syncCurrentUser() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final sequencerState = Provider.of<SequencerState>(context, listen: false);
    
    print('🔍 Attempting to sync current user...');
    print('🔍 AuthService currentUser: ${authService.currentUser?.id} (${authService.currentUser?.name})');
    print('🔍 ThreadsState currentUserId: ${threadsState.currentUserId}');
    
    // Set the ThreadsState reference in SequencerState
    sequencerState.setThreadsState(threadsState);
    print('🔗 Set ThreadsState reference in SequencerState');
    
    if (authService.currentUser != null) {
      threadsState.setCurrentUser(
        authService.currentUser!.id,
        authService.currentUser!.name,
      );
      print('🔗 Synced current user to ThreadsState: ${authService.currentUser!.id} (${authService.currentUser!.name})');
    } else {
      print('❌ No current user found in AuthService');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show users screen as the initial view
    return const UsersScreen();
  }
}


