import 'package:flutter/foundation.dart';

/// State for displaying a transient overlay during slider interactions
class SliderOverlayState extends ChangeNotifier {
  final ValueNotifier<bool> isInteractingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> settingNameNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> valueNotifier = ValueNotifier<String>('');

  void startInteraction(String settingName, String value) {
    settingNameNotifier.value = settingName;
    valueNotifier.value = value;
    isInteractingNotifier.value = true;
    notifyListeners();
  }

  void updateValue(String value) {
    valueNotifier.value = value;
    notifyListeners();
  }

  void stopInteraction() {
    isInteractingNotifier.value = false;
    settingNameNotifier.value = '';
    valueNotifier.value = '';
    notifyListeners();
  }

  @override
  void dispose() {
    isInteractingNotifier.dispose();
    settingNameNotifier.dispose();
    valueNotifier.dispose();
    super.dispose();
  }
}


