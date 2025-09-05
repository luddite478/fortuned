import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/threads_state.dart';
import '../models/thread/thread.dart';

import '../utils/app_colors.dart';
import 'sequencer_screen_v2.dart';
import '../widgets/common_header_widget.dart';
import '../ffi/table_bindings.dart';
import '../ffi/playback_bindings.dart';
import '../ffi/sample_bank_bindings.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({Key? key}) : super(key: key);
  
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      await threadsState.loadThreads();
      
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
      body: SafeArea(
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
                                  final projects = threadsState.threads;
                                  
                                  if (projects.isEmpty) {
                                    return const SizedBox.shrink(); // Show nothing when no projects
                                  }
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
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
    );
  }


  Widget _buildMySequencerButton() {
    // Don't show buttons while loading
    if (_isLoading) {
      return const SizedBox.shrink();
    }
    
    return Consumer<ThreadsState>(
      builder: (context, threadsState, child) {
        final projects = threadsState.threads;
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
        
        // If projects exist, show CONTINUE + NEW buttons
        return Row(
          children: [
            // Continue button (70% width) - LEFT
            Expanded(
              flex: 7,
              child: Container(
                height: 100,
                margin: const EdgeInsets.only(right: 4),
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
                          // Project name - bottom left
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
                          
                          // Last edited time - bottom right
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
            ),
            
            // New button (30% width) - RIGHT
            Expanded(
              flex: 3,
              child: Container(
                height: 100,
                margin: const EdgeInsets.only(left: 4),
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Project icon
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.menuButtonBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.menuBorder, width: 1),
                  ),
                  child: Icon(
                    Icons.folder,
                    color: AppColors.menuText,
                    size: 16,
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
                        'Project ${project.id.substring(0, 10)}',
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        '${project.messageIds.length} messages',
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.menuLightText,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
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

  Future<void> _openProject(Thread project) async {
    await _loadProjectInSequencer(project);
  }

  Future<void> _loadProjectInSequencer(Thread project) async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loading project...'),
            backgroundColor: AppColors.menuText,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Navigate to V2 sequencer screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SequencerScreenV2(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.menuErrorColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
} 