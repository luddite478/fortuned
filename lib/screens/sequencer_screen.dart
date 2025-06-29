import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../widgets/sequencer/top_multitask_panel_widget.dart';
import '../widgets/sequencer/sample_banks_widget.dart';
import '../widgets/sequencer/sound_grid_widget.dart';
import '../widgets/sequencer/edit_buttons_widget.dart';
import '../widgets/app_header_widget.dart';
import '../state/sequencer_state.dart';
import '../state/threads_state.dart';
import '../services/chat_client.dart';

import 'checkpoints_screen.dart';

class PatternScreen extends StatefulWidget {
  const PatternScreen({super.key});

  @override
  State<PatternScreen> createState() => _PatternScreenState();
}

class _PatternScreenState extends State<PatternScreen> with WidgetsBindingObserver {
  late ChatClient _chatClient;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatClient = ChatClient();
    _setupChatClient();
  }

  void _setupChatClient() async {
    // Connect to server for sending thread messages
    final clientId = '${dotenv.env['CLIENT_ID_PREFIX'] ?? 'flutter_user'}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    await _chatClient.connect(clientId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatClient.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Re-configure Bluetooth audio session when app becomes active
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed - reconfiguring Bluetooth audio session');
      // This will be handled by the AudioService later
    }
  }

  void _navigateToCheckpoints() {
    final threadsState = context.read<ThreadsState>();
    final currentThread = threadsState.currentThread;
    
    if (currentThread != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckpointsScreen(
            threadId: currentThread.id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppHeaderWidget(
        mode: HeaderMode.sequencer,
        onBack: () => Navigator.of(context).pop(),
        chatClient: _chatClient,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final screenWidth = constraints.maxWidth;
          
          // EASY FOOTER SIZE CONTROL - Adjust this value for iPhone bottom clearance
          const double footerPadding = 7.0; // Easy to adjust for different needs
          
          // EASY PERCENTAGE CONTROL - Adjust these values to redistribute space
          const double multitaskPanelPercent = 20.0;    // 20%
          const double sampleBanksPercent = 8.0;        // 8%
          const double sampleGridPercent = 63.0;        // 63% - Main grid (increased)
          const double editButtonsPercent = 9.0;        // 9%
          
          // Calculate spacing to distribute evenly
          final totalContentPercent = multitaskPanelPercent + sampleBanksPercent + 
                                    sampleGridPercent + editButtonsPercent;
          final remainingPercent = 100.0 - totalContentPercent;
          final singleSpacingPercent = remainingPercent / 5; // 5 spacing areas
          
          // Use screen height minus footer padding
          final availableHeight = screenHeight - footerPadding;
          
          final multitaskPanelHeight = availableHeight * (multitaskPanelPercent / 100);
          final sampleBanksHeight = availableHeight * (sampleBanksPercent / 100);
          final sampleGridHeight = availableHeight * (sampleGridPercent / 100);
          final editButtonsHeight = availableHeight * (editButtonsPercent / 100);
          final spacingHeight = availableHeight * (singleSpacingPercent / 100);
            
            final totalUsedHeight = multitaskPanelHeight + spacingHeight + 
                                  sampleBanksHeight + spacingHeight + sampleGridHeight + 
                                  spacingHeight + editButtonsHeight + spacingHeight;
            
            final unusedHeight = screenHeight - totalUsedHeight;
            final unusedPercentage = (unusedHeight / screenHeight) * 100;
            
            // Debug log of space allocation
            debugPrint('📐 SEQUENCER HEIGHT ALLOCATION (AUTO-FILL):');
            debugPrint('📱 Total Screen Height: ${screenHeight.toStringAsFixed(1)}px');
            debugPrint('📐 Available Height: ${availableHeight.toStringAsFixed(1)}px (minus border padding)');
            debugPrint('┌─ Multitask Panel: ${multitaskPanelHeight.toStringAsFixed(1)}px (${multitaskPanelPercent.toStringAsFixed(1)}%)');
            debugPrint('├─ Spacing: ${spacingHeight.toStringAsFixed(1)}px (${singleSpacingPercent.toStringAsFixed(1)}%)');
            debugPrint('├─ Sample Banks: ${sampleBanksHeight.toStringAsFixed(1)}px (${sampleBanksPercent.toStringAsFixed(1)}%)');
            debugPrint('├─ Spacing: ${spacingHeight.toStringAsFixed(1)}px (${singleSpacingPercent.toStringAsFixed(1)}%)');
            debugPrint('├─ Sample Grid: ${sampleGridHeight.toStringAsFixed(1)}px (${sampleGridPercent.toStringAsFixed(1)}%)');
            debugPrint('├─ Spacing: ${spacingHeight.toStringAsFixed(1)}px (${singleSpacingPercent.toStringAsFixed(1)}%)');
            debugPrint('├─ Edit Buttons: ${editButtonsHeight.toStringAsFixed(1)}px (${editButtonsPercent.toStringAsFixed(1)}%)');
            debugPrint('├─ Spacing: ${spacingHeight.toStringAsFixed(1)}px (${singleSpacingPercent.toStringAsFixed(1)}%)');
            debugPrint('└─ Border: No padding - using full screen height');
            debugPrint('🔢 Total Content: ${(totalContentPercent).toStringAsFixed(1)}%');
            debugPrint('🔢 Total Used: ${totalUsedHeight.toStringAsFixed(1)}px (${((totalUsedHeight/screenHeight)*100).toStringAsFixed(1)}%)');
            debugPrint('🆓 Unused Space: ${unusedHeight.toStringAsFixed(1)}px (${unusedPercentage.toStringAsFixed(1)}%)');
            debugPrint('─────────────────────────────────────');
            
            return Column(
              children: [
                // Auto-calculated spacing
                SizedBox(height: spacingHeight),
                
                // Multitask panel
                SizedBox(
                  height: multitaskPanelHeight,
                  child: const MultitaskPanelWidget(),
                ),
                
                // Auto-calculated spacing
                SizedBox(height: spacingHeight),
                
                // Sample banks panel
                SizedBox(
                  height: sampleBanksHeight,
                  child: const SampleBanksWidget(),
                ),
                
                // Auto-calculated spacing
                SizedBox(height: spacingHeight),
                
                // Sample grid
                SizedBox(
                  height: sampleGridHeight,
                  child: const SampleGridWidget(),
                ),
                
                // Auto-calculated spacing
                SizedBox(height: spacingHeight),
                
                // Edit buttons panel
                SizedBox(
                  height: editButtonsHeight,
                  child: const EditButtonsWidget(),
                ),
                
                // Auto-calculated spacing (fills remaining space)
                SizedBox(height: spacingHeight),
                
                // Footer container matching edit buttons style
                Container(
                  height: footerPadding,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 244, 244, 244),
                  ),
                ),
              ],
            );
        },
      ),
    );
  }
} 