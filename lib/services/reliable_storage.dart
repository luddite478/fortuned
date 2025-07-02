import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// Reliable cross-platform storage that avoids SharedPreferences pigeon channel issues on Android
class ReliableStorage {
  static String get _documentsPath {
    if (Platform.isAndroid) {
      // Use Android's internal app data directory
      return '/storage/emulated/0/Android/data/com.example.niyya/files';
    } else if (Platform.isIOS) {
      return '/var/mobile/Containers/Data/Application/Documents';
    } else if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE']}\\Documents\\niyya';
    } else if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Documents/niyya';
    } else {
      return '/tmp/niyya'; // Fallback
    }
  }
  
  static File get _prefsFile => File(path.join(_documentsPath, 'niyya_prefs.json'));
  
  static Future<Map<String, dynamic>> _loadPrefs() async {
    try {
      if (await _prefsFile.exists()) {
        final content = await _prefsFile.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      print('⚠️ Error loading prefs: $e');
    }
    return {};
  }
  
  static Future<void> _savePrefs(Map<String, dynamic> prefs) async {
    try {
      // Ensure directory exists
      await _prefsFile.parent.create(recursive: true);
      await _prefsFile.writeAsString(json.encode(prefs));
    } catch (e) {
      print('⚠️ Error saving prefs: $e');
    }
  }
  
  // SharedPreferences-compatible interface
  static Future<void> setString(String key, String value) async {
    final prefs = await _loadPrefs();
    prefs[key] = value;
    await _savePrefs(prefs);
  }
  
  static Future<String?> getString(String key) async {
    final prefs = await _loadPrefs();
    return prefs[key] as String?;
  }
  
  static Future<void> setStringList(String key, List<String> value) async {
    final prefs = await _loadPrefs();
    prefs[key] = value;
    await _savePrefs(prefs);
  }
  
  static Future<List<String>> getStringList(String key) async {
    final prefs = await _loadPrefs();
    final value = prefs[key];
    if (value is List) {
      return List<String>.from(value);
    }
    return [];
  }
  
  static Future<void> setBool(String key, bool value) async {
    final prefs = await _loadPrefs();
    prefs[key] = value;
    await _savePrefs(prefs);
  }
  
  static Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final prefs = await _loadPrefs();
    return prefs[key] as bool? ?? defaultValue;
  }
  
  static Future<void> setInt(String key, int value) async {
    final prefs = await _loadPrefs();
    prefs[key] = value;
    await _savePrefs(prefs);
  }
  
  static Future<int> getInt(String key, {int defaultValue = 0}) async {
    final prefs = await _loadPrefs();
    return prefs[key] as int? ?? defaultValue;
  }
  
  static Future<void> remove(String key) async {
    final prefs = await _loadPrefs();
    prefs.remove(key);
    await _savePrefs(prefs);
  }
  
  static Future<void> clear() async {
    await _savePrefs({});
  }
} 