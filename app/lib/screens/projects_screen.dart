import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/threads_state.dart';
import '../models/thread/thread.dart';
import '../services/threads_api.dart';

import '../utils/app_colors.dart';
import 'sequencer_screen_v2.dart';
import '../widgets/common_header_widget.dart';
import '../ffi/table_bindings.dart';
import '../ffi/playback_bindings.dart';
import '../ffi/sample_bank_bindings.dart';
import '../services/auth_service.dart';
import '../widgets/buttons/action_button.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({Key? key}) : super(key: key);
  
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _isLoading = true;
  String? _error;
  bool _isOpeningProject = false;

  @override
  void initState() {
    super.initState();
    // Defer to next frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadProjects();
      }
    });
  }

  Future<void> _loadProjects() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      
      // Refresh current user to fetch pending_invites_to_threads
      await Provider.of<AuthService>(context, listen: false).refreshCurrentUserFromServer();
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      await threadsState.loadThreads();
      // Also load invite thread summaries not in membership list if any
      final invites = Provider.of<AuthService>(context, listen: false).currentUser?.pendingInvitesToThreads ?? const [];
      for (final threadId in invites) {
        await threadsState.ensureThreadSummary(threadId);
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load projects: $e';
        _isLoading = false;
      });
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
            // User indicator at the top
            const CommonHeaderWidget(),
            
            // Show only loading indicator while loading
            if (_isLoading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.menuLightText),
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                child: _buildMySequencerButton(),
              ),
              
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
                                      Consumer2<AuthService, ThreadsState>(
                                        builder: (context, auth, threadsState, _) {
                                          final invites = auth.currentUser?.pendingInvitesToThreads ?? const [];
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
                                                  orElse: () => Thread(id: id, createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
                                                );
                                                return _buildInviteCard(t.users.isEmpty ? null : t, auth, id);
                                              }).toList(),
                                            ],
                                          );
                                        },
                                      ),
                                      // Recent header - only show when there are projects
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
            ], 
          ], // Close the main children array
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
        ],
      ),
    );
  }


  Widget _buildMySequencerButton() {
    // Don't show buttons while loading
    if (_isLoading) {
      return const SizedBox.shrink();
    }
    
    return Consumer<ThreadsState>(
      builder: (context, threadsState, child) {
        final projects = [...threadsState.threads]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final mostRecentProject = projects.isNotEmpty ? projects.first : null;
        
        // If no projects, show full-width NEW button
        if (mostRecentProject == null) {
          return Container(
            width: double.infinity,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.menuPrimaryButton, // Dark primary button
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.menuPrimaryButton,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 4,
                  offset: const Offset(2, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
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
                  // Navigate to V2 sequencer implementation
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SequencerScreenV2(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Stack(
                    children: [
                                             // Centered NEW text
                       Center(
                         child: Text(
                           'NEW',
                           style: GoogleFonts.sourceSans3(
                             color: AppColors.menuPrimaryButtonText, // White text on dark button
                             fontSize: 16,
                             fontWeight: FontWeight.w600,
                             letterSpacing: 1.2,
                           ),
                         ),
                       ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        
        // If projects exist, show CONTINUE + NEW buttons (vertical stack)
        return Column(
          children: [
            // Continue button - TOP (full width, slightly smaller height)
            Container(
              width: double.infinity,
              height: 84,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                  color: AppColors.menuPrimaryButton, // Dark primary button
                  borderRadius: BorderRadius.circular(12), // More rounded corners
                  border: Border.all(
                    color: AppColors.menuPrimaryButton,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    // Load project into sequencer and navigate
                    await _loadProjectInSequencer(mostRecentProject);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Stack(
                      children: [
                        // Centered CONTINUE text
                        Center(
                          child: Text(
                            'CONTINUE',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.menuPrimaryButtonText, // White text on dark button
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        // Bottom row with project info
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: Text(
                            'Project ${mostRecentProject.id.substring(0, 8)}',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.menuPrimaryButtonText, // White text on dark button
                              fontSize: 9,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Text(
                            _formatProjectTimestamp(mostRecentProject.updatedAt),
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.menuPrimaryButtonText.withOpacity(0.8), // Dimmed white text
                              fontSize: 9,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // New button - BOTTOM (full width, slightly smaller height)
            Container(
              width: double.infinity,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.menuSecondaryButton, // White secondary button
                borderRadius: BorderRadius.circular(12), // More rounded corners
                border: Border.all(
                  color: AppColors.menuSecondaryButtonBorder, // Dark border
                  width: 2,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
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
                    // Navigate to V2 sequencer implementation
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SequencerScreenV2(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Text(
                        'NEW',
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuSecondaryButtonText, // Dark text on light button
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProjectCard(Thread project) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        border: Border(
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
                // Small black square instead of folder icon
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Project info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatDateYmd(project.createdAt),
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${project.messageIds.length} checkpoints',
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.menuLightText,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          _buildParticipantsChips(project),
                        ],
                      ),
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

  Widget _buildInviteCard(Thread? thread, AuthService auth, String threadId) {
    // Same visual style as project list tile; only right side differs
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        border: Border(
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
          child: Row(
            children: [
              // Leading square (same as project row)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // Middle info (same structure as project row)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      thread != null ? _formatDateYmd(thread.createdAt) : _formatDateYmd(DateTime.now()),
                      style: GoogleFonts.sourceSans3(
                        color: AppColors.menuText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${thread?.messageIds.length ?? 0} checkpoints',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.menuLightText,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Participant chips (or invited username)
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
                  ],
                ),
              ),
              // Right actions instead of timestamp (match right spacing of Recent: timer + chevron ~ 56px)
              const SizedBox(width: 8),
              ActionButton(
                label: 'ACCEPT',
                background: AppColors.menuPrimaryButton,
                border: AppColors.menuPrimaryButton,
                textColor: AppColors.menuPrimaryButtonText,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                fontSize: 12,
                onTap: () async {
                  await ThreadsApi.acceptInvite(threadId: threadId, userId: auth.currentUser!.id);
                  final authSvc = context.read<AuthService>();
                  final threadsState = context.read<ThreadsState>();
                  await authSvc.refreshCurrentUserFromServer();
                  await threadsState.loadThreads();
                  final invites = authSvc.currentUser?.pendingInvitesToThreads ?? const [];
                  for (final id in invites) {
                    await threadsState.ensureThreadSummary(id);
                  }
                  if (mounted) setState(() {});
                },
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
                  await ThreadsApi.declineInvite(threadId: threadId, userId: auth.currentUser!.id);
                  final authSvc = context.read<AuthService>();
                  final threadsState = context.read<ThreadsState>();
                  await authSvc.refreshCurrentUserFromServer();
                  await threadsState.loadThreads();
                  final invites = authSvc.currentUser?.pendingInvitesToThreads ?? const [];
                  for (final id in invites) {
                    await threadsState.ensureThreadSummary(id);
                  }
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantsChips(Thread project) {
    final auth = context.read<AuthService>();
    final me = auth.currentUser?.id;
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

  Widget _buildParticipantsLine(Thread thread) {
    final auth = context.read<AuthService>();
    final me = auth.currentUser?.id;
    final names = thread.users.where((u) => u.id != me).map((u) => u.name).toList();
    final text = names.join(', ');
    return Text(
      text,
      style: GoogleFonts.sourceSans3(color: AppColors.menuLightText, fontSize: 11),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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

  String _formatDateYmd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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

      // Load latest message only for CONTINUE
      final latest = await ThreadsApi.getLatestMessage(project.id, includeSnapshot: true);
      Map<String, dynamic>? initialSnapshot = latest?.snapshot;

      // Navigate to V2 sequencer screen
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SequencerScreenV2(initialSnapshot: initialSnapshot),
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
    try {
      // Show loading indicator
      if (mounted) {
        setState(() {
          _isOpeningProject = true;
        });
      }

      // Delete the thread via API
      await ThreadsApi.deleteThread(project.id);

      // Refresh the projects list
      final threadsState = context.read<ThreadsState>();
      await threadsState.loadThreads();

      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Project deleted successfully',
              style: GoogleFonts.sourceSans3(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to delete project: $e');
      
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to delete project: $e',
              style: GoogleFonts.sourceSans3(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
} 