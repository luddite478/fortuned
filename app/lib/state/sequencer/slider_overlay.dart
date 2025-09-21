import 'package:flutter/foundation.dart';

/// State for displaying a transient overlay during slider interactions
class SliderOverlayState extends ChangeNotifier {
  final ValueNotifier<bool> isInteractingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> settingNameNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> valueNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> contextNotifier = ValueNotifier<String>('');

  void startInteraction(String settingName, String value, {String contextLabel = ''}) {
    settingNameNotifier.value = settingName;
    valueNotifier.value = value;
    contextNotifier.value = contextLabel;
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
    contextNotifier.value = '';
    notifyListeners();
  }

  @override
  void dispose() {
    isInteractingNotifier.dispose();
    settingNameNotifier.dispose();
    valueNotifier.dispose();
    contextNotifier.dispose();
    super.dispose();
  }
}


