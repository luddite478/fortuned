import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';

enum SequencerBodyOverlayMenuType {
  sectionSettings,
  sectionCreation,
  recording,
  sampleBrowser,
}

class SequencerBodyOverlayMenu extends StatelessWidget {
  final SequencerBodyOverlayMenuType type;
  final Widget child;

  const SequencerBodyOverlayMenu({
    super.key,
    required this.type,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = switch (type) {
      // Section settings keeps slight transparency
      SequencerBodyOverlayMenuType.sectionSettings => AppColors.sequencerPageBackground.withOpacity(0.7),
      SequencerBodyOverlayMenuType.sectionCreation => AppColors.sequencerPageBackground,
      SequencerBodyOverlayMenuType.recording => AppColors.sequencerPageBackground.withOpacity(0.7),
      // Sample browser should be fully opaque to prevent grid bleed-through
      SequencerBodyOverlayMenuType.sampleBrowser => AppColors.sequencerPageBackground,
    };

    return Container(
      color: backgroundColor,
      child: child,
    );
  }
} 