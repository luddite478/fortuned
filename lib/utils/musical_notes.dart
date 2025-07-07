// Musical Notes Utility
// Converts between slider positions (0-131), note names, and pitch multipliers

import 'dart:math' as math;

const int _totalNotes = 121; // C0 to C10 (10 octaves + 1 note = 121 positions: 0-120)
const int _defaultCenterNote = 60; // C5 (center position)

// Note names for each semitone within an octave
const List<String> _noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
];

/// Convert slider position (0-131) to musical note name
String sliderPositionToNoteName(int position) {
  if (position < 0 || position >= _totalNotes) {
    return 'C5'; // Default fallback
  }
  
  final octave = position ~/ 12;
  final semitone = position % 12;
  
  return '${_noteNames[semitone]}$octave';
}

/// Convert musical note name to slider position
int noteNameToSliderPosition(String noteName) {
  // Parse note name (e.g., "C#5" -> "C#" and "5")
  final RegExp noteRegex = RegExp(r'^([A-G]#?)(\d+)$');
  final match = noteRegex.firstMatch(noteName);
  
  if (match == null) {
    return _defaultCenterNote; // Default to C5
  }
  
  final noteStr = match.group(1)!;
  final octave = int.parse(match.group(2)!);
  
  // Find semitone within octave
  final semitone = _noteNames.indexOf(noteStr);
  if (semitone == -1) {
    return _defaultCenterNote; // Default to C5
  }
  
  final position = octave * 12 + semitone;
  return position.clamp(0, _totalNotes - 1);
}

/// Convert slider position to pitch multiplier
/// C5 (position 60) = 1.0, each semitone = 2^(1/12) ratio
double sliderPositionToPitchMultiplier(int position) {
  if (position < 0 || position >= _totalNotes) {
    return 1.0; // Default to no pitch change
  }
  
  // Number of semitones from C5 (center)
  final semitonesFromCenter = position - _defaultCenterNote;
  
  // Each semitone is 2^(1/12) ratio
  return math.pow(2.0, semitonesFromCenter / 12.0).toDouble();
}

/// Convert pitch multiplier to slider position
int pitchMultiplierToSliderPosition(double pitchMultiplier) {
  if (pitchMultiplier <= 0) {
    return _defaultCenterNote; // Default to C5
  }
  
  // Calculate semitones from center using logarithm
  final semitonesFromCenter = (12.0 * math.log(pitchMultiplier) / math.ln2).round();
  final position = _defaultCenterNote + semitonesFromCenter;
  
  return position.clamp(0, _totalNotes - 1);
}

/// Get the default center position (C5)
int getDefaultCenterPosition() {
  return _defaultCenterNote;
}

/// Get the total number of notes (slider range)
int getTotalNotes() {
  return _totalNotes;
}

/// Get note name for default center position
String getDefaultCenterNoteName() {
  return sliderPositionToNoteName(_defaultCenterNote);
}

/// Check if a position is the default center
bool isDefaultCenter(int position) {
  return position == _defaultCenterNote;
}

/// Check if a pitch multiplier is the default (1.0)
bool isDefaultPitch(double pitchMultiplier) {
  return (pitchMultiplier - 1.0).abs() < 0.001; // Allow small floating point errors
} 