import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';

enum SequencerBodyOverlayMenuType {
  sectionSettings,
  sectionCreation,
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
      SequencerBodyOverlayMenuType.sectionSettings => AppColors.sequencerPageBackground.withOpacity(0.7),
      SequencerBodyOverlayMenuType.sectionCreation => AppColors.sequencerPageBackground,
    };

    return Container(
      color: backgroundColor,
      child: child,
    );
  }
} 