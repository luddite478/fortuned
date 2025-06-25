import 'package:flutter/foundation.dart';
import '../services/pattern_storage.dart';

// Pattern data model
class Pattern {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<int?> gridSamples;
  final int gridColumns;
  final int gridRows;
  final List<String?> samplePaths;
  final List<String?> sampleNames;

  Pattern({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    required this.gridSamples,
    required this.gridColumns,
    required this.gridRows,
    required this.samplePaths,
    required this.sampleNames,
  });

  // Create a new empty pattern
  factory Pattern.empty() {
    final now = DateTime.now();
    final dateString = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    
    return Pattern(
      id: now.millisecondsSinceEpoch.toString(),
      name: dateString,
      createdAt: now,
      modifiedAt: now,
      gridSamples: List.filled(4 * 16, null), // Default 4x16 grid
      gridColumns: 4,
      gridRows: 16,
      samplePaths: List.filled(8, null), // 8 sample slots
      sampleNames: List.filled(8, null),
    );
  }

  // Create copy with updated data
  Pattern copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<int?>? gridSamples,
    int? gridColumns,
    int? gridRows,
    List<String?>? samplePaths,
    List<String?>? sampleNames,
  }) {
    return Pattern(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? DateTime.now(),
      gridSamples: gridSamples ?? List.from(this.gridSamples),
      gridColumns: gridColumns ?? this.gridColumns,
      gridRows: gridRows ?? this.gridRows,
      samplePaths: samplePaths ?? List.from(this.samplePaths),
      sampleNames: sampleNames ?? List.from(this.sampleNames),
    );
  }

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'gridSamples': gridSamples,
      'gridColumns': gridColumns,
      'gridRows': gridRows,
      'samplePaths': samplePaths,
      'sampleNames': sampleNames,
    };
  }

  // Create from JSON
  factory Pattern.fromJson(Map<String, dynamic> json) {
    return Pattern(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      gridSamples: (json['gridSamples'] as List).cast<int?>(),
      gridColumns: json['gridColumns'] as int,
      gridRows: json['gridRows'] as int,
      samplePaths: (json['samplePaths'] as List).cast<String?>(),
      sampleNames: (json['sampleNames'] as List).cast<String?>(),
    );
  }

  @override
  String toString() {
    return 'Pattern(id: $id, name: $name, modified: $modifiedAt)';
  }
}

// Patterns state management
class PatternsState extends ChangeNotifier {
  final PatternStorageService _storageService = PatternStorageService();
  
  List<Pattern> _patterns = [];
  Pattern? _currentPattern;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<Pattern> get patterns => List.unmodifiable(_patterns);
  Pattern? get currentPattern => _currentPattern;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasPatterns => _patterns.isNotEmpty;

  // Initialize the state
  Future<void> initialize() async {
    _setLoading(true);
    await _loadPatterns();
    await _loadCurrentPattern();
    _setLoading(false);
  }

  // Load all patterns from storage
  Future<void> _loadPatterns() async {
    try {
      final patternsData = await _storageService.loadPatterns();
      _patterns = patternsData; // Already Pattern objects from storage
      
      // Sort by modification date (newest first)
      _patterns.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      
      _clearError();
    } catch (e) {
      _setError('Failed to load patterns: $e');
    }
  }

  // Load current pattern from storage
  Future<void> _loadCurrentPattern() async {
    try {
      final currentPatternId = await _storageService.getCurrentPatternId();
      if (currentPatternId != null && currentPatternId.isNotEmpty) {
        _currentPattern = _patterns.firstWhere(
          (pattern) => pattern.id == currentPatternId,
          orElse: () => _patterns.isNotEmpty ? _patterns.first : Pattern.empty(),
        );
      } else if (_patterns.isNotEmpty) {
        _currentPattern = _patterns.first;
      }
    } catch (e) {
      if (_patterns.isNotEmpty) {
        _currentPattern = _patterns.first;
      }
    }
    notifyListeners();
  }

  // Create a new empty pattern
  Future<Pattern?> createNewPattern() async {
    _setLoading(true);
    try {
      final newPattern = Pattern.empty();
      final success = await _storageService.savePattern(newPattern);
      
      if (success) {
        _patterns.insert(0, newPattern); // Add to beginning
        await setCurrentPattern(newPattern);
        _clearError();
        notifyListeners();
        return newPattern;
      } else {
        _setError('Failed to create pattern');
        return null;
      }
    } catch (e) {
      _setError('Error creating pattern: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  // Save current pattern with updated data
  Future<bool> saveCurrentPattern({
    String? name,
    List<int?>? gridSamples,
    int? gridColumns,
    int? gridRows,
    List<String?>? samplePaths,
    List<String?>? sampleNames,
  }) async {
    if (_currentPattern == null) return false;

    try {
      final updatedPattern = _currentPattern!.copyWith(
        name: name,
        gridSamples: gridSamples,
        gridColumns: gridColumns,
        gridRows: gridRows,
        samplePaths: samplePaths,
        sampleNames: sampleNames,
      );

      final success = await _storageService.savePattern(updatedPattern);
      
      if (success) {
        // Update in memory
        final index = _patterns.indexWhere((p) => p.id == updatedPattern.id);
        if (index >= 0) {
          _patterns[index] = updatedPattern;
          _currentPattern = updatedPattern;
          
          // Move to front if name changed (indicates significant update)
          if (name != null && name != _currentPattern!.name) {
            _patterns.removeAt(index);
            _patterns.insert(0, updatedPattern);
          }
          
          notifyListeners();
        }
        _clearError();
        return true;
      } else {
        _setError('Failed to save pattern');
        return false;
      }
    } catch (e) {
      _setError('Error saving pattern: $e');
      return false;
    }
  }

  // Set current pattern
  Future<void> setCurrentPattern(Pattern pattern) async {
    _currentPattern = pattern;
    await _storageService.setCurrentPatternId(pattern.id);
    notifyListeners();
  }

  void clearCurrentPattern() {
    _currentPattern = null;
    _storageService.setCurrentPatternId('');
    notifyListeners();
  }

  // Delete a pattern
  Future<bool> deletePattern(String patternId) async {
    try {
      final success = await _storageService.deletePattern(patternId);
      
      if (success) {
        _patterns.removeWhere((p) => p.id == patternId);
        
        // If deleted pattern was current, set new current
        if (_currentPattern?.id == patternId) {
          _currentPattern = _patterns.isNotEmpty ? _patterns.first : null;
          await _storageService.setCurrentPatternId(_currentPattern?.id);
        }
        
        notifyListeners();
        _clearError();
        return true;
      } else {
        _setError('Failed to delete pattern');
        return false;
      }
    } catch (e) {
      _setError('Error deleting pattern: $e');
      return false;
    }
  }

  // Duplicate a pattern
  Future<Pattern?> duplicatePattern(String patternId) async {
    try {
      final originalPattern = _patterns.firstWhere((p) => p.id == patternId);
      final now = DateTime.now();
      final dateString = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      
      final duplicatedPattern = Pattern(
        id: now.millisecondsSinceEpoch.toString(),
        name: dateString,
        createdAt: now,
        modifiedAt: now,
        gridSamples: List.from(originalPattern.gridSamples),
        gridColumns: originalPattern.gridColumns,
        gridRows: originalPattern.gridRows,
        samplePaths: List.from(originalPattern.samplePaths),
        sampleNames: List.from(originalPattern.sampleNames),
      );

      final success = await _storageService.savePattern(duplicatedPattern);
      
      if (success) {
        _patterns.insert(0, duplicatedPattern);
        notifyListeners();
        _clearError();
        return duplicatedPattern;
      } else {
        _setError('Failed to duplicate pattern');
        return null;
      }
    } catch (e) {
      _setError('Error duplicating pattern: $e');
      return null;
    }
  }

  // Refresh patterns from storage
  Future<void> refresh() async {
    await _loadPatterns();
    await _loadCurrentPattern();
  }

  // Clear all patterns (for testing/reset)
  Future<bool> clearAllPatterns() async {
    try {
      final success = await _storageService.clearAllData();
      if (success) {
        _patterns.clear();
        _currentPattern = null;
        notifyListeners();
        _clearError();
        return true;
      } else {
        _setError('Failed to clear patterns');
        return false;
      }
    } catch (e) {
      _setError('Error clearing patterns: $e');
      return false;
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
} 