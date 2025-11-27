import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/pattern_preview_widget.dart';
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
  String _sortBy = 'modified'; // 'modified' or 'created'
  bool _sortAscending = false; // false = descending (newest first)
  
  // Cache for project snapshots to avoid re-fetching on every rebuild
  final Map<String, Future<Map<String, dynamic>?>> _snapshotFutures = {};

  // ============================================================================
  // LAYOUT CONTROL VARIABLES - CENTRALIZED CONFIGURATION
  // ============================================================================
  // All adjustable layout parameters in one place. Change these to customize appearance.
  // Using flex ratios and relative sizing (following flutter_overflow_prevention_guide.md)
  
  // ----------------------------------------------------------------------------
  // TILE HEIGHT CONTROL
  // ----------------------------------------------------------------------------
  // Controls the height of each project tile as a percentage of screen height
  // 
  // Recommended values:
  // - 8-10%:  Compact view (more projects visible, less detail)
  // - 10-12%: Balanced view (good mix of visibility and detail)
  // - 12-15%: Comfortable view (fewer projects, more detail visible)
  // - 15%+:   Spacious view (best for tablets/large screens)
  //
  // Current: 8.0% = Compact view showing more projects
  static const double _tileHeightPercent = 9.0;
  
  // Tile horizontal spacing (% of screen width)
  static const double _tileHorizontalPaddingLeftPercent = 2.0;
  static const double _tileHorizontalPaddingRightPercent = 2.0;
  
  // ----------------------------------------------------------------------------
  // COLUMN FLEX RATIOS - CENTRALIZED (Total must equal 100)
  // ----------------------------------------------------------------------------
  // Controls width proportions of all 5 columns using Expanded flex ratios.
  // This is the RECOMMENDED approach (no overflow possible).
  //
  // Adjust these to change column widths:
  static const int _patternColumnFlex = 38;      // Pattern preview (32%)
  static const int _sampleBankColumnFlex = 11;   // Sample bank grid (14%)
  static const int _countersColumnFlex = 15;     // LEN/HST counters (12%)
  static const int _createdColumnFlex = 17;      // Created date (21%)
  static const int _modifiedColumnFlex = 17;     // Modified date (21%)
  // Total: 100 (exact, no floating-point errors, overflow-safe
  
  // ----------------------------------------------------------------------------
  // PATTERN PREVIEW INNER PADDING (as % of tile height for proportional sizing)
  // ----------------------------------------------------------------------------
  // Controls inner padding between the pattern widget border and the actual cells.
  // This affects how much the cells spread within the available space.
  // SMALLER padding = cells spread MORE (more rectangular when given wide space)
  // LARGER padding = cells spread LESS (more constrained)
  // Using percentages of tile height for responsive scaling
  //
  // Recommended values:
  // - 0-1%:   Minimal padding (maximum cell spreading)
  // - 1-3%:   Compact padding (cells fill most of space)
  // - 3-5%:   Comfortable padding (balanced spacing)
  // - 5%+:    Spacious padding (more border space)
  //
  // Current: Minimal padding for maximum cell spreading
  static const double _patternPreviewInnerPaddingLeftPercent = 2;    // 0.3% of tile height
  static const double _patternPreviewInnerPaddingTopPercent = 0.3;     // 0.3% of tile height
  static const double _patternPreviewInnerPaddingRightPercent = 1;   // 0.6% of tile height
  static const double _patternPreviewInnerPaddingBottomPercent = 5;  // 0.3% of tile height
  
  // ----------------------------------------------------------------------------
  // SAMPLE BANK GRID SIZE CONTROL
  // ----------------------------------------------------------------------------
  // Controls the dimensions of the sample bank grid
  // Total samples shown = columns × rows
  //
  // Recommended configurations:
  // - 5×4 = 20 samples (current, good balance)
  // - 4×4 = 16 samples (square grid)
  // - 6×4 = 24 samples (more samples)
  // - 5×3 = 15 samples (shorter grid)
  static const int _sampleBankColumns = 5;  // Number of columns in sample grid
  static const int _sampleBankRows = 4;     // Number of rows in sample grid
  
  // ----------------------------------------------------------------------------
  // SAMPLE BANK SIZE CONTROL (Independent Width & Height Control)
  // ----------------------------------------------------------------------------
  // Controls how much space the sample grid occupies inside its column
  // Cells automatically fill the specified dimensions using Expanded widgets
  //
  // WIDTH CONTROL (% of column width):
  // - 50-70%: Narrow grid
  // - 70-85%: Comfortable width (recommended)
  // - 85-100%: Wide grid (maximum visibility)
  static const double _sampleBankWidthPercent = 100.0;  // % of column width
  
  // HEIGHT CONTROL (% of column height):
  // - 40-55%: Compact height
  // - 55-70%: Comfortable height (recommended)
  // - 70-85%: Tall grid (maximum visibility)
  static const double _sampleBankHeightPercent = 55.0;  // % of column height
  
  // ----------------------------------------------------------------------------
  // SAMPLE BANK INNER PADDING (as % of tile height for proportional sizing)
  // ----------------------------------------------------------------------------
  // Controls inner padding between the sample grid border and the actual cells.
  // Cells now fill available space using Expanded widgets (responsive)
  // SMALLER padding = more room for cells
  // LARGER padding = more border space
  static const double _sampleBankInnerPaddingPercent = 4.0;  // All sides (% of tile height)
  
  // ----------------------------------------------------------------------------
  // ELEMENT PADDING CONTROL (Responsive, as % of tile dimensions)
  // ----------------------------------------------------------------------------
  // Each main element gets its own box with controlled padding
  // All values are percentages for responsive scaling
  
  // Pattern preview element padding (% of tile height)
  static const double _patternElementPaddingTopPercent = 3.0;       // 3% top
  static const double _patternElementPaddingBottomPercent = 3.0;    // 3% bottom
  static const double _patternElementPaddingLeftPercent = 3.0;      // 2% left
  static const double _patternElementPaddingRightPercent = 3.0;     // 2% right
  
  // Sample bank element padding (% of tile height)
  static const double _sampleElementPaddingTopPercent = 3.0;        // 3% top
  static const double _sampleElementPaddingBottomPercent = 3.0;     // 3% bottom
  static const double _sampleElementPaddingLeftPercent = 2.0;       // 2% left
  static const double _sampleElementPaddingRightPercent = 2.0;      // 2% right
  
  // Counters element padding (% of tile height)
  static const double _countersElementPaddingTopPercent = 3.0;      // 3% top
  static const double _countersElementPaddingBottomPercent = 3.0;   // 3% bottom
  static const double _countersElementPaddingLeftPercent = 8.0;     // 3% left
  static const double _countersElementPaddingRightPercent = 8.0;    // 3% right
  
  // Date columns element padding (% of tile height)
  static const double _dateElementPaddingTopPercent = 3.0;          // 3% top
  static const double _dateElementPaddingBottomPercent = 3.0;       // 3% bottom
  static const double _dateElementPaddingLeftPercent = 2.0;         // 2% left
  static const double _dateElementPaddingRightPercent = 2.0;        // 2% right
  
  // ----------------------------------------------------------------------------
  // COUNTERS LAYOUT (Internal spacing within counter element)
  // ----------------------------------------------------------------------------
  // Spacing between label and number (as % of column width)
  static const double _counterLabelGapPercent = 3.0;    // 3% of column width
  // Spacing between LEN and HST rows (as % of column height)
  static const double _counterRowGapPercent = 0.5;      // 0.5% of column height
  
  // ----------------------------------------------------------------------------
  // DEBUG COLORS (set to null to disable)
  // ----------------------------------------------------------------------------
  static const Color? _patternPreviewDebugColor = Color.fromARGB(255, 194, 194, 194); // Light red
  static const Color? _sampleBankDebugColor = Color.fromARGB(255, 194, 194, 194); // Light green
  static const Color? _countersDebugColor = Color.fromARGB(255, 194, 194, 194);// Light blue
  static const Color? _createdColumnDebugColor = Color.fromARGB(255, 194, 194, 194);/// Light yellow
  static const Color? _modifiedColumnDebugColor = Color.fromARGB(255, 194, 194, 194); // Light purple
  
  // ----------------------------------------------------------------------------
  // BACKGROUND PATTERN CONTROLS (Checkerboard Pattern)
  // ----------------------------------------------------------------------------
  // Controls the appearance of the background checkerboard pattern
  
  // Base background color (shows between rounded squares when cornerRadius > 0)
  // Set this to match your pattern colors for seamless appearance with rounded corners
  static const Color _bgBaseColor = Color.fromARGB(255, 240, 240, 240);
  
  // Pattern colors (alternating squares)
  static const Color _bgPatternColor1 = Color.fromARGB(255, 239, 238, 238);  // Light gray
  static const Color _bgPatternColor2 = Color.fromARGB(255, 238, 238, 238);  // Light beige
  
  // Square size (in pixels)
  static const double _bgPatternSquareSize = 10.0;
  
  // Corner roundness (0.0 = sharp corners, higher = more rounded)
  // Recommended: 0.0 for squares, 2-5 for slightly rounded, 10+ for very rounded
  static const double _bgPatternCornerRadius = 10;
  
  // Gray overlay (sits on top of pattern to adjust overall grayness/brightness)
  // Set opacity to 0.0 for no overlay, increase for more gray (0.0 - 1.0)
  // Recommended: 0.0 = no overlay, 0.1-0.3 = subtle, 0.4-0.6 = moderate, 0.7+ = heavy
  static const double _bgOverlayOpacity = 0.1;
  // Overlay color (white = lighten, black = darken, gray = desaturate)
  static const Color _bgOverlayColor = Color.fromARGB(255, 42, 42, 42);

  @override
  void initState() {
    super.initState();
    // Configure status bar to be transparent (shows background pattern through)
    // This affects both iOS and Android
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // Transparent status bar background
        statusBarIconBrightness: Brightness.dark, // Dark icons (for light background)
        statusBarBrightness: Brightness.light, // iOS status bar brightness
      ),
    );
    
    // Stop any playing audio when ProjectsScreen becomes visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final audioPlayer = context.read<AudioPlayerState>();
        audioPlayer.stop();
        _loadProjects();
      }
    });
  }

  @override
  void dispose() {
    // Restore default system UI styling when leaving this screen
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    super.dispose();
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
      backgroundColor: _bgBaseColor, // Base color shows between rounded squares
      body: Stack(
        children: [
          // Background pattern layer (behind everything)
          Positioned.fill(
            child: _buildBackgroundPattern(),
          ),
          
          // Gray overlay layer (for adjusting overall grayness/brightness)
          if (_bgOverlayOpacity > 0.0)
            Positioned.fill(
              child: Container(
                color: _bgOverlayColor.withOpacity(_bgOverlayOpacity),
              ),
            ),
          
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
                  child: Stack(
                    children: [
                      Column(
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
                                              final projects = [...threadsState.threads];
                                              
                                              // Add mock project for testing layer boundaries
                                              _addMockProject(projects);
                                              
                                              // Sort based on current sort settings
                                              projects.sort((a, b) {
                                                int comparison;
                                                if (_sortBy == 'created') {
                                                  comparison = a.createdAt.compareTo(b.createdAt);
                                                } else {
                                                  comparison = a.updatedAt.compareTo(b.updatedAt);
                                                }
                                                return _sortAscending ? comparison : -comparison;
                                              });
                                              
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
                                  // Header with sorting controls - aligned with tile columns
                                                  LayoutBuilder(
                                                    builder: (context, constraints) {
                                                      final screenWidth = constraints.maxWidth;
                                                      
                                      // Use same padding as tiles for perfect alignment
                                                      final paddingLeft = screenWidth * (_tileHorizontalPaddingLeftPercent / 100);
                                                      final paddingRight = screenWidth * (_tileHorizontalPaddingRightPercent / 100);
                                                      
                                                      return Padding(
                                                        padding: EdgeInsets.only(left: paddingLeft, right: paddingRight, bottom: 8),
                                                        child: Row(
                                                          crossAxisAlignment: CrossAxisAlignment.center,
                                                          children: [
                                            // Column 1: Patterns header
                                            Expanded(flex: _patternColumnFlex, child: _buildHeaderPatternsColumn()),
                                            // Column 2: Sample bank header
                                            Expanded(flex: _sampleBankColumnFlex, child: _buildHeaderSampleBankColumn()),
                                            // Column 3: Counters header
                                            Expanded(flex: _countersColumnFlex, child: _buildHeaderCountersColumn()),
                                            // Column 4: Created header
                                            Expanded(flex: _createdColumnFlex, child: _buildHeaderCreatedColumn()),
                                            // Column 5: Modified header
                                            Expanded(flex: _modifiedColumnFlex, child: _buildHeaderModifiedColumn()),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  
                                                  // Projects list
                                                  Expanded(
                                                    child: ListView.builder(
                                                      padding: EdgeInsets.zero,
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

  Widget _buildBackgroundPattern() {
    return CustomPaint(
      painter: _CheckerboardPatternPainter(
        color1: _bgPatternColor1,
        color2: _bgPatternColor2,
        squareSize: _bgPatternSquareSize,
        cornerRadius: _bgPatternCornerRadius,
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildProjectCard(Thread project) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final tileHeight = MediaQuery.of(context).size.height * (_tileHeightPercent / 100);
        
        // Calculate horizontal padding
        final paddingLeft = screenWidth * (_tileHorizontalPaddingLeftPercent / 100);
        final paddingRight = screenWidth * (_tileHorizontalPaddingRightPercent / 100);
        
        return Padding(
          padding: EdgeInsets.only(left: paddingLeft, right: paddingRight),
          child: Container(
          height: tileHeight,
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    // Column 1: Pattern preview
                    Expanded(
                      flex: _patternColumnFlex,
                      child: _buildPatternsColumn(project, tileHeight),
                    ),
                    
                    // Column 2: Sample bank grid
                    Expanded(
                      flex: _sampleBankColumnFlex,
                      child: _buildSampleBankColumn(project, tileHeight),
                    ),
                    
                    // Column 3: Counters - LEN & HST
                    Expanded(
                      flex: _countersColumnFlex,
                      child: _buildCountersColumn(project, tileHeight),
                    ),
                    
                    // Column 4: Created date
                    Expanded(
                      flex: _createdColumnFlex,
                      child: _buildDateColumn(
                      _formatDate(project.createdAt),
                        _createdColumnDebugColor,
                      tileHeight,
                    ),
                  ),
                  
                    // Column 5: Modified date
                    Expanded(
                      flex: _modifiedColumnFlex,
                      child: _buildDateColumn(
                      _formatDate(project.updatedAt),
                        _modifiedColumnDebugColor,
                      tileHeight,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }
  
  Widget _buildPatternsColumn(Thread project, double tileHeight) {
    // Calculate element padding as percentage of tile height
    final paddingTop = tileHeight * (_patternElementPaddingTopPercent / 100);
    final paddingBottom = tileHeight * (_patternElementPaddingBottomPercent / 100);
    final paddingLeft = tileHeight * (_patternElementPaddingLeftPercent / 100);
    final paddingRight = tileHeight * (_patternElementPaddingRightPercent / 100);
    
    // Calculate inner padding for pattern preview widget (space between border and cells)
    final innerPaddingLeft = tileHeight * (_patternPreviewInnerPaddingLeftPercent / 100);
    final innerPaddingTop = tileHeight * (_patternPreviewInnerPaddingTopPercent / 100);
    final innerPaddingRight = tileHeight * (_patternPreviewInnerPaddingRightPercent / 100);
    final innerPaddingBottom = tileHeight * (_patternPreviewInnerPaddingBottomPercent / 100);
    
    return Container(
      color: _patternPreviewDebugColor,
      child: Padding(
        padding: EdgeInsets.only(
          top: paddingTop,
          bottom: paddingBottom,
          left: paddingLeft,
          right: paddingRight,
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.menuBorder.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: ClipRect(
            child: PatternPreviewWidget(
              project: project,
              getProjectSnapshot: _getProjectSnapshot,
              getSampleBankColors: _getSampleBankColors,
              fadeOverlayColor: _patternPreviewDebugColor,
              innerPadding: EdgeInsets.only(
                left: innerPaddingLeft,
                top: innerPaddingTop,
                right: innerPaddingRight,
                bottom: innerPaddingBottom,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildDateColumn(String dateText, Color? debugColor, double tileHeight) {
    // Calculate element padding as percentage of tile height
    final paddingTop = tileHeight * (_dateElementPaddingTopPercent / 100);
    final paddingBottom = tileHeight * (_dateElementPaddingBottomPercent / 100);
    final paddingLeft = tileHeight * (_dateElementPaddingLeftPercent / 100);
    final paddingRight = tileHeight * (_dateElementPaddingRightPercent / 100);
    
    return Container(
      color: debugColor,
      child: Padding(
        padding: EdgeInsets.only(
          top: paddingTop,
          bottom: paddingBottom,
          left: paddingLeft,
          right: paddingRight,
            ),
            child: Center(
          child: Text(
            dateText,
            style: GoogleFonts.crimsonPro(
              color: AppColors.menuText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
  
  Widget _buildSampleBankColumn(Thread project, double tileHeight) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getProjectSnapshot(project.id),
      builder: (context, snapshot) {
        List<Color> sampleColors = [];
        
        if (snapshot.hasData && snapshot.data != null) {
          sampleColors = _getSampleBankColors(snapshot.data!);
        } else {
          // Default colors if no data
          sampleColors = _getSampleBankColors({});
        }
        
        // Use centralized grid size configuration
        final totalSamples = _sampleBankColumns * _sampleBankRows;
        final samplesToShow = sampleColors.take(totalSamples).toList();
        
        // Calculate element padding as percentage of tile height
        final paddingTop = tileHeight * (_sampleElementPaddingTopPercent / 100);
        final paddingBottom = tileHeight * (_sampleElementPaddingBottomPercent / 100);
        final paddingLeft = tileHeight * (_sampleElementPaddingLeftPercent / 100);
        final paddingRight = tileHeight * (_sampleElementPaddingRightPercent / 100);
        
        // Calculate inner padding for sample grid (space between border and cells)
        final innerPadding = tileHeight * (_sampleBankInnerPaddingPercent / 100);
        
        // Use centralized grid size
        final cols = _sampleBankColumns;
        final rows = _sampleBankRows;
        
        // Cell spacing - using fixed values from PatternPreviewWidget for consistency
        final rowGap = PatternPreviewWidget.patternCellMargin * 4.0;
        final colGap = PatternPreviewWidget.patternCellMargin * 4.0;
        
        return Container(
          color: _sampleBankDebugColor,
          child: Padding(
            padding: EdgeInsets.only(
              top: paddingTop,
              bottom: paddingBottom,
              left: paddingLeft,
              right: paddingRight,
            ),
            child: Center(
              child: FractionallySizedBox(
                widthFactor: _sampleBankWidthPercent / 100,   // Width control
                heightFactor: _sampleBankHeightPercent / 100, // Height control
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.menuBorder.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(innerPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int row = 0; row < rows; row++) ...[
                          if (row > 0) SizedBox(height: rowGap), // Gap between rows
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (int col = 0; col < cols; col++) ...[
                                  if (col > 0) SizedBox(width: colGap), // Gap between columns
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: () {
                                          final index = row * cols + col;
                                          return index < samplesToShow.length
                                              ? samplesToShow[index]
                                              : AppColors.sequencerCellEmpty;
                                        }(),
                                        borderRadius: BorderRadius.circular(0),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
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
  
  Widget _buildCountersColumn(Thread project, double tileHeight) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getProjectSnapshot(project.id),
      builder: (context, snapshot) {
        int sectionsCount = 0;
        
        if (snapshot.hasData && snapshot.data != null) {
          try {
            final source = snapshot.data!['source'] as Map<String, dynamic>?;
            final table = source?['table'] as Map<String, dynamic>?;
            final sections = table?['sections'] as List<dynamic>?;
            sectionsCount = sections?.length ?? 0;
          } catch (e) {
            sectionsCount = 0;
          }
        }
        
        final historyCount = project.messageIds.length;
        
        // Calculate element padding as percentage of tile height
        final paddingTop = tileHeight * (_countersElementPaddingTopPercent / 100);
        final paddingBottom = tileHeight * (_countersElementPaddingBottomPercent / 100);
        final paddingLeft = tileHeight * (_countersElementPaddingLeftPercent / 100);
        final paddingRight = tileHeight * (_countersElementPaddingRightPercent / 100);
        
        return Container(
          color: _countersDebugColor,
          child: Padding(
      padding: EdgeInsets.only(
        top: paddingTop,
        bottom: paddingBottom,
        left: paddingLeft,
        right: paddingRight,
      ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth = constraints.maxWidth;
                final columnHeight = constraints.maxHeight;
                
                // Calculate internal spacing as percentages
                final labelGap = columnWidth * (_counterLabelGapPercent / 100);
                final rowGap = columnHeight * (_counterRowGapPercent / 100);
                
                return Center(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.menuBorder.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: labelGap, vertical: rowGap * 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // LEN counter - using Expanded for overflow-safe layout
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Label with intrinsic width
                            Text(
                              'LEN:',
                              style: GoogleFonts.crimsonPro(
                                color: AppColors.menuLightText,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(width: labelGap),
                            // Number takes remaining space with FittedBox for overflow prevention
                            // FittedBox with scaleDown only scales if needed - otherwise displays at full size
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '$sectionsCount',
                                  style: GoogleFonts.crimsonPro(
                                    color: AppColors.menuText,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: rowGap),
                        // HST counter - using Expanded for overflow-safe layout
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Label with intrinsic width
                            Text(
                              'HST:',
                              style: GoogleFonts.crimsonPro(
                                color: AppColors.menuLightText,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(width: labelGap),
                            // Number takes remaining space with FittedBox for overflow prevention
                            // FittedBox with scaleDown only scales if needed - otherwise displays at full size
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '$historyCount',
                                  style: GoogleFonts.crimsonPro(
                                    color: AppColors.menuText,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
  
  // Mock project for testing layer boundaries
  void _addMockProject(List<Thread> projects) {
    const mockId = 'mock-layer-test-project';
    
    // Only add if not already present
    if (projects.any((p) => p.id == mockId)) return;
    
    // Create mock project
    final mockProject = Thread(
      id: mockId,
      name: '🧪 MOCK: Layer Test (2,6,5,7,8,4,2,1)',
      createdAt: DateTime.now().subtract(const Duration(days: 100)),
      updatedAt: DateTime.now(),
      users: const [],
      messageIds: const ['msg1', 'msg2', 'msg3', 'msg4', 'msg5', 'msg6', 'msg7', 'msg7', 'msg7', 'msg7', 'msg7', 'msg7', 'msg7', 'msg7', 'msg7'], // 7 messages for HST counter
      invites: const [],
      isLocal: true,
    );
    
    projects.insert(0, mockProject); // Add at top
    
    // Create mock snapshot with 8 layers: [2, 6, 5, 7, 8, 4, 2, 1] = 35 columns
    final mockSnapshot = {
      'source': {
        'table': {
          'sections': [
            {'num_steps': 8, 'start_step': 0},
            {'num_steps': 8, 'start_step': 8},
            {'num_steps': 8, 'start_step': 16}
          ],
          'layers': [
            [
              {'len': 2},  // Layer 1: 2 columns
              {'len': 6},  // Layer 2: 6 columns
              {'len': 5},  // Layer 3: 5 columns
              {'len': 7},  // Layer 4: 7 columns
              {'len': 8},  // Layer 5: 8 columns
              {'len': 4},  // Layer 6: 4 columns
              {'len': 2},  // Layer 7: 2 columns
              {'len': 1},  // Layer 8: 1 column
            ]
          ],
          'table_cells': List.generate(8, (row) {
            // Create 8 rows, each with some colored cells
            return List.generate(35, (col) {
              // Add some cells with colors (sample slots)
              if ((row + col) % 3 == 0) {
                return {'sample_slot': (col % 8)}; // Vary sample slots
              }
              return null; // Empty cell
            });
          }),
        },
        'sample_bank': {
          'samples': List.generate(10, (i) => {
            'color': {
              'r': ((i * 30) % 255) / 255.0,
              'g': ((i * 60) % 255) / 255.0,
              'b': ((i * 90) % 255) / 255.0,
            }
          }),
        },
      },
    };
    
    // Cache the mock snapshot
    _snapshotFutures[mockId] = Future.value(mockSnapshot);
  }
  
  // Header Column Builders
  
  Widget _buildHeaderPatternsColumn() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
            'PATTERNS',
              style: GoogleFonts.sourceSans3(
                color: AppColors.menuText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeaderSampleBankColumn() {
    return const SizedBox.shrink(); // Empty header
  }
  
  Widget _buildHeaderCountersColumn() {
    return const SizedBox.shrink(); // Empty header
  }
  
  Widget _buildHeaderCreatedColumn() {
    return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (_sortBy == 'created') {
                _sortAscending = !_sortAscending;
              } else {
                _sortBy = 'created';
                _sortAscending = false;
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                    'CREATED',
                      style: GoogleFonts.sourceSans3(
                        color: _sortBy == 'created' 
                            ? AppColors.menuText 
                            : AppColors.menuLightText,
                        fontSize: 10,
                        fontWeight: _sortBy == 'created'
                            ? FontWeight.w500
                            : FontWeight.w400,
                      letterSpacing: 1.3,
                      ),
                    ),
                    if (_sortBy == 'created')
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 12,
                          color: AppColors.menuText,
                        ),
                      ),
                  ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeaderModifiedColumn() {
    return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (_sortBy == 'modified') {
                _sortAscending = !_sortAscending;
              } else {
                _sortBy = 'modified';
                _sortAscending = false;
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                    'MODIFIED',
                      style: GoogleFonts.sourceSans3(
                        color: _sortBy == 'modified' 
                            ? AppColors.menuText 
                            : AppColors.menuLightText,
                        fontSize: 10,
                        fontWeight: _sortBy == 'modified'
                            ? FontWeight.w500
                            : FontWeight.w400,
                      letterSpacing: 1.3,
                      ),
                    ),
                    if (_sortBy == 'modified')
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 12,
                          color: AppColors.menuText,
                        ),
                      ),
                  ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  List<Color> _getSampleBankColors(Map<String, dynamic> snapshotData) {
    // Default color palette (same as in SampleBankState)
    return const [
      Color(0xFFE57373), // Red
      Color(0xFFF06292), // Pink
      Color(0xFFBA68C8), // Purple
      Color(0xFF9575CD), // Deep Purple
      Color(0xFF7986CB), // Indigo
      Color(0xFF64B5F6), // Blue
      Color(0xFF4FC3F7), // Light Blue
      Color(0xFF4DD0E1), // Cyan
      Color(0xFF4DB6AC), // Teal
      Color(0xFF81C784), // Green
      Color(0xFFAED581), // Light Green
      Color(0xFFDCE775), // Lime
      Color(0xFFFFF176), // Yellow
      Color(0xFFFFD54F), // Amber
      Color(0xFFFFB74D), // Orange
      Color(0xFFFF8A65), // Deep Orange
      Color(0xFFA1887F), // Brown
      Color(0xFFE0E0E0), // Grey
      Color(0xFF90A4AE), // Blue Grey
      Color(0xFFEF5350), // Red (alt)
      Color(0xFFEC407A), // Pink (alt)
      Color(0xFFAB47BC), // Purple (alt)
      Color(0xFF7E57C2), // Deep Purple (alt)
      Color(0xFF5C6BC0), // Indigo (alt)
      Color(0xFF42A5F5), // Blue (alt)
      Color(0xFF29B6F6), // Light Blue (alt)
    ];
  }
  
  Future<Map<String, dynamic>?> _getProjectSnapshot(String threadId) {
    // Return cached future if already loading/loaded
    if (_snapshotFutures.containsKey(threadId)) {
      return _snapshotFutures[threadId]!;
    }
    
    // Create and cache the future
    final future = _fetchProjectSnapshot(threadId);
    _snapshotFutures[threadId] = future;
    return future;
  }
  
  Future<Map<String, dynamic>?> _fetchProjectSnapshot(String threadId) async {
    try {
      final threadsState = context.read<ThreadsState>();
      final snapshot = await threadsState.loadProjectSnapshot(threadId);
      debugPrint('📸 [PROJECTS] Loaded snapshot for $threadId: ${snapshot != null ? "success" : "null"}');
      return snapshot;
    } catch (e) {
      debugPrint('❌ [PROJECTS] Error loading snapshot for $threadId: $e');
      return null;
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);
    
    if (dateDay == today) {
      // Show relative time for today (e.g., "2h ago", "5m ago")
      final difference = now.difference(date);
      if (difference.inMinutes < 1) {
        return 'just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
      return 'Today';
      }
    } else if (dateDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      // Always show year in short format (e.g., "8/17/25")
      final yearShort = date.year % 100; // Get last 2 digits of year
      return '${date.month}/${date.day}/${yearShort.toString().padLeft(2, '0')}';
    }
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
    final others = project.users.where((u) => u.id != me).map((u) => u.username).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    final List<Widget> chips = [];
    const maxVisible = 2;
    for (final username in others.take(maxVisible)) {
      chips.add(Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.menuBorder.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          username,
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
            'Are you sure you want to delete this pattern? This will delete it for all participants.',
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

// ============================================================================
// CHECKERBOARD PATTERN PAINTER
// ============================================================================
// Custom painter for creating a checkerboard/grid background pattern
// Uses two alternating colors with configurable square size and corner roundness

class _CheckerboardPatternPainter extends CustomPainter {
  final Color color1;
  final Color color2;
  final double squareSize;
  final double cornerRadius;

  _CheckerboardPatternPainter({
    required this.color1,
    required this.color2,
    required this.squareSize,
    required this.cornerRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = color1
      ..style = PaintingStyle.fill;
      
    final paint2 = Paint()
      ..color = color2
      ..style = PaintingStyle.fill;

    // Calculate number of squares needed to cover the canvas
    final numCols = (size.width / squareSize).ceil() + 1;
    final numRows = (size.height / squareSize).ceil() + 1;

    // Draw checkerboard pattern
    for (int row = 0; row < numRows; row++) {
      for (int col = 0; col < numCols; col++) {
        // Alternate colors based on row + col (checkerboard pattern)
        final isEvenSquare = (row + col) % 2 == 0;
        final paint = isEvenSquare ? paint1 : paint2;
        
        final left = col * squareSize;
        final top = row * squareSize;
        final rect = Rect.fromLTWH(left, top, squareSize, squareSize);
        
        if (cornerRadius > 0) {
          // Draw rounded rectangle
          final rrect = RRect.fromRectAndRadius(
            rect,
            Radius.circular(cornerRadius),
          );
          canvas.drawRRect(rrect, paint);
        } else {
          // Draw square rectangle
          canvas.drawRect(rect, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPatternPainter oldDelegate) {
    return oldDelegate.color1 != color1 ||
        oldDelegate.color2 != color2 ||
        oldDelegate.squareSize != squareSize ||
        oldDelegate.cornerRadius != cornerRadius;
  }
} 