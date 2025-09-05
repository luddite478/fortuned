import 'export.dart';
import 'import.dart';
import '../../state/sequencer/table.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_bank.dart';

/// Main snapshot service that combines export and import functionality
class SnapshotService {
  final SnapshotExporter _exporter;
  final SnapshotImporter _importer;

  const SnapshotService._(this._exporter, this._importer);

  /// Create a snapshot service with the required state objects
  factory SnapshotService({
    required TableState tableState,
    required PlaybackState playbackState,
    required SampleBankState sampleBankState,
  }) {
    final exporter = SnapshotExporter(
      tableState: tableState,
      playbackState: playbackState,
      sampleBankState: sampleBankState,
    );
    final importer = SnapshotImporter(
      tableState: tableState,
      playbackState: playbackState,
      sampleBankState: sampleBankState,
    );
    return SnapshotService._(exporter, importer);
  }

  /// Export current sequencer state to JSON string
  String exportToJson({
    required String name,
    String? id,
    String? description,
  }) {
    return _exporter.exportToJson(
      name: name,
      id: id,
      description: description,
    );
  }

  /// Import sequencer state from JSON string
  Future<bool> importFromJson(String jsonString) {
    return _importer.importFromJson(jsonString);
  }

  /// Validate JSON structure
  bool validateJson(String jsonString) {
    return _importer.validateJson(jsonString);
  }

  /// Get snapshot metadata without importing
  Map<String, dynamic>? getSnapshotMetadata(String jsonString) {
    return _importer.getSnapshotMetadata(jsonString);
  }
}

/*
USAGE EXAMPLE:

// 1. Create the service (typically in your app initialization)
final snapshotService = SnapshotService(
  tableState: tableState,
  playbackState: playbackState,
  sampleBankState: sampleBankState,
);

// 2. Export current state
final jsonString = snapshotService.exportToJson(
  name: 'My Awesome Beat',
  description: 'Created with the sequencer',
);

// 3. Save to file or send to server
// await File('snapshot.json').writeAsString(jsonString);

// 4. Import from JSON (when loading from file/server)
final success = await snapshotService.importFromJson(jsonString);
if (success) {
  print('Snapshot imported successfully!');
} else {
  print('Failed to import snapshot');
}

// 5. Validate JSON before importing
if (snapshotService.validateJson(jsonString)) {
  // Safe to import
}

// 6. Get metadata without importing
final metadata = snapshotService.getSnapshotMetadata(jsonString);
print('Snapshot: ${metadata?['name']} by ${metadata?['createdAt']}');
*/
