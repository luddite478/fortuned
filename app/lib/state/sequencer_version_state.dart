import 'package:flutter/foundation.dart';

enum SequencerVersion { v1, v2 }

class SequencerVersionState extends ChangeNotifier {
  SequencerVersion _currentVersion = SequencerVersion.v2;

  SequencerVersion get currentVersion => _currentVersion;

  void setVersion(SequencerVersion version) {
    if (_currentVersion != version) {
      debugPrint('🔄 SequencerVersionState: Changing from $_currentVersion to $version');
      _currentVersion = version;
      notifyListeners();
    }
  }

  bool get isV1 => _currentVersion == SequencerVersion.v1;
  bool get isV2 => _currentVersion == SequencerVersion.v2;
}
