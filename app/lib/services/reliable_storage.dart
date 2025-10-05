import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:docman/docman.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reliable cross-platform storage that uses DocMan for Android app directories
/// Avoids SharedPreferences pigeon channel issues on Android
class ReliableStorage {
  
  /// Get the best available app data directory path
  static Future<String> get _documentsPath async {
    final appName = dotenv.env['APP_NAME']!;
    if (Platform.isAndroid) {
      return await _getAndroidAppDataPath();
    } else if (Platform.isIOS) {
      return await _getIOSDocumentsPath();
    } else if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE']}\\Documents\\$appName';
    } else if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Documents/$appName';
    } else {
      return '/tmp/$appName'; // Fallback
    }
  }
  
  /// Get the best available Android app data path using DocMan
  static Future<String> _getAndroidAppDataPath() async {
    final appName = dotenv.env['APP_NAME']!;
    try {
      // Try internal app files directory first (most persistent for preferences)
      final filesDir = await DocMan.dir.files();
      if (filesDir != null) {
        return path.join(filesDir.path, '${appName}_prefs');
      }
      
      // Fallback to cache directory
      final cacheDir = await DocMan.dir.cache();
      if (cacheDir != null) {
        return path.join(cacheDir.path, '${appName}_prefs');
      }
      
      // Last resort fallback to Downloads
      return '/storage/emulated/0/Download/${appName}_data';
    } catch (e) {
      print('⚠️ DocMan failed, using Downloads fallback: $e');
      return '/storage/emulated/0/Download/${appName}_data';
    }
  }

  /// Get a safe iOS documents path using DocMan fallbacks
  static Future<String> _getIOSDocumentsPath() async {
    final appName = dotenv.env['APP_NAME']!;
    try {
      // Prefer internal app files directory (sandboxed, always writable)
      final filesDir = await DocMan.dir.files();
      if (filesDir != null) {
        return filesDir.path;
      }

      final cacheDir = await DocMan.dir.cache();
      if (cacheDir != null) {
        return cacheDir.path;
      }

      return '/tmp/$appName';
    } catch (e) {
      print('⚠️ DocMan iOS failed, using /tmp fallback: $e');
      return '/tmp/$appName';
    }
  }
  
  static Future<File> get _prefsFile async {
    final appName = dotenv.env['APP_NAME']!;
    final docPath = await _documentsPath;
    final file = File(path.join(docPath, '${appName}_prefs.json'));
    await file.parent.create(recursive: true);
    return file;
  }

  // Recording helpers removed; now handled in RecordingState
  
  static Future<Map<String, dynamic>> _loadPrefs() async {
    try {
      final file = await _prefsFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      print('⚠️ Error loading prefs: $e');
    }
    return {};
  }
  
  static Future<void> _savePrefs(Map<String, dynamic> prefs) async {
    try {
      final file = await _prefsFile;
      // Ensure directory exists
      await file.parent.create(recursive: true);
      await file.writeAsString(json.encode(prefs));
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