import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/main_navigation_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/threads_service.dart';
import 'services/users_service.dart';
import 'services/notifications.dart';
import 'screens/thread_screen.dart';
import 'services/http_client.dart';

import 'state/threads_state.dart';
import 'services/ws_client.dart';
// import 'state/patterns_state.dart';
import 'state/sequencer/table.dart';
import 'state/sequencer/playback.dart';
import 'state/sequencer/sample_bank.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  // Apply DevHttpOverrides for stage environment to trust self-signed certificates
  final env = dotenv.env['ENV'] ?? '';
  if (env == 'stage') {
    HttpOverrides.global = DevHttpOverrides();
  }
  
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthService()),
        Provider(create: (context) => WebSocketClient()),
        ChangeNotifierProvider(create: (context) => TableState()),
        ChangeNotifierProvider(create: (context) => PlaybackState(Provider.of<TableState>(context, listen: false))),
        ChangeNotifierProvider(create: (context) => SampleBankState()),
        ChangeNotifierProvider(
          create: (context) => ThreadsState(
            wsClient: Provider.of<WebSocketClient>(context, listen: false),
            tableState: Provider.of<TableState>(context, listen: false),
            playbackState: Provider.of<PlaybackState>(context, listen: false),
            sampleBankState: Provider.of<SampleBankState>(context, listen: false),
          ),
        ),
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
        title: 'App',
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
  StreamSubscription? _notifSub;
  NotificationsService? _notificationsService;
  
  @override
  void initState() {
    super.initState();
    // Remove the immediate call to _syncCurrentUser() since it will be called
    // reactively when AuthService completes loading
  }

  void _syncCurrentUser() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final threadsService = Provider.of<ThreadsService>(context, listen: false);
    final wsClient = Provider.of<WebSocketClient>(context, listen: false);
    
    if (authService.currentUser != null) {
      threadsState.setCurrentUser(
        authService.currentUser!.id,
        authService.currentUser!.name,
      );
      
      // Initialize single WebSocket connection for this user
      _initializeThreadsService(threadsService, authService.currentUser!.id, context);
      _setupNotifications(wsClient);
    } else {
    }
  }

  void _initializeThreadsService(ThreadsService threadsService, String userId, BuildContext context) async {
    try {
      final success = await threadsService.connectRealtime(userId);
      if (success) {
        // Get UsersService and request online users
        final usersService = Provider.of<UsersService>(context, listen: false);
        usersService.requestOnlineUsers();
      } else {
      }
    } catch (e) {
    }
  }

  void _setupNotifications(WebSocketClient wsClient) {
    // Initialize lightweight notifications stream and show snackbars globally
    _notificationsService?.dispose();
    final notifications = NotificationsService(wsClient: wsClient);
    _notificationsService = notifications;
    _notifSub?.cancel();
    _notifSub = notifications.stream.listen((event) {
      // Do not show messageCreated banner if already on same thread screen
      bool suppress = false;
      if (event.type == AppNotificationType.messageCreated) {
        try {
          final threadsState = Provider.of<ThreadsState>(context, listen: false);
          if (threadsState.activeThread?.id == event.threadId) {
            suppress = true;
          }
        } catch (_) {}
      }
      if (!suppress) {
        final snack = SnackBar(
          content: Text('${event.title}: ${event.body}'),
          action: (event.threadId != null)
              ? SnackBarAction(
                  label: 'Open',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ThreadScreen(threadId: event.threadId!, highlightNewest: event.type == AppNotificationType.messageCreated),
                      ),
                    );
                  },
                )
              : null,
        );
        ScaffoldMessenger.of(context).showSnackBar(snack);
      }
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _notificationsService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show users screen as the initial view
    return Consumer2<AuthService, ThreadsService>(
      builder: (context, authService, threadsService, child) {
        // 🔧 FIX: Sync current user when AuthService finishes loading and user is authenticated
        if (!authService.isLoading && authService.isAuthenticated && authService.currentUser != null && !_hasInitializedUser) {
          _hasInitializedUser = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
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
          });
        }
        
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

        if (!authService.isAuthenticated) {
          return const LoginScreen();
        }

        return const MainNavigationScreen();
      },
    );
  }
}


