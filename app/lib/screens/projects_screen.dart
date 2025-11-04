import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/threads_state.dart';
import '../state/audio_player_state.dart';
import '../state/user_state.dart';
import '../models/thread/thread.dart';
import '../services/threads_api.dart';

import '../utils/app_colors.dart';
import '../utils/thread_name_generator.dart';
import 'sequencer_screen.dart';
import '../widgets/simplified_header_widget.dart';
import '../ffi/table_bindings.dart';
import '../ffi/playback_bindings.dart';
import '../ffi/sample_bank_bindings.dart';
import '../widgets/buttons/action_button.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({Key? key}) : super(key: key);
  
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String? _error;
  bool _isOpeningProject = false;
  final Set<String> _deletingThreadIds = {}; // Prevent double deletion

  @override
  void initState() {
    super.initState();
    // Stop any playing audio when ProjectsScreen becomes visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final audioPlayer = context.read<AudioPlayerState>();
        audioPlayer.stop();
        _loadProjects();
      }
    });
  }

  Future<void> _loadProjects() async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      
      // Load threads (returns cached data immediately if available)
      await threadsState.loadThreads();
      
      // Refresh in background if already loaded (collaborative data)
      if (threadsState.hasLoaded) {
        // Refresh user and threads in background
        _refreshInBackground(userState, threadsState);
      } else {
        // First load - also fetch invites
        await _loadInvites(userState, threadsState);
      }
      
      setState(() {
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load projects: $e';
      });
    }
  }
  
  Future<void> _refreshInBackground(UserState userState, ThreadsState threadsState) async {
    try {
      // Refresh current user to fetch pending_invites_to_threads
      await userState.refreshCurrentUserFromServer();
      
      // Refresh threads in background
      await threadsState.refreshThreadsInBackground();
      
      // Also load invite thread summaries
      await _loadInvites(userState, threadsState);
    } catch (e) {
      debugPrint('❌ [PROJECTS] Background refresh error: $e');
      // Don't show error to user for background refresh
    }
  }
  
  Future<void> _loadInvites(UserState userState, ThreadsState threadsState) async {
    final invites = userState.currentUser?.pendingInvitesToThreads ?? const [];
    for (final threadId in invites) {
      await threadsState.ensureThreadSummary(threadId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.menuPageBackground,
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            // Simplified header with library icon
            const SimplifiedHeaderWidget(),
            
            Consumer<ThreadsState>(
              builder: (context, threadsState, _) {
                // Show loading only on first load (no cached data)
                if (threadsState.isLoading && !threadsState.hasLoaded) {
                  return Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.menuLightText),
                    ),
                  );
                }
                
                return Expanded(
                  child: Column(
                    children: [
              // Projects List
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Projects content
                    Expanded(
                      child: _error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, color: AppColors.menuLightText, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    _error!, 
                                    style: GoogleFonts.sourceSans3(
                                      color: AppColors.menuLightText,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: () {
                                      _loadProjects();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.menuButtonBackground,
                                    ),
                                    child: Text(
                                      'RETRY',
                                      style: GoogleFonts.sourceSans3(
                                        color: AppColors.menuText,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Consumer<ThreadsState>(
                                builder: (context, threadsState, child) {
                                  final projects = [...threadsState.threads]
                                    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                                  
                                  if (projects.isEmpty) {
                                    return const SizedBox.shrink(); // Show nothing when no projects
                                  }
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Invites section (if current user has pending invites)
                                      Consumer2<UserState, ThreadsState>(
                                        builder: (context, userState, threadsState, _) {
                                          final invites = userState.currentUser?.pendingInvitesToThreads ?? const [];
                                          if (invites.isEmpty) return const SizedBox.shrink();
                                          // Ensure missing invite thread summaries are loaded
                                          final existingIds = threadsState.threads.map((t) => t.id).toSet();
                                          final missing = invites.where((id) => !existingIds.contains(id)).toList();
                                          if (missing.isNotEmpty) {
                                            WidgetsBinding.instance.addPostFrameCallback((_) async {
                                              for (final id in missing) {
                                                try { await threadsState.ensureThreadSummary(id); } catch (_) {}
                                              }
                                              if (mounted) setState(() {});
                                            });
                                          }
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                                child: Text(
                                                  'INVITES',
                                                  style: GoogleFonts.sourceSans3(
                                                    color: AppColors.menuText,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 1.5,
                                                  ),
                                                ),
                                              ),
                                              ...invites.map((id) {
                                                final t = threadsState.threads.firstWhere(
                                                  (x) => x.id == id,
                                                  orElse: () => Thread(id: id, name: ThreadNameGenerator.generate(id), createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
                                                );
                                                return _buildInviteCard(t.users.isEmpty ? null : t, userState, id);
                                              }).toList(),
                                            ],
                                          );
                                        },
                                      ),
                                      // Recent header - only show when there are projects
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                        child: Text(
                                          'RECENT',
                                          style: GoogleFonts.sourceSans3(
                                            color: AppColors.menuText,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ),
                                      
                                      // Projects list
                                      Expanded(
                                        child: ListView.builder(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          itemCount: projects.length,
                                          itemBuilder: (context, index) {
                                            return _buildProjectCard(projects[index]);
                                          },
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),
                      // Show subtle refresh indicator when refreshing in background
                      if (threadsState.isRefreshing && threadsState.hasLoaded)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.menuEntryBackground.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.menuBorder),
                            ),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.menuOnlineIndicator,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
          if (_isOpeningProject)
            Positioned.fill(
              child: Container(
                color: AppColors.menuPageBackground.withOpacity(0.8),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.menuPrimaryButton),
                ),
              ),
            ),
          // Custom positioned floating action button
          Positioned(
            right: 30,
            bottom: 30,
            child: FloatingActionButton(
              onPressed: () async {
                // Stop any playing audio from playlist/renders
                context.read<AudioPlayerState>().stop();
                // Clear active thread context for new project
                context.read<ThreadsState>().setActiveThread(null);
                // Initialize native subsystems (idempotent: init performs cleanup)
                try {
                  TableBindings().tableInit();
                  PlaybackBindings().playbackInit();
                  SampleBankBindings().sampleBankInit();
                } catch (e) {
                  debugPrint('❌ Failed to init native subsystems: $e');
                }
                // Navigate to sequencer using PatternScreen which handles version routing
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PatternScreen(),
                  ),
                );
              },
              backgroundColor: Colors.white, // White background
              foregroundColor: const Color(0xFF424242), // Dark gray cross
              elevation: 4, // Add shadow for Google-style appearance
              child: const Icon(Icons.add, size: 50),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildProjectCard(Thread project) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        border: Border(
          left: BorderSide(
            color: AppColors.menuLightText.withOpacity(0.3),
            width: 2,
          ),
          bottom: BorderSide(
            color: AppColors.menuBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openProject(project),
          onLongPress: () => _showDeleteDialog(project),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Project info
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Emojis
                      ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      1, 0,
                        ]),
                      child: Text(
                        _getProjectName(project),
                        style: GoogleFonts.sourceSans3(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.0,
                        ),
                      ),
                      ),
                      const SizedBox(width: 8),
                      // Checkpoint counter to the right of emojis
                      Text(
                        '${project.messageIds.length}',
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuLightText,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      _buildParticipantsChips(project),
                    ],
                  ),
                ),
                
                // Timestamp
                Text(
                  _formatProjectTimestamp(project.updatedAt),
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.menuLightText,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Arrow indicator
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.menuLightText,
                  size: 12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInviteCard(Thread? thread, UserState userState, String threadId) {
    final currentUsername = userState.currentUser?.username ?? '';
    final needsUsername = currentUsername.isEmpty;

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final TextEditingController usernameController = TextEditingController();
        String? usernameError;
        bool isUpdatingUsername = false;

        String? validateUsername(String username) {
          if (username.isEmpty) return 'Username required';
          if (username.length < 3) return 'Min 3 characters';
          final validPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
          if (!validPattern.hasMatch(username)) return 'Only letters, numbers, _ and -';
          return null;
        }

        Future<void> handleAccept() async {
          // If username is needed, validate first
          if (needsUsername) {
            final username = usernameController.text.trim();
            final error = validateUsername(username);
            if (error != null) {
              setLocalState(() => usernameError = error);
              return;
            }

            setLocalState(() => isUpdatingUsername = true);
            try {
              final success = await userState.updateUsername(username);
              if (!success) {
                setLocalState(() {
                  usernameError = 'Failed to create username';
                  isUpdatingUsername = false;
                });
                return;
              }
            } catch (e) {
              setLocalState(() {
                usernameError = e.toString().replaceFirst('Exception: ', '');
                isUpdatingUsername = false;
              });
              return;
            }
          }

          // Accept invite
          await ThreadsApi.acceptInvite(threadId: threadId, userId: userState.currentUser!.id);
          final userSvc = context.read<UserState>();
          final threadsState = context.read<ThreadsState>();
          await userSvc.refreshCurrentUserFromServer();
          await threadsState.loadThreads();
          final invites = userSvc.currentUser?.pendingInvitesToThreads ?? const [];
          for (final id in invites) {
            await threadsState.ensureThreadSummary(id);
          }
          if (mounted) setState(() {});
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: AppColors.menuEntryBackground,
            border: Border(
              left: BorderSide(
                color: AppColors.menuLightText.withOpacity(0.3),
                width: 2,
              ),
              bottom: BorderSide(
                color: AppColors.menuBorder,
                width: 0.5,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Row 1: Project info
                  Row(
                    children: [
                      // Emojis
                      ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      1, 0,
                        ]),
                        child: Text(
                          thread?.name ?? '',
                          style: GoogleFonts.sourceSans3(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Checkpoint counter
                      Text(
                        '${thread?.messageIds.length ?? 0}',
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuLightText,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      // Participant chips
                      if (thread != null)
                        _buildParticipantsChips(thread)
                      else
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.menuBorder.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'invite',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.menuLightText,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Row 2 (conditional): Username creation field
                  if (needsUsername) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.menuPrimaryButton.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.menuPrimaryButton,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person, color: AppColors.menuPrimaryButton, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: usernameController,
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.menuText,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Create username to accept',
                                hintStyle: GoogleFonts.sourceSans3(
                                  color: AppColors.menuLightText,
                                  fontSize: 14,
                                ),
                                errorText: usernameError,
                                errorStyle: GoogleFonts.sourceSans3(
                                  color: AppColors.menuErrorColor,
                                  fontSize: 11,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (value) {
                                setLocalState(() {
                                  usernameError = null;
                                });
                              },
                            ),
                          ),
                          if (isUpdatingUsername)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.menuPrimaryButton,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Row 3: Action buttons
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ActionButton(
                        label: 'ACCEPT',
                        background: AppColors.menuPrimaryButton,
                        border: AppColors.menuPrimaryButton,
                        textColor: AppColors.menuPrimaryButtonText,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        fontSize: 12,
                        onTap: () => handleAccept(),
                      ),
                      const SizedBox(width: 8),
                      ActionButton(
                        label: 'DENY',
                        background: AppColors.menuSecondaryButton,
                        border: AppColors.menuSecondaryButtonBorder,
                        textColor: AppColors.menuSecondaryButtonText,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        fontSize: 12,
                        onTap: () async {
                          await ThreadsApi.declineInvite(threadId: threadId, userId: userState.currentUser!.id);
                          final userSvc = context.read<UserState>();
                          final threadsState = context.read<ThreadsState>();
                          await userSvc.refreshCurrentUserFromServer();
                          await threadsState.loadThreads();
                          final invites = userSvc.currentUser?.pendingInvitesToThreads ?? const [];
                          for (final id in invites) {
                            await threadsState.ensureThreadSummary(id);
                          }
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildParticipantsChips(Thread project) {
    final userState = context.read<UserState>();
    final me = userState.currentUser?.id;
    final others = project.users.where((u) => u.id != me).map((u) => u.name).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    final List<Widget> chips = [];
    const maxVisible = 2;
    for (final name in others.take(maxVisible)) {
      chips.add(Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.menuBorder.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          name,
          style: GoogleFonts.sourceSans3(color: AppColors.menuLightText, fontSize: 12, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }
    final remaining = others.length - maxVisible;
    if (remaining > 0) {
      chips.add(Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.menuBorder.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '+$remaining',
          style: GoogleFonts.sourceSans3(color: AppColors.menuLightText, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ));
    }
    return SizedBox(
      width: 140,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(children: chips),
      ),
    );
  }

  String _formatProjectTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${difference.inDays}d ago';
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Now';
    }
  }

  // Get project name
  String _getProjectName(Thread project) {
    return project.name;
  }

  Future<void> _openProject(Thread project) async {
    await _loadProjectInSequencer(project);
  }

  Future<void> _loadProjectInSequencer(Thread project) async {
    try {
      if (mounted) {
        setState(() {
          _isOpeningProject = true;
        });
      }

      // Set active thread context so Sequencer V2 doesn't create a new unpublished thread
      final threadsState = context.read<ThreadsState>();
      threadsState.setActiveThread(project);

      // Stop any playing audio from playlist/renders
      context.read<AudioPlayerState>().stop();
      
      // Use unified loader (handles initialization, caching, and import)
      // This will:
      // 1. Check and initialize native systems if needed (one-time)
      // 2. Check cache first, fetch from API if needed
      // 3. Import snapshot with proper resets (surgical, not full reinit)
      // 4. Clear undo/redo history for fresh start
      debugPrint('📂 [PROJECTS] Loading project ${project.id} via unified loader');
      final success = await threadsState.loadProjectIntoSequencer(project.id);
      
      if (!success) {
        debugPrint('⚠️ [PROJECTS] Project has no snapshot - will start empty');
      }

      // Navigate to sequencer using PatternScreen
      // Pass null snapshot since import already loaded everything
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const PatternScreen(initialSnapshot: null),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to open project: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }
    }
  }

  void _showDeleteDialog(Thread project) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.menuPageBackground,
          title: Text(
            'Delete Project',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to delete this project? This will delete it for all participants.',
            style: GoogleFonts.sourceSans3(
              color: AppColors.menuLightText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.sourceSans3(
                  color: AppColors.menuLightText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteProject(project);
              },
              child: Text(
                'Delete',
                style: GoogleFonts.sourceSans3(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteProject(Thread project) async {
    // Prevent double deletion
    if (_deletingThreadIds.contains(project.id)) {
      return;
    }
    
    final threadsState = context.read<ThreadsState>();
    final isOfflineThread = project.isLocal == true;
    Thread? removedThread;
    
    try {
      _deletingThreadIds.add(project.id);
      
      // Optimistically remove the thread immediately from the UI
      removedThread = threadsState.removeThreadOptimistically(project.id);
      
      // Show loading indicator
      if (mounted) {
        setState(() {
          _isOpeningProject = true;
        });
      }

      // Skip API call for offline threads (they don't exist on server)
      if (!isOfflineThread) {
        await ThreadsApi.deleteThread(project.id);
      }

      // Refresh the projects list to ensure consistency
      await threadsState.loadThreads();

      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to delete project: $e');
      
      // If optimistic removal happened, restore the thread by refreshing
      if (removedThread != null) {
        await threadsState.loadThreads();
      }
      
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }
    } finally {
      _deletingThreadIds.remove(project.id);
    }
  }
} 