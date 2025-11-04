import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../state/sequencer/table.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_bank.dart';
import '../../ffi/undo_redo_bindings.dart';
import 'debug_snapshot.dart';

/// Snapshot import service for sequencer state
class SnapshotImporter {
  final TableState _tableState;
  final PlaybackState _playbackState;
  final SampleBankState _sampleBankState;

  SnapshotImporter({
    required TableState tableState,
    required PlaybackState playbackState,
    required SampleBankState sampleBankState,
  }) : _tableState = tableState,
       _playbackState = playbackState,
       _sampleBankState = sampleBankState;

  /// Import sequencer state from JSON string
  Future<bool> importFromJson(String jsonString, {Function(String, double)? onProgress}) async {
    try {
      debugPrint('📥 [SNAPSHOT_IMPORT] === STARTING IMPORT FROM JSON ===');

      final dynamic jsonData = json.decode(jsonString);
      if (jsonData is! Map<String, dynamic>) {
        debugPrint('❌ [SNAPSHOT_IMPORT] Invalid JSON structure');
        return false;
      }

      final snapshot = jsonData;
      final source = snapshot['source'] as Map<String, dynamic>;

      // CRITICAL STEP 1: Stop playback completely
      onProgress?.call('Stopping playback...', 0.02);
      debugPrint('🛑 [SNAPSHOT_IMPORT] STEP 1: Stopping playback');
      _playbackState.stop();

      // CRITICAL STEP 2: Reset ALL SunVox patterns (this removes all patterns and clears mappings)
      onProgress?.call('Resetting audio engine...', 0.05);
      debugPrint('🔄 [SNAPSHOT_IMPORT] STEP 2: Resetting ALL SunVox patterns');
      _tableState.resetAllSunVoxPatterns();

      // CRITICAL STEP 3: Clear sample bank
      onProgress?.call('Clearing samples...', 0.08);
      debugPrint('🧹 [SNAPSHOT_IMPORT] STEP 3: Clearing sample bank');
      for (int i = 0; i < 26; i++) {
        _sampleBankState.unloadSample(i);
      }

      // CRITICAL STEP 4: Clear all table cells (WITHOUT syncing to SunVox since patterns are gone)
      onProgress?.call('Clearing table...', 0.1);
      debugPrint('🧹 [SNAPSHOT_IMPORT] STEP 4: Clearing all table cells');
      _clearAllTableCells();

      // CRITICAL STEP 5: Reset sections to section 0 only
      onProgress?.call('Resetting sections...', 0.15);
      debugPrint('🔄 [SNAPSHOT_IMPORT] STEP 5: Resetting to single section');
      final currentSections = _tableState.sectionsCount;
      for (int i = currentSections - 1; i > 0; i--) {
        _tableState.deleteSection(i, undoRecord: false);
      }

      // Now import fresh data

      // STEP 6: Import sample bank
      onProgress?.call('Loading samples...', 0.2);
      debugPrint('📦 [SNAPSHOT_IMPORT] STEP 6: Importing sample bank');
      if (source.containsKey('sample_bank')) {
        final success = await _importSampleBankState(source['sample_bank'] as Map<String, dynamic>);
        if (!success) {
          debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import sample bank state');
          return false;
        }
      }

      // STEP 7: Import table structure and data
      // CRITICAL: Disable automatic SunVox sync during import to avoid syncing to non-existent patterns
      onProgress?.call('Loading table structure...', 0.3);
      debugPrint('📊 [SNAPSHOT_IMPORT] STEP 7: Importing table structure');
      debugPrint('🔇 [SNAPSHOT_IMPORT] Disabling automatic SunVox sync during import');
      _tableState.disableSunvoxSync();
      
      int importedSectionsCount = 1;
      
      try {
        if (source.containsKey('table')) {
          final tableData = source['table'] as Map<String, dynamic>;
          importedSectionsCount = tableData['sections_count'] as int;
          
          final success = _importTableState(tableData);
          if (!success) {
            debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import table state');
            return false;
          }
        }

        // STEP 8: Create SunVox patterns and sync all section data
        // This is THE critical step where we rebuild the entire SunVox pattern structure
        // IMPORTANT: Use the sections count from JSON, not from tableState (which may have stale cached value)
        onProgress?.call('Creating audio patterns...', 0.6);
        debugPrint('🎵 [SNAPSHOT_IMPORT] STEP 8: Creating SunVox patterns and syncing data');
        
        // CRITICAL FIX: Force table state sync to update cached _sectionsCount before syncing to SunVox
        // Without this, _sectionsCount is stale (still 1) and syncSectionToSunVox() fails bounds check for sections 1+
        debugPrint('🔄 [SNAPSHOT_IMPORT] Forcing table state sync to update cached sections count');
        _tableState.syncTableState();
        debugPrint('✅ [SNAPSHOT_IMPORT] Table state synced: ${_tableState.sectionsCount} sections now visible to Dart');
        
        _createAllSunVoxPatterns(importedSectionsCount);
        
      } finally {
        // ALWAYS re-enable automatic SunVox sync, even if import fails
        debugPrint('🔊 [SNAPSHOT_IMPORT] Re-enabling automatic SunVox sync');
        _tableState.enableSunvoxSync();
      }
      
      // STEP 9: Import playback settings
      onProgress?.call('Loading playback settings...', 0.8);
      debugPrint('⚙️ [SNAPSHOT_IMPORT] STEP 9: Importing playback settings');
      if (source.containsKey('playback')) {
        final success = _importPlaybackState(source['playback'] as Map<String, dynamic>);
        if (!success) {
          debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import playback state');
          return false;
        }
      }
      
      // STEP 10: Sync UI state with imported playback state
      onProgress?.call('Finalizing...', 0.9);
      debugPrint('✨ [SNAPSHOT_IMPORT] STEP 10: Syncing UI state');
      // Note: Don't call switchToSection here - it was already called in _importPlaybackState
      // and would override the timeline setup (creating a loop-mode timeline for section 0 only)
      // Sync UI selected section to match playback current section
      _tableState.setUiSelectedSection(_playbackState.currentSection);
      _tableState.setUiSelectedLayer(0);

      onProgress?.call('Clearing undo history...', 0.95);
      debugPrint('🗑️ [SNAPSHOT_IMPORT] STEP 11: Clearing undo/redo history');
      UndoRedoFfi.clear();
      debugPrint('✅ [SNAPSHOT_IMPORT] Undo/redo history cleared (fresh start)');
      
      onProgress?.call('Import complete!', 1.0);
      debugPrint('✅ [SNAPSHOT_IMPORT] === IMPORT COMPLETED SUCCESSFULLY ===');
      
      // Debug: Print final state
      debugPrint('📋 [SNAPSHOT_IMPORT] === FINAL STATE AFTER IMPORT ===');
      SnapshotDebugger.printTableState(_tableState);
      SnapshotDebugger.printSampleBankState(_sampleBankState);
      SnapshotDebugger.printPlaybackState(_playbackState);
      
      return true;

    } catch (e, stackTrace) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Import failed: $e');
      debugPrint('📋 [SNAPSHOT_IMPORT] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Clear all table cells WITHOUT syncing to SunVox (patterns don't exist yet)
  /// Uses efficient bulk clear operation instead of clearing cells one by one
  void _clearAllTableCells() {
    debugPrint('🧹 [SNAPSHOT_IMPORT] Clearing all table cells (bulk operation)');
    _tableState.clearAllCells();
    debugPrint('✅ [SNAPSHOT_IMPORT] Cleared all table cells');
  }

  /// Create SunVox patterns for all sections and sync data
  /// This is called AFTER table structure and cells are imported
  /// sectionsCount: The number of sections from the imported data (not from tableState which may be stale)
  void _createAllSunVoxPatterns(int sectionsCount) {
    debugPrint('🎵 [SNAPSHOT_IMPORT] Creating patterns for $sectionsCount sections');
    
    // For each section, we need to ensure a SunVox pattern exists and is synced
    // The appendSection() and setSectionStepCount() calls already created/resized patterns
    // Now we need to sync the cell data to those patterns
    for (int i = 0; i < sectionsCount; i++) {
      final startStep = _tableState.getSectionStartStep(i);
      final stepCount = _tableState.getSectionStepCount(i);
      
      // Sync this section to SunVox pattern
      // The native code will log detailed info about what gets synced
      debugPrint('  🔄 Section $i: start=$startStep, steps=$stepCount');
      debugPrint('     Syncing to SunVox pattern...');
      _tableState.syncSectionToSunVox(i);
    }
    
    debugPrint('✅ [SNAPSHOT_IMPORT] All patterns created and synced');
  }

  Future<bool> _importSampleBankState(Map<String, dynamic> sampleBankData) async {
    try {
      debugPrint('🎛️ [SNAPSHOT_IMPORT] Importing sample bank state');

      final samples = sampleBankData['samples'] as List<dynamic>;
      if (samples.length != 26) {
        debugPrint('❌ [SNAPSHOT_IMPORT] Invalid sample count: ${samples.length}');
        return false;
      }

      // Clear existing samples first
      for (int i = 0; i < 26; i++) {
        _sampleBankState.unloadSample(i);
      }

      // Import samples
      for (int i = 0; i < samples.length; i++) {
        final sampleData = samples[i] as Map<String, dynamic>;
        final loaded = sampleData['loaded'] as bool;
        final settings = sampleData['settings'] as Map<String, dynamic>?;
        final volume = ((settings?['volume'] ?? 1.0) as num).toDouble();
        final pitch = ((settings?['pitch'] ?? 1.0) as num).toDouble();
        final sampleId = sampleData['sample_id'] as String?;
        final filePath = sampleData['file_path'] as String?;

        if (loaded && sampleId != null && filePath != null) {
          // Try to load the sample using the manifest ID
          final success = await _sampleBankState.loadSample(i, sampleId);
          if (!success) {
            debugPrint('⚠️ [SNAPSHOT_IMPORT] Failed to load sample $i with id $sampleId');
            // Continue with other samples
          }
        }

        // Set volume and pitch regardless of load success
        _sampleBankState.setSampleSettings(i, volume: volume, pitch: pitch);
      }

      debugPrint('✅ [SNAPSHOT_IMPORT] Sample bank state imported');
      return true;

    } catch (e) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Sample bank import failed: $e');
      return false;
    }
  }

  bool _importTableState(Map<String, dynamic> tableData) {
    try {
      debugPrint('📊 [SNAPSHOT_IMPORT] Importing table state');

      final sectionsCount = tableData['sections_count'] as int;
      final sections = tableData['sections'] as List<dynamic>;
      final layers = tableData['layers'] as List<dynamic>? ?? [];
      final tableCells = tableData['table_cells'] as List<dynamic>? ?? [];

      debugPrint('📊 [SNAPSHOT_IMPORT] Sections count: $sectionsCount');
      debugPrint('📊 [SNAPSHOT_IMPORT] Layers data length: ${layers.length}');
      debugPrint('📊 [SNAPSHOT_IMPORT] Table cells rows: ${tableCells.length}');

      if (sectionsCount != sections.length) {
        debugPrint('❌ [SNAPSHOT_IMPORT] Sections count mismatch: expected $sectionsCount, got ${sections.length}');
        return false;
      }

      // Reconcile sections count first to avoid accidental appends
      final currentCount = _tableState.sectionsCount;
      debugPrint('📊 [SNAPSHOT_IMPORT] Current sections: $currentCount, target: $sectionsCount');
      if (currentCount > sectionsCount) {
        debugPrint('🔄 [SNAPSHOT_IMPORT] Deleting extra sections');
        for (int i = currentCount - 1; i >= sectionsCount; i--) {
          _tableState.deleteSection(i, undoRecord: false);
        }
      } else if (currentCount < sectionsCount) {
        debugPrint('🔄 [SNAPSHOT_IMPORT] Adding missing sections');
        for (int i = currentCount; i < sectionsCount; i++) {
          _tableState.appendSection(undoRecord: false);
        }
      }

      // Apply per-section step counts
      debugPrint('🔄 [SNAPSHOT_IMPORT] Setting section step counts');
      for (int i = 0; i < sections.length; i++) {
        final sectionData = sections[i] as Map<String, dynamic>;
        final numSteps = sectionData['num_steps'] as int;
        debugPrint('  Section $i: $numSteps steps');
        _tableState.setSectionStepCount(i, numSteps, undoRecord: false);
      }

      // Import layers using bulk update - CRITICAL: ensure all sections get their layer data
      debugPrint('🔄 [SNAPSHOT_IMPORT] Importing layers for all sections');
      final layersLenFlat = <int>[];
      
      // We must provide layer data for ALL sections (4 layers per section)
      for (int s = 0; s < sectionsCount; s++) {
        if (s < layers.length) {
          final sectionLayers = layers[s] as List<dynamic>;
          debugPrint('  Section $s layers: ${sectionLayers.length} layers');
          
          // Import all 4 layers for this section
          for (int l = 0; l < 4; l++) {
            if (l < sectionLayers.length) {
              final len = (sectionLayers[l] as num).toInt();
              layersLenFlat.add(len);
              debugPrint('    Layer $l: $len columns');
            } else {
              // Default to 4 columns if layer data is missing
              layersLenFlat.add(4);
              debugPrint('    Layer $l: 4 columns (default)');
            }
          }
        } else {
          // If no layer data for this section, use defaults (4 columns per layer)
          debugPrint('  Section $s: using default layer configuration (4 layers x 4 columns)');
          for (int l = 0; l < 4; l++) {
            layersLenFlat.add(4);
          }
        }
      }
      
      if (layersLenFlat.isNotEmpty) {
        debugPrint('🔄 [SNAPSHOT_IMPORT] Applying ${layersLenFlat.length} layer configurations');
        _tableState.updateManyLayers(0, sectionsCount, layersLenFlat);
      }

      // Import table cells individually
      debugPrint('🔄 [SNAPSHOT_IMPORT] Importing table cells');
      int cellsImported = 0;
      for (int step = 0; step < tableCells.length; step++) {
        final row = tableCells[step] as List<dynamic>;
        for (int col = 0; col < row.length && col < _tableState.maxCols; col++) {
          final cellData = row[col] as Map<String, dynamic>;
          final sampleSlot = cellData['sample_slot'] as int;
          
          // Skip empty cells to save processing time
          if (sampleSlot < 0) continue;
          
          final settings = cellData['settings'] as Map<String, dynamic>?;
          final volume = ((settings?['volume'] ?? 1.0) as num).toDouble();
          final pitch = ((settings?['pitch'] ?? 1.0) as num).toDouble();
          
          // Set slot and settings
          _tableState.setCell(step, col, sampleSlot, volume, pitch, undoRecord: false);
          cellsImported++;
        }
      }
      
      debugPrint('✅ [SNAPSHOT_IMPORT] Table state imported: $cellsImported non-empty cells');
      return true;

    } catch (e) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Table import failed: $e');
      return false;
    }
  }

  bool _importPlaybackState(Map<String, dynamic> playbackData) {
    try {
      debugPrint('🎵 [SNAPSHOT_IMPORT] Importing playback state');

      final bpm = playbackData['bpm'] as int;
      final songMode = playbackData['song_mode'] as int;
      final currentSection = playbackData['current_section'] as int;
      final sectionsLoopsNum = playbackData['sections_loops_num'] as List<dynamic>;

      // Set playback parameters
      _playbackState.setBpm(bpm);
      _playbackState.setSongMode(songMode != 0);

      // Note: Region setting would need to be added to PlaybackState if not already available

      // Set section loop counts
      for (int i = 0; i < sectionsLoopsNum.length && i < 64; i++) {
        final loops = sectionsLoopsNum[i] as int;
        _playbackState.setSectionLoopsNum(i, loops);
      }

      // Switch to the saved section
      _playbackState.switchToSection(currentSection);

      debugPrint('✅ [SNAPSHOT_IMPORT] Playback state imported');
      return true;

    } catch (e) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Playback import failed: $e');
      return false;
    }
  }

  /// Validate JSON structure against expected schema
  bool validateJson(String jsonString) {
    try {
      final dynamic jsonData = json.decode(jsonString);
      if (jsonData is! Map<String, dynamic>) return false;

      final schemaVersion = jsonData['schema_version'];
      if (schemaVersion != 1) return false;

      final source = jsonData['source'];
      if (source is! Map<String, dynamic>) return false;

      // Basic validation - check required fields exist
      final requiredModules = ['table', 'playback', 'sample_bank'];
      for (final module in requiredModules) {
        if (!source.containsKey(module)) {
          debugPrint('⚠️ [SNAPSHOT_VALIDATE] Missing module: $module');
          return false;
        }
      }

      return true;

    } catch (e) {
      debugPrint('❌ [SNAPSHOT_VALIDATE] Validation failed: $e');
      return false;
    }
  }

  /// Get snapshot metadata without importing
  Map<String, dynamic>? getSnapshotMetadata(String jsonString) {
    try {
      final dynamic jsonData = json.decode(jsonString);
      if (jsonData is! Map<String, dynamic>) return null;

      final snapshot = jsonData;
      return {
        'id': snapshot['id'],
        'name': snapshot['name'],
        'description': snapshot['description'],
        'created_at': snapshot['created_at'],
        'schema_version': snapshot['schema_version'],
      };

    } catch (e) {
      debugPrint('❌ [SNAPSHOT_METADATA] Failed to get metadata: $e');
      return null;
    }
  }
}
