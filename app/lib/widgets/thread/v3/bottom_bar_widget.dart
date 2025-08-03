import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';import '../../../state/sequencer_state.dart';
import '../../../utils/app_colors.dart';import '../../../state/threads_state.dart';
import '../../../utils/app_colors.dart';import '../../../services/threads_service.dart';
import '../../../utils/app_colors.dart';import '../../../screens/checkpoints_screen.dart';
import '../../../utils/app_colors.dart';

class BottomBarWidget extends StatefulWidget {
  final VoidCallback? onToggleView;
  final dynamic threadsService;
  
  const BottomBarWidget({
    super.key,
    this.onToggleView,
    this.threadsService,
  });

  @override
  State<BottomBarWidget> createState() => _BottomBarWidgetState();
}

class _BottomBarWidgetState extends State<BottomBarWidget> {
  
  void _handleSendAction() async {
    final sequencerState = Provider.of<SequencerState>(context, listen: false);
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    
    // Determine context and create checkpoint accordingly
    final activeThread = threadsState.activeThread;
    final sourceThread = sequencerState.sourceThread;
    
    try {
      if (sourceThread != null) {
        // Case: Sourced project - create fork with modifications (SEND)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Creating fork...'),
            backgroundColor: Colors.orangeAccent,
            duration: Duration(seconds: 1),
          ),
        );
        
                 final success = await sequencerState.createProjectFork(
           comment: 'Modified version',
           threadsService: widget.threadsService,
         );
        
        if (success) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Fork created successfully! 🎉'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to create fork'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
        return; // Exit early after handling sourced project
      } else if (activeThread != null) {
        // Check if this is unpublished solo thread (SAVE) or published/collaborative (SEND)
        final isUnpublishedSolo = activeThread.users.length == 1 && 
                                 activeThread.users.first.id == threadsState.currentUserId &&
                                 !(activeThread.metadata['is_public'] ?? false);
        
        if (isUnpublishedSolo) {
          // Case: Unpublished solo thread - add checkpoint to same thread (SAVE)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saving checkpoint...'),
              backgroundColor: Colors.orangeAccent,
              duration: Duration(seconds: 1),
            ),
          );
          
          final success = await threadsState.addCheckpointFromSequencer(
            activeThread.id,
            'Saved changes',
            sequencerState,
          );
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Checkpoint saved! 💾'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          // Case: Published/collaborative thread - create fork or add checkpoint (SEND)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Adding to collaboration...'),
              backgroundColor: Colors.orangeAccent,
              duration: Duration(seconds: 1),
            ),
          );
          
          final success = await threadsState.addCheckpointFromSequencer(
            activeThread.id,
            'New contribution',
            sequencerState,
          );
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Contribution added! 📤'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        // No active thread - this shouldn't happen now with auto-creation
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active project to save'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error in send action: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save/send checkpoint'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildFourSquaresIcon() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.sequencerLightText,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.sequencerLightText,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.sequencerLightText,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.sequencerLightText,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        border: Border(
          top: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Toggle view button (oval with 4 squares)
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceRaised,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.sequencerBorder,
                    width: 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: widget.onToggleView,
                    child: Center(
                      child: _buildFourSquaresIcon(),
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Send button
            Container(
              decoration: BoxDecoration(
                color: AppColors.sequencerAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _handleSendAction,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 