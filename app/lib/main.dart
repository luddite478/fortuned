import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/main_navigation_screen.dart';
import 'screens/login_screen.dart';
import 'screens/thread_screen.dart';
import 'services/auth_service.dart';
import 'services/threads_service.dart';
import 'services/users_service.dart';
import 'services/notifications.dart';
import 'utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/http_client.dart';
import 'models/thread/thread.dart';
import 'models/thread/thread_user.dart';

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
  OverlayEntry? _notifOverlay;
  Timer? _notifOverlayTimer;
  
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
      // Ensure we have latest user fields (e.g., pending_invites_to_threads)
      authService.refreshCurrentUserFromServer();
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
    _notifSub = notifications.stream.listen((event) async {
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
      // If an invitation arrives while on Projects, refresh user + load that thread summary so INVITES appears instantly
      if (event.type == AppNotificationType.invitationReceived) {
        try {
          final auth = Provider.of<AuthService>(context, listen: false);
          await auth.refreshCurrentUserFromServer();
          if (event.threadId != null) {
            final threadsState = Provider.of<ThreadsState>(context, listen: false);
            await threadsState.ensureThreadSummary(event.threadId!);
          }
        } catch (_) {}
      }

      if (!suppress) {
        String body = event.body;
        VoidCallback? onTap;
        if (event.type == AppNotificationType.messageCreated) {
          String senderName = 'Someone';
          try {
            final threadsState = Provider.of<ThreadsState>(context, listen: false);
            final userId = event.raw['user_id'] as String?;
            if (event.threadId != null && userId != null) {
              final thread = threadsState.threads.firstWhere(
                (t) => t.id == event.threadId,
                orElse: () => threadsState.activeThread ?? Thread(id: event.threadId!, createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
              );
              final user = thread.users.firstWhere(
                (u) => u.id == userId,
                orElse: () => ThreadUser(id: userId, name: 'User ${userId.substring(0, 6)}', joinedAt: DateTime.now()),
              );
              senderName = user.name;
            }
          } catch (_) {}
          body = '$senderName sent a new message';
          if (event.threadId != null) {
            onTap = () async {
              try {
                final threadsState = Provider.of<ThreadsState>(context, listen: false);
                await threadsState.ensureThreadSummary(event.threadId!);
                threadsState.setActiveThread(
                  threadsState.threads.firstWhere(
                    (t) => t.id == event.threadId,
                    orElse: () => Thread(id: event.threadId!, createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
                  ),
                );
                await threadsState.loadMessages(event.threadId!, includeSnapshot: false, order: 'asc', limit: 1000);
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ThreadScreen(threadId: event.threadId!, highlightNewest: false, targetMessageId: event.messageId),
                  ),
                );
              } catch (_) {}
            };
          }
        } else if (event.type == AppNotificationType.invitationReceived) {
          final inviter = (event.raw['from_user_name'] as String?) ?? 'Someone';
          body = '$inviter sent you an invitation';
          onTap = null; // stay on current screen
        } else if (event.type == AppNotificationType.invitationAccepted) {
          final userName = (event.raw['user_name'] as String?) ?? 'A collaborator';
          final acceptedUserId = event.raw['user_id'] as String?;
          try {
            final auth = Provider.of<AuthService>(context, listen: false);
            if (acceptedUserId != null && auth.currentUser?.id == acceptedUserId) {
              // Suppress for the user who accepted their own invite
              return;
            }
          } catch (_) {}
          body = '$userName accepted invitation';
          onTap = null;
        }
        _showOverlayNotification(
          title: event.title,
          body: body,
          onTap: onTap,
        );
      }
    });
  }

  void _showOverlayNotification({required String title, required String body, VoidCallback? onTap}) {
    _removeOverlayNotification();
    final overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 20,
          left: 12,
          right: 12,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Container
              (
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.menuEntryBackground,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                  border: Border.all(color: AppColors.menuBorder, width: 1),
                ),
                child: InkWell(
                  onTap: onTap,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          body,
                          style: GoogleFonts.sourceSans3(color: AppColors.menuText, fontSize: 14, fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(overlay);
    _notifOverlay = overlay;
    _notifOverlayTimer = Timer(const Duration(seconds: 4), () {
      _removeOverlayNotification();
    });
  }

  void _removeOverlayNotification() {
    _notifOverlayTimer?.cancel();
    _notifOverlayTimer = null;
    _notifOverlay?.remove();
    _notifOverlay = null;
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _notificationsService?.dispose();
    _removeOverlayNotification();
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


