import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';

import 'screens/main_navigation_screen.dart';
import 'screens/thread_screen.dart';
import 'screens/sequencer_screen.dart';
import 'widgets/username_creation_dialog.dart';
import 'services/threads_service.dart';
import 'services/users_service.dart';
import 'services/notifications.dart';
import 'utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/http_client.dart';
import 'models/thread/thread.dart';
import 'models/thread/thread_user.dart';
import 'utils/thread_name_generator.dart';

import 'state/user_state.dart';
import 'state/threads_state.dart';
import 'state/audio_player_state.dart';
import 'state/library_state.dart';
import 'state/followed_state.dart';
import 'services/ws_client.dart';
import 'state/sequencer/table.dart';
import 'state/sequencer/playback.dart';
import 'state/sequencer/sample_bank.dart';
import 'state/sequencer_version_state.dart';


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
        ChangeNotifierProvider(create: (context) => UserState()),
        ChangeNotifierProvider(create: (context) => AudioPlayerState()),
        ChangeNotifierProvider(create: (context) => LibraryState()),
        ChangeNotifierProvider(create: (context) => FollowedState()),
        ChangeNotifierProvider(create: (context) => SequencerVersionState()),
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
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;
  
  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    // Remove the immediate call to _syncCurrentUser() since it will be called
    // reactively when UserState completes loading
    
    // Set up callback for syncing library when render uploads complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupLibrarySyncCallback();
    });
  }
  
  void _setupLibrarySyncCallback() {
    final threadsState = context.read<ThreadsState>();
    final libraryState = context.read<LibraryState>();
    final userState = context.read<UserState>();
    
    // Set callback to update library when renders complete uploading
    threadsState.setOnRenderUploadComplete((renderId, url) async {
      final userId = userState.currentUser?.id;
      if (userId != null) {
        await libraryState.updateItemAfterUpload(
          userId: userId,
          renderId: renderId,
          url: url,
        );
      }
    });
    
    debugPrint('📚 [MAIN] Set up library sync callback for render uploads');
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Handle initial link if app was opened from a deep link (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('Got initial deep link: $initialUri');
        if (initialUri.path.startsWith('/join/')) {
          final threadId = initialUri.pathSegments.last;
          // Delay showing confirmation until after build completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showJoinConfirmation(threadId);
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting initial link: $e');
    }

    // Listen for incoming app links while app is running
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Got deep link: $uri');
      if (uri.path.startsWith('/join/')) {
        final threadId = uri.pathSegments.last;
        _showJoinConfirmation(threadId);
      }
    });
  }

  void _showJoinConfirmation(String threadId) {
    // Ensure we have a valid context that can show a dialog
    if (!mounted) return;

    // Check if user needs to create username first
    final userState = context.read<UserState>();
    final currentUsername = userState.currentUser?.username ?? '';
    
    if (currentUsername.isEmpty) {
      // Show username creation dialog first
      _showUsernameCreationForInvite(threadId);
    } else {
      // Show regular join confirmation
      _showJoinDialog(threadId);
    }
  }
  
  void _showUsernameCreationForInvite(String threadId) {
    if (!mounted) return;
    
    final userState = context.read<UserState>();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.menuPageBackground.withOpacity(0.8),
      builder: (context) => UsernameCreationDialog(
        title: 'Join Project',
        message: 'Create a username to join this collaborative project.',
        onSubmit: (username) async {
          // Update username via UserState
          final success = await userState.updateUsername(username);
          if (success) {
            // Close dialog and proceed to join
            if (context.mounted) {
              Navigator.pop(context);
              _acceptInviteAndNavigate(threadId);
            }
          } else {
            throw Exception('Failed to create username. Please try again.');
          }
        },
      ),
    );
  }
  
  void _showJoinDialog(String threadId) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.sequencerPageBackground.withOpacity(0.8),
      builder: (BuildContext context) {
        final size = MediaQuery.of(context).size;
        final dialogWidth = (size.width * 0.8).clamp(280.0, size.width);
        final dialogHeight = (size.height * 0.35).clamp(220.0, size.height);

        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: dialogWidth, height: dialogHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                ),
                clipBehavior: Clip.hardEdge,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Join Pattern Project',
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.sequencerText,
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.close, color: AppColors.sequencerLightText, size: 28),
                              splashRadius: 22,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'You have been invited to join a pattern project. Do you want to accept?',
                          textAlign: TextAlign.left,
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerLightText,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.sequencerText,
                                  side: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                  'Decline',
                                  style: GoogleFonts.sourceSans3(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  _acceptInviteAndNavigate(threadId);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.sequencerAccent,
                                  foregroundColor: AppColors.sequencerText,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: Text(
                                  'Accept',
                                  style: GoogleFonts.sourceSans3(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  Future<void> _acceptInviteAndNavigate(String threadId) async {
    try {
      final threadsState = context.read<ThreadsState>();
      final success = await threadsState.joinThread(threadId: threadId);
      if (success && mounted) {
        await threadsState.ensureThreadSummary(threadId);
        
        // Set active thread and load project into sequencer
        final thread = threadsState.threads.firstWhere(
          (t) => t.id == threadId,
          orElse: () => throw Exception('Thread not found'),
        );
        threadsState.setActiveThread(thread);
        
        // Load project into sequencer
        await threadsState.loadProjectIntoSequencer(threadId);
        
        // Navigate to PatternScreen (sequencer)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const PatternScreen(initialSnapshot: null),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to join project.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _syncCurrentUser() {
    final userState = Provider.of<UserState>(context, listen: false);
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final threadsService = Provider.of<ThreadsService>(context, listen: false);
    final wsClient = Provider.of<WebSocketClient>(context, listen: false);
    final libraryState = Provider.of<LibraryState>(context, listen: false);
    final followedState = Provider.of<FollowedState>(context, listen: false);
    
    if (userState.currentUser != null) {
      threadsState.setCurrentUser(
        userState.currentUser!.id,
        userState.currentUser!.username,  // Fixed: Use username instead of name
      );
      
      // Add listener to keep ThreadsState in sync when username changes
      userState.addListener(() {
        if (userState.currentUser != null) {
          threadsState.setCurrentUser(
            userState.currentUser!.id,
            userState.currentUser!.username,
          );
        }
      });
      
      // Load data on startup (cached for session)
      libraryState.loadPlaylist(userId: userState.currentUser!.id);
      threadsState.loadThreads();
      followedState.loadFollowedUsers(userId: userState.currentUser!.id);
      
      // Initialize single WebSocket connection for this user
      _initializeThreadsService(threadsService, userState.currentUser!.id, context);
      
      // Setup auto-sync on reconnection
      _setupReconnectionHandler(wsClient, userState, threadsState, libraryState, followedState);
      _setupNotifications(wsClient);
    }
  }

  void _initializeThreadsService(ThreadsService threadsService, String userId, BuildContext context) async {
    try {
      debugPrint('🔌 [MAIN] Connecting WebSocket for user: $userId');
      final success = await threadsService.connectRealtime(userId);
      if (success) {
        debugPrint('✅ [MAIN] WebSocket connected successfully');
        
        // Refresh threads to get accurate online status (now that WebSocket is connected)
        final threadsState = Provider.of<ThreadsState>(context, listen: false);
        await threadsState.refreshThreadsInBackground();
        debugPrint('✅ [MAIN] Threads refreshed with online status');
        
        // Get UsersService and request online users
        final usersService = Provider.of<UsersService>(context, listen: false);
        usersService.requestOnlineUsers();
        debugPrint('✅ [MAIN] Online users list requested');
      } else {
        debugPrint('❌ [MAIN] WebSocket connection failed');
      }
    } catch (e) {
      debugPrint('❌ [MAIN] Error initializing WebSocket: $e');
    }
  }
  
  void _setupReconnectionHandler(
    WebSocketClient wsClient,
    UserState userState,
    ThreadsState threadsState,
    LibraryState libraryState,
    FollowedState followedState,
  ) {
    // Listen for connection status changes
    wsClient.connectionStream.listen((isConnected) {
      if (isConnected) {
        debugPrint('✅ [MAIN] WebSocket reconnected - syncing data...');
        _syncDataAfterReconnect(userState, threadsState, libraryState, followedState);
      } else {
        debugPrint('❌ [MAIN] WebSocket disconnected');
      }
    });
  }
  
  Future<void> _syncDataAfterReconnect(
    UserState userState,
    ThreadsState threadsState,
    LibraryState libraryState,
    FollowedState followedState,
  ) async {
    try {
      final userId = userState.currentUser?.id;
      if (userId == null) return;
      
      debugPrint('🔄 [MAIN] Starting data sync after reconnection...');
      
      // 1. Refresh user profile (might have new invites)
      await userState.refreshCurrentUserFromServer();
      debugPrint('✅ [MAIN] User profile refreshed');
      
      // 2. Refresh thread list (new threads, new participants, new messages)
      await threadsState.refreshThreadsInBackground();
      debugPrint('✅ [MAIN] Threads refreshed');
      
      // 3. Refresh playlist (new items might have been added)
      await libraryState.refreshPlaylistInBackground(userId: userId);
      debugPrint('✅ [MAIN] Playlist refreshed');
      
      // 4. Refresh followed users
      await followedState.refreshFollowedUsersInBackground(userId);
      debugPrint('✅ [MAIN] Followed users refreshed');
      
      // 5. Request fresh online users list
      if (mounted) {
        final usersService = Provider.of<UsersService>(context, listen: false);
        usersService.requestOnlineUsers();
        debugPrint('✅ [MAIN] Online users requested');
      }
      
      debugPrint('✅ [MAIN] Data sync complete after reconnection');
    } catch (e) {
      debugPrint('❌ [MAIN] Data sync failed after reconnection: $e');
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
          // Suppress only when user is actively viewing the same thread screen
          if (threadsState.isThreadViewActive && threadsState.activeThread?.id == event.threadId) {
            suppress = true;
          }
        } catch (_) {}
      }
      // If an invitation arrives while on Projects, refresh user + load that thread summary so INVITES appears instantly
      if (event.type == AppNotificationType.invitationReceived) {
        try {
          // Re-sync user state to get new invites
          final userState = Provider.of<UserState>(context, listen: false);
          // This will re-trigger a sync and update the user object
          await userState.refreshCurrentUserFromServer();

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
                orElse: () => threadsState.activeThread ?? Thread(id: event.threadId!, name: ThreadNameGenerator.generate(event.threadId!), createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
              );
              final user = thread.users.firstWhere(
                (u) => u.id == userId,
                orElse: () => ThreadUser(
                  id: userId, 
                  username: 'user_${userId.substring(0, 6)}',
                  name: 'User ${userId.substring(0, 6)}', 
                  joinedAt: DateTime.now(),
                ),
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
                    orElse: () => Thread(id: event.threadId!, name: ThreadNameGenerator.generate(event.threadId!), createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
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
            final userState = Provider.of<UserState>(context, listen: false);
            if (acceptedUserId != null && userState.currentUser?.id == acceptedUserId) {
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
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserState>(
      builder: (context, userState, child) {
        if (!userState.isLoading && userState.isAuthenticated && userState.currentUser != null && !_hasInitializedUser) {
          _hasInitializedUser = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncCurrentUser();
          });
        }
        
        if (userState.isLoading) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF333333)),
                        minHeight: 3,
                      ),
                    ),
                    
                    const Spacer(),
                  ],
                ),
              ),
            ),
          );
        }

        return const MainNavigationScreen();
      },
    );
  }
}


