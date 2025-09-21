import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/slider_overlay.dart';
// musical note formatting handled externally if needed
class MusicalNotes {
  static const List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];
  
  static Map<String, String> getNoteInfo(int semitones) {
    final normalizedSemitones = semitones % 12;
    final noteIndex = normalizedSemitones < 0 ? normalizedSemitones + 12 : normalizedSemitones;
    final noteName = _noteNames[noteIndex];
    
    return {
      'note': noteName,
      'semitones': semitones.toString(),
    };
  }
}

enum SliderType {
  volume,
  pitch,
  bpm,
}

// Custom thumb shape that displays the current value
class ValueDisplayThumbShape extends SliderComponentShape {
  final String value;
  final double thumbRadius;
  
  const ValueDisplayThumbShape({
    required this.value,
    required this.thumbRadius,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    
    // Draw the thumb background
    final Paint thumbPaint = Paint()
      ..color = const Color(0xFF8B7355) // AppColors.sequencerAccent
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, thumbRadius, thumbPaint);
    
    // Draw border
    final Paint borderPaint = Paint()
      ..color = const Color(0xFF5A5A57) // AppColors.sequencerBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(center, thumbRadius, borderPaint);
    
    // Draw the value text
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: this.value,
        style: GoogleFonts.sourceSans3(
          color: Colors.white,
          fontSize: thumbRadius * 0.6,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }
}

class GenericSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final SliderType type;
  final Function(double) onChanged;
  final double height;
  final SliderOverlayState? sliderOverlay; // optional overlay state
  final String? contextLabel;

  const GenericSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.type,
    required this.onChanged,
    required this.height,
    required this.sliderOverlay,
    this.contextLabel,
  });

  String _getSettingName() {
    switch (type) {
      case SliderType.volume:
        return 'VOLUME';
      case SliderType.pitch:
        return 'PITCH';
      case SliderType.bpm:
        return 'BPM';
    }
  }

  String _formatValue(double value) {
    switch (type) {
      case SliderType.volume:
        final volumePercent = (value * 100).round();
        return '$volumePercent';
      case SliderType.pitch:
        final semitones = (value * 24 - 12).round();
        final noteInfo = MusicalNotes.getNoteInfo(semitones);
        return '${noteInfo['note']}';
      case SliderType.bpm:
        return '${value.round()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbRadius = (height * 0.15).clamp(20.0, 40.0); // Much larger thumb
    final currentValueText = _formatValue(value);
    
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: const Color(0xFF8B7355), // AppColors.sequencerAccent
        inactiveTrackColor: const Color(0xFF5A5A57), // AppColors.sequencerBorder
        thumbColor: const Color(0xFF8B7355), // AppColors.sequencerAccent
        trackHeight: (height * 0.04).clamp(2.0, 8.0),
        thumbShape: ValueDisplayThumbShape(
          value: currentValueText,
          thumbRadius: thumbRadius,
        ),
      ),
      child: Slider(
        value: value,
        onChanged: (newValue) {
          onChanged(newValue);
          if (sliderOverlay != null) {
            sliderOverlay!.updateValue(_formatValue(newValue));
          }
        },
        onChangeStart: (newValue) {
          if (sliderOverlay != null) {
            sliderOverlay!.startInteraction(
              _getSettingName(),
              _formatValue(newValue),
              contextLabel: contextLabel ?? '',
            );
          }
        },
        onChangeEnd: (newValue) {
          if (sliderOverlay != null) {
            sliderOverlay!.stopInteraction();
          }
        },
        min: min,
        max: max,
        divisions: divisions,
      ),
    );
  }
} 