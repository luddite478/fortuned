import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../state/sequencer/table.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_bank.dart';

/// Snapshot import service for sequencer state
class SnapshotImporter {
  final TableState _tableState;
  final PlaybackState _playbackState;
  final SampleBankState _sampleBankState;

  const SnapshotImporter({
    required TableState tableState,
    required PlaybackState playbackState,
    required SampleBankState sampleBankState,
  }) : _tableState = tableState,
       _playbackState = playbackState,
       _sampleBankState = sampleBankState;

  /// Import sequencer state from JSON string
  Future<bool> importFromJson(String jsonString) async {
    try {
      debugPrint('📥 [SNAPSHOT_IMPORT] Starting import from JSON');

      final dynamic jsonData = json.decode(jsonString);
      if (jsonData is! Map<String, dynamic>) {
        debugPrint('❌ [SNAPSHOT_IMPORT] Invalid JSON structure');
        return false;
      }

      final snapshot = jsonData;
      final source = snapshot['source'] as Map<String, dynamic>;

      // Import in order: sample_bank -> table -> playback
      // This order ensures dependencies are resolved correctly

      if (source.containsKey('sample_bank')) {
        final success = await _importSampleBankState(source['sample_bank'] as Map<String, dynamic>);
        if (!success) {
          debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import sample bank state');
          return false;
        }
      }

      if (source.containsKey('table')) {
        final success = _importTableState(source['table'] as Map<String, dynamic>);
        if (!success) {
          debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import table state');
          return false;
        }
      }

      if (source.containsKey('playback')) {
        final success = _importPlaybackState(source['playback'] as Map<String, dynamic>);
        if (!success) {
          debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import playback state');
          return false;
        }
      }

      debugPrint('✅ [SNAPSHOT_IMPORT] Import completed successfully');
      return true;

    } catch (e) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Import failed: $e');
      return false;
    }
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

      if (sectionsCount != sections.length) {
        debugPrint('❌ [SNAPSHOT_IMPORT] Sections count mismatch');
        return false;
      }

      // Reconcile sections count first to avoid accidental appends
      final currentCount = _tableState.sectionsCount;
      if (currentCount > sectionsCount) {
        for (int i = currentCount - 1; i >= sectionsCount; i--) {
          _tableState.deleteSection(i, undoRecord: false);
        }
      } else if (currentCount < sectionsCount) {
        for (int i = currentCount; i < sectionsCount; i++) {
          _tableState.appendSection(undoRecord: false);
        }
      }

      // Apply per-section step counts
      for (int i = 0; i < sections.length; i++) {
        final sectionData = sections[i] as Map<String, dynamic>;
        final numSteps = sectionData['num_steps'] as int;
        _tableState.setSectionStepCount(i, numSteps, undoRecord: false);
      }

      // Import layers using bulk update
      final layersLenFlat = <int>[];
      for (int s = 0; s < layers.length && s < sectionsCount; s++) {
        final sectionLayers = layers[s] as List<dynamic>;
        for (int l = 0; l < sectionLayers.length && l < 4; l++) {
          final len = sectionLayers[l] as int;
          layersLenFlat.add(len);
        }
      }
      if (layersLenFlat.isNotEmpty) {
        _tableState.updateManyLayers(0, sectionsCount, layersLenFlat);
      }

      // Import table cells individually
      for (int step = 0; step < tableCells.length; step++) {
        final row = tableCells[step] as List<dynamic>;
        for (int col = 0; col < row.length && col < _tableState.maxCols; col++) {
          final cellData = row[col] as Map<String, dynamic>;
          final sampleSlot = cellData['sample_slot'] as int;
          final settings = cellData['settings'] as Map<String, dynamic>?;
          final volume = ((settings?['volume'] ?? 1.0) as num).toDouble();
          final pitch = ((settings?['pitch'] ?? 1.0) as num).toDouble();
          // Set slot and settings
          _tableState.setCell(step, col, sampleSlot, volume, pitch, undoRecord: false);
        }
      }

      debugPrint('✅ [SNAPSHOT_IMPORT] Table state imported');
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
