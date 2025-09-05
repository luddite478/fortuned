import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';
import 'package:provider/provider.dart';
import '../../../state/threads_state.dart';
import '../../../screens/thread_screen.dart';
import '../../../state/sequencer/table.dart';

class MessageBarWidget extends StatelessWidget {
  static const double leftButtonContainerPercent = 0.15;
  static const double centerButtonContainerPercent = 0.7;
  static const double rightButtonContainerPercent = 0.15;
  static const double leftButtonHorizontalPosition = 0.8;
  static const double centerButtonHorizontalPosition = 0.5;
  static const double rightButtonHorizontalPosition = 0.5;
  static const double leftButtonWidthPercent = 0.9;
  static const double leftButtonHeightPercent = 0.7;
  static const double centerButtonWidthPercent = 1;
  static const double centerButtonHeightPercent = 0.7;
  static const double rightButtonSizePercent = 0.5;
  static const double leftButtonsBorderRadiusPercent = 0.1;
  static const double rightButtonBorderRadiusPercent = 0.5;
  static const Color leftContainerBackgroundColor = AppColors.sequencerCellEmpty;
  static const Color centerContainerBackgroundColor = AppColors.sequencerCellEmpty;
  static const Color rightContainerBackgroundColor = Color.fromARGB(255, 67, 65, 65);
  static const double parentContainerWidthPercent = 0.975;
  static const double parentContainerHeightPercent = 1;
  static const Color parentContainerBackgroundColor = Color.fromARGB(255, 255, 3, 3);
  static const double parentContainerBorderRadiusPercent = 0.5;

  const MessageBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
        child: Consumer2<TableState, ThreadsState>(
          builder: (context, tableState, threadsState, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final barHeight = constraints.maxHeight;
                final barWidth = constraints.maxWidth;
                final leftContainerWidth = barWidth * leftButtonContainerPercent;
                final centerContainerWidth = barWidth * centerButtonContainerPercent;
                final rightContainerWidth = barWidth * rightButtonContainerPercent;
                final leftButtonWidth = leftContainerWidth * leftButtonWidthPercent;
                final leftButtonHeight = barHeight * leftButtonHeightPercent;
                final centerButtonWidth = centerContainerWidth * centerButtonWidthPercent;
                final centerButtonHeight = barHeight * centerButtonHeightPercent;
                final rightButtonSize = rightContainerWidth * rightButtonSizePercent;
                final leftBorderRadius = leftButtonHeight * leftButtonsBorderRadiusPercent;
                final rightBorderRadius = rightButtonSize * rightButtonBorderRadiusPercent;
                final parentContainerWidth = barWidth * parentContainerWidthPercent;
                final parentContainerHeight = barHeight * parentContainerHeightPercent;
                final parentBorderRadius = parentContainerHeight * parentContainerBorderRadiusPercent;

                return Center(
                  child: Container(
                    width: parentContainerWidth,
                    height: parentContainerHeight,
                    decoration: BoxDecoration(
                      color: parentContainerBackgroundColor,
                      borderRadius: BorderRadius.circular(parentBorderRadius),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: (leftButtonContainerPercent * 100).round(),
                          child: Container(
                            height: barHeight,
                            color: leftContainerBackgroundColor,
                            child: Align(
                              alignment: Alignment(leftButtonHorizontalPosition * 2 - 1, 0),
                              child: Container(
                                width: leftButtonWidth,
                                height: leftButtonHeight,
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 57, 57, 57),
                                  borderRadius: BorderRadius.circular(leftBorderRadius),
                                  border: Border.all(
                                    color: const Color.fromARGB(255, 57, 57, 57),
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(leftBorderRadius),
                                    onTap: () => _navigateToThread(context, threadsState),
                                    child: Center(
                                      child: Icon(
                                        Icons.format_list_bulleted,
                                        color: AppColors.sequencerLightText,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: (centerButtonContainerPercent * 100).round(),
                          child: Container(
                            height: barHeight,
                            color: centerContainerBackgroundColor,
                            child: Align(
                              alignment: Alignment(centerButtonHorizontalPosition * 2 - 1, 0),
                              child: Container(
                                width: centerButtonWidth,
                                height: centerButtonHeight,
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 53, 53, 53),
                                  borderRadius: BorderRadius.circular(leftBorderRadius),
                                  border: Border.all(
                                    color: const Color.fromARGB(255, 57, 57, 57),
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: _buildSectionChain(tableState.sectionsCount),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: (rightButtonContainerPercent * 100).round(),
                          child: Container(
                            height: barHeight,
                            color: rightContainerBackgroundColor,
                            child: Align(
                              alignment: Alignment(rightButtonHorizontalPosition * 2 - 1, 0),
                              child: Container(
                                width: rightButtonSize,
                                height: rightButtonSize,
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 90, 111, 114),
                                  borderRadius: BorderRadius.circular(rightBorderRadius),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color.fromARGB(255, 130, 130, 130).withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(rightBorderRadius),
                                    onTap: () => _sendMessageAndNavigate(context, threadsState),
                                    child: Center(
                                      child: CustomPaint(
                                        size: Size(rightButtonSize * 0.4, rightButtonSize * 0.4),
                                        painter: TrianglePainter(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionChain(int numSections) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(numSections * 2 - 1, (index) {
        if (index.isEven) {
          return Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 90, 111, 114),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: AppColors.sequencerBorder,
                width: 1,
              ),
            ),
          );
        } else {
          return Container(
            width: 8,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: AppColors.sequencerLightText,
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }
      }),
    );
  }

  void _navigateToThread(BuildContext context, ThreadsState threadsState) {
    final thread = threadsState.activeThread;
    if (thread != null) {
      threadsState.setActiveThread(thread);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ThreadScreen(threadId: thread.id),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publish your project first to create checkpoints'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _navigateToThreadWithHighlight(BuildContext context, ThreadsState threadsState) {
    final thread = threadsState.activeThread;
    if (thread != null) {
      threadsState.setActiveThread(thread);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ThreadScreen(threadId: thread.id, highlightNewest: true),
        ),
      );
    }
  }

  void _sendMessageAndNavigate(BuildContext context, ThreadsState threadsState) async {
    final activeThread = threadsState.activeThread;
    try {
      if (activeThread != null) {
        await threadsState.sendMessageFromSequencer(threadId: activeThread.id);
        if (context.mounted) {
          _navigateToThreadWithHighlight(context, threadsState);
        }
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }
}

class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(255, 209, 246, 245)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    path.moveTo(size.width * 0.0, size.height * 0.0);
    path.lineTo(size.width * 1, size.height * 0.5);
    path.lineTo(size.width * 0.0, size.height * 1);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 