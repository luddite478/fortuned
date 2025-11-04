import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'sample_bank.dart';
import 'playback.dart';

// Temporary sample browser state for the new sequencer implementation
// This integrates the existing sample browser logic with our new sequencer
class SampleBrowserState extends ChangeNotifier {
  bool _isVisible = false;
  bool _isLoading = true;
  List<String> _currentPath = [];
  List<SampleItem> _currentItems = [];
  Map<String, dynamic>? _manifestData;
  int? _targetStep;
  int? _targetCol;
  
  bool get isVisible => _isVisible;
  bool get isLoading => _isLoading;
  List<String> get currentPath => _currentPath;
  List<SampleItem> get currentItems => _currentItems;
  int? get targetStep => _targetStep;
  int? get targetCol => _targetCol;
  
  // Initialize the sample browser with manifest data
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Load samples_manifest.json
      final manifestString = await rootBundle.loadString('samples_manifest.json');
      final fullManifest = json.decode(manifestString);
      
      // Extract the samples section
      if (fullManifest is Map && fullManifest.containsKey('samples')) {
        _manifestData = fullManifest['samples'];
        _refreshCurrentItems();
        debugPrint('📁 Sample browser initialized with ${_manifestData?.keys.length ?? 0} samples');
      } else {
        debugPrint('❌ Invalid manifest structure: no samples key found');
        _manifestData = {};
      }
    } catch (e) {
      debugPrint('❌ Failed to load samples manifest: $e');
      _manifestData = {}; // Empty fallback
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  // Show the sample browser for a specific cell
  void showForCell(int step, int col) {
    _targetStep = step;
    _targetCol = col;
    _isVisible = true;
    notifyListeners();
    debugPrint('📁 Showing sample browser for cell [$step, $col]');
  }
  
  // Show for a sample bank slot (V2 compatibility)
  void showForSlot(int slot) {
    _targetStep = null;
    _targetCol = slot; // Reuse targetCol for slot
    _isVisible = true;
    notifyListeners();
    debugPrint('📁 Showing sample browser for slot $slot');
  }
  
  // Hide the sample browser
  void hide() {
    _isVisible = false;
    _targetStep = null;
    _targetCol = null;
    notifyListeners();
    debugPrint('📁 Sample browser hidden');
  }
  
  // Navigate into a folder
  void navigateToFolder(String folderName) {
    _currentPath.add(folderName);
    _refreshCurrentItems();
    notifyListeners();
    debugPrint('📁 Navigated to: ${_currentPath.join('/')}');
  }
  
  // Navigate back one level
  void navigateBack() {
    if (_currentPath.isNotEmpty) {
      _currentPath.removeLast();
      _refreshCurrentItems();
      notifyListeners();
      debugPrint('📁 Navigated back to: ${_currentPath.join('/')}');
    }
  }
  
  // Select a sample file - returns the full path
  String? selectSample(SampleItem item) {
    if (item.isFolder) return null;
    
    debugPrint('📁 Selected sample: ${item.path}');
    return item.path; // Path is already complete from manifest
  }
  
  // Preview slot constant - use slot 25 (Z) as dedicated preview slot
  static const int _previewSlot = 25;
  
  // Current preview sample ID (if any)
  String? _previewSampleId;
  
  /// Preview a sample by loading it temporarily into preview slot and playing it
  /// Similar to how sound settings preview works
  Future<void> previewSample(SampleItem item, SampleBankState sampleBankState, PlaybackState playbackState) async {
    if (item.isFolder || item.sampleId == null) return;
    
    try {
      // Stop any existing preview first
      playbackState.stopPreview();
      
      // If same sample is already loaded in preview slot, just play it
      if (_previewSampleId == item.sampleId && sampleBankState.isSlotLoaded(_previewSlot)) {
        debugPrint('▶️ [SAMPLE_BROWSER] Reusing preview slot for sample: ${item.sampleId}');
        playbackState.previewSampleSlot(_previewSlot, pitchRatio: 1.0, volume01: 1.0);
        return;
      }
      
      // Load sample into preview slot
      debugPrint('📥 [SAMPLE_BROWSER] Loading sample into preview slot: ${item.sampleId}');
      final success = await sampleBankState.loadSample(_previewSlot, item.sampleId!);
      
      if (success) {
        _previewSampleId = item.sampleId;
        // Wait a tiny bit for sample to be ready, then preview
        await Future.delayed(const Duration(milliseconds: 50));
        playbackState.previewSampleSlot(_previewSlot, pitchRatio: 1.0, volume01: 1.0);
        debugPrint('▶️ [SAMPLE_BROWSER] Preview started for sample: ${item.sampleId}');
      } else {
        debugPrint('❌ [SAMPLE_BROWSER] Failed to load sample for preview: ${item.sampleId}');
      }
    } catch (e) {
      debugPrint('❌ [SAMPLE_BROWSER] Error previewing sample: $e');
    }
  }
  
  /// Stop preview and optionally clean up preview slot
  void stopPreview(PlaybackState playbackState, {bool unload = false}) {
    playbackState.stopPreview();
    if (unload) {
      _previewSampleId = null;
      debugPrint('🛑 [SAMPLE_BROWSER] Preview stopped and slot cleared');
    } else {
      debugPrint('🛑 [SAMPLE_BROWSER] Preview stopped (slot kept for reuse)');
    }
  }
  
  // Refresh current items based on current path
  void _refreshCurrentItems() {
    _currentItems.clear();
    
    if (_manifestData == null) {
      debugPrint('📁 No manifest data available');
      return;
    }
    
    // Build virtual folder structure from flat manifest
    final folders = <String>{};
    final files = <SampleItem>[];
    
    // Get the current path prefix
    final currentPathPrefix = _currentPath.join('/');
    final searchPrefix = currentPathPrefix.isEmpty ? 'samples/' : 'samples/$currentPathPrefix/';
    
    debugPrint('📁 Searching for items with prefix: $searchPrefix');
    
    // Go through all samples in manifest
    int totalSamples = 0;
    int matchingSamples = 0;
    
    for (final entry in _manifestData!.entries) {
      totalSamples++;
      final sampleId = entry.key;
      final sampleData = entry.value;
      
      if (sampleData is Map && sampleData.containsKey('path')) {
        final fullPath = sampleData['path'] as String;
        
        // Check if this sample is in the current directory
        if (fullPath.startsWith(searchPrefix)) {
          matchingSamples++;
          final relativePath = fullPath.substring(searchPrefix.length);
          final pathParts = relativePath.split('/');
          
          if (pathParts.length == 1) {
            // This is a file in current directory
            files.add(SampleItem(
              name: pathParts[0],
              isFolder: false,
              path: fullPath,
              sampleId: sampleId,
            ));
          } else if (pathParts.isNotEmpty) {
            // This is in a subdirectory
            folders.add(pathParts[0]);
          }
        }
      }
    }
    
    // Add folders first (sorted)
    final sortedFolders = folders.toList()..sort();
    for (final folder in sortedFolders) {
      _currentItems.add(SampleItem(
        name: folder,
        isFolder: true,
        path: '$searchPrefix$folder',
      ));
    }
    
    // Add files (sorted by name)
    files.sort((a, b) => a.name.compareTo(b.name));
    _currentItems.addAll(files);
    
    debugPrint('📁 Refreshed items for path: ${_currentPath.join('/')}');
    debugPrint('📁 Total samples in manifest: $totalSamples');
    debugPrint('📁 Matching samples: $matchingSamples');
    debugPrint('📁 Found ${folders.length} folders, ${files.length} files');
    debugPrint('📁 Current items count: ${_currentItems.length}');
    
    notifyListeners();
  }
}

// Sample item data class
class SampleItem {
  final String name;
  final bool isFolder;
  final String path;
  final String? sampleId; // ID from manifest for files
  
  SampleItem({
    required this.name,
    required this.isFolder,
    required this.path,
    this.sampleId,
  });
  
  @override
  String toString() => 'SampleItem(name: $name, isFolder: $isFolder, path: $path, sampleId: $sampleId)';
}
