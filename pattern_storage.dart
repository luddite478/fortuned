import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../state/patterns_state.dart';

class PatternStorageService {
  static const String _patternsKey = 'saved_patterns';
  static const String _currentPatternKey = 'current_pattern_id';

  // Load all patterns from storage
  Future<List<Pattern>> loadPatterns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_patternsKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => Pattern.fromJson(json)).toList();
    } catch (e) {
      print('Error loading patterns: $e');
      return [];
    }
  }

  // Save all patterns to storage
  Future<bool> savePatterns(List<Pattern> patterns) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(patterns.map((p) => p.toJson()).toList());
      return await prefs.setString(_patternsKey, jsonString);
    } catch (e) {
      print('Error saving patterns: $e');
      return false;
    }
  }

  // Save a single pattern (updates existing or adds new)
  Future<bool> savePattern(Pattern pattern) async {
    try {
      final patterns = await loadPatterns();
      final index = patterns.indexWhere((p) => p.id == pattern.id);
      
      if (index >= 0) {
        patterns[index] = pattern;
      } else {
        patterns.add(pattern);
      }
      
      return await savePatterns(patterns);
    } catch (e) {
      print('Error saving pattern: $e');
      return false;
    }
  }

  // Delete a pattern
  Future<bool> deletePattern(String patternId) async {
    try {
      final patterns = await loadPatterns();
      patterns.removeWhere((p) => p.id == patternId);
      return await savePatterns(patterns);
    } catch (e) {
      print('Error deleting pattern: $e');
      return false;
    }
  }

  // Load a specific pattern by ID
  Future<Pattern?> loadPattern(String patternId) async {
    try {
      final patterns = await loadPatterns();
      return patterns.firstWhere(
        (p) => p.id == patternId,
        orElse: () => throw Exception('Pattern not found'),
      );
    } catch (e) {
      print('Error loading pattern $patternId: $e');
      return null;
    }
  }

  // Save current pattern ID
  Future<bool> setCurrentPatternId(String? patternId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (patternId == null) {
        return await prefs.remove(_currentPatternKey);
      } else {
        return await prefs.setString(_currentPatternKey, patternId);
      }
    } catch (e) {
      print('Error setting current pattern ID: $e');
      return false;
    }
  }

  // Get current pattern ID
  Future<String?> getCurrentPatternId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_currentPatternKey);
    } catch (e) {
      print('Error getting current pattern ID: $e');
      return null;
    }
  }

  // Clear all data (for testing/reset)
  Future<bool> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_patternsKey);
      await prefs.remove(_currentPatternKey);
      return true;
    } catch (e) {
      print('Error clearing data: $e');
      return false;
    }
  }
} 