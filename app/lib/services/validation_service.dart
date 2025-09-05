import 'dart:convert';
import 'package:json_schema/json_schema.dart';

/// Service for validating data against JSON schemas
class ValidationService {
  static final ValidationService _instance = ValidationService._internal();
  factory ValidationService() => _instance;
  ValidationService._internal();

  // Cache for loaded schemas
  final Map<String, JsonSchema> _schemaCache = {};

  /// Load a JSON schema from assets
  Future<JsonSchema?> loadSchema(String schemaName) async {
    if (_schemaCache.containsKey(schemaName)) {
      return _schemaCache[schemaName];
    }

    try {
      // Load schema from assets
      final schemaString = await _loadAsset('schemas/${schemaName}_schema.json');
      final schemaMap = json.decode(schemaString) as Map<String, dynamic>;
      
      final schema = JsonSchema.create(schemaMap);
      _schemaCache[schemaName] = schema;
      
      return schema;
    } catch (e) {
      print('Error loading schema $schemaName: $e');
      return null;
    }
  }

  /// Validate a document against a schema
  Future<bool> validateDocument(String schemaName, Map<String, dynamic> document) async {
    final schema = await loadSchema(schemaName);
    if (schema == null) {
      print('Schema $schemaName not found');
      return false;
    }

    try {
      return schema.validate(document);
    } catch (e) {
      print('Validation error for $schemaName: $e');
      return false;
    }
  }

  /// Validate user data
  Future<bool> validateUser(Map<String, dynamic> userData) async {
    return await validateDocument('users', userData);
  }

  /// Validate thread data
  Future<bool> validateThread(Map<String, dynamic> threadData) async {
    return await validateDocument('threads', threadData);
  }

  /// Validate sample data
  Future<bool> validateSample(Map<String, dynamic> sampleData) async {
    return await validateDocument('samples', sampleData);
  }

  /// Load asset file (you'll need to implement this based on your asset structure)
  Future<String> _loadAsset(String path) async {
    // This is a placeholder - you'll need to implement asset loading
    // based on how you want to include the schema files in your Flutter app
    throw UnimplementedError('Asset loading not implemented');
  }

  /// Clear schema cache
  void clearCache() {
    _schemaCache.clear();
  }
}



