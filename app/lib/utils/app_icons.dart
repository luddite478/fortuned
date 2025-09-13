import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Centralized configurable icons used across the app.
///
/// Swap the values below to test different icons without changing widget code.
class AppIcons {
  AppIcons._();

  /// Base directory for icon assets.
  static const String _iconsBasePath = 'icons/';

  /// Send icon asset filename (SVG). Point to any file under `icons/`.
  static String sendIconAsset = 'send-arrow';

  /// Default size multiplier for send icon when used in square buttons.
  static double sendIconScale = 1;

  /// Returns a widget for the configured send icon.
  ///
  /// - [size] is the target square size of the button area; the icon will be
  ///   scaled by [sendIconScale]. If you want a fixed size, pass [fixedSize].
  /// - [color] optionally applies a color filter to the SVG.
  static Widget buildSendIcon({
    required double size,
    Color? color,
    double? fixedSize,
  }) {
    final double iconSize = fixedSize ?? size * sendIconScale;
    final String assetPath = '$_iconsBasePath$sendIconAsset';

    return SvgPicture.asset(
      assetPath,
      width: iconSize,
      height: iconSize,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
      fit: BoxFit.contain,
      package: null,
    );
  }
}


