import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/users_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/threads_service.dart';
import 'services/users_service.dart';
import 'services/http_client.dart';
import 'state/sequencer_state.dart';
import 'state/threads_state.dart';
import 'services/ws_client.dart';
// import 'state/patterns_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  print('Loaded .env file');
  print('API_TOKEN: "${dotenv.env['API_TOKEN']}"');
  print('All env keys: ${dotenv.env.keys.toList()}');
  
  // Apply DevHttpOverrides for stage environment to trust self-signed certificates
  final env = dotenv.env['ENV'] ?? '';
  if (env == 'stage') {
    HttpOverrides.global = DevHttpOverrides();
    print('Applied DevHttpOverrides for stage environment');
  }
  
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
        Provider(create: (context) => WebSocketClient()),
        Provider(
          create: (context) => ThreadsService(
            wsClient: Provider.of<WebSocketClient>(context, listen: false),
          ),
        ),
        Provider(
          create: (context) => UsersService(
            wsClient: Provider.of<WebSocketClient>(context, listen: false),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'NIYYA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const MainPage(),
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
  bool _hasInitializedUser = false;
  
  @override
  void initState() {
    super.initState();
    // Remove the immediate call to _syncCurrentUser() since it will be called
    // reactively when AuthService completes loading
  }

  void _syncCurrentUser() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final sequencerState = Provider.of<SequencerState>(context, listen: false);
    final threadsService = Provider.of<ThreadsService>(context, listen: false);
    
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
      
      // Initialize single WebSocket connection for this user
      _initializeThreadsService(threadsService, authService.currentUser!.id, context);
    } else {
      print('❌ No current user found in AuthService');
    }
  }

  void _initializeThreadsService(ThreadsService threadsService, String userId, BuildContext context) async {
    try {
      print('📡 Initializing global ThreadsService for user: $userId');
      final success = await threadsService.connectRealtime(userId);
      if (success) {
        print('📡 ✅ Global ThreadsService connected successfully');
        // Get UsersService and request online users
        final usersService = Provider.of<UsersService>(context, listen: false);
        usersService.requestOnlineUsers();
      } else {
        print('📡 ❌ Failed to connect global ThreadsService');
      }
    } catch (e) {
      print('📡 ❌ Error connecting global ThreadsService: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show users screen as the initial view
    return Consumer2<AuthService, ThreadsService>(
      builder: (context, authService, threadsService, child) {
        // 🐛 DEBUG: Log authentication state
        print('🐛 [DEBUG] AuthService state:');
        print('🐛   - isLoading: ${authService.isLoading}');
        print('🐛   - isAuthenticated: ${authService.isAuthenticated}');
        print('🐛   - currentUser: ${authService.currentUser?.id ?? 'null'}');
        print('🐛   - _hasInitializedUser: $_hasInitializedUser');
        
        // 🔧 FIX: Sync current user when AuthService finishes loading and user is authenticated
        if (!authService.isLoading && authService.isAuthenticated && authService.currentUser != null && !_hasInitializedUser) {
          _hasInitializedUser = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            print('🔧 [FIX] Syncing current user after authentication completed');
            _syncCurrentUser();
          });
        }
        
        // Reset flag if user logs out
        if (!authService.isAuthenticated && _hasInitializedUser) {
          _hasInitializedUser = false;
        }
        
        // Handle logout - disconnect ThreadsService when user logs out
        if (!authService.isAuthenticated && threadsService.isConnected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            threadsService.dispose();
            print('📡 Disconnected ThreadsService due to logout');
          });
        }
        
        if (authService.isLoading) {
          print('🐛 [DEBUG] Showing loading screen');
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
              ),
            ),
          );
        }

        if (!authService.isAuthenticated) {
          print('🐛 [DEBUG] User not authenticated, showing LoginScreen');
          return const LoginScreen();
        }

        print('🐛 [DEBUG] User authenticated, showing UsersScreen');
        return const UsersScreen();
      },
    );
  }
}


