import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

class SampleBrowserScreen extends StatefulWidget {
  final int slotIndex;
  final Function(String path, String name) onSampleSelected;
  
  const SampleBrowserScreen({
    Key? key,
    required this.slotIndex,
    required this.onSampleSelected,
  }) : super(key: key);
  
  @override
  State<SampleBrowserScreen> createState() => _SampleBrowserScreenState();
}

class _SampleBrowserScreenState extends State<SampleBrowserScreen> {
  List<String> _currentPath = [];
  List<SampleItem> _currentItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRootSamples();
  }

  Future<void> _loadRootSamples() async {
    setState(() => _isLoading = true);
    
    try {
      // Load and parse the asset manifest to discover all sample files
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      
      print('🔍 Total assets in manifest: ${manifestMap.keys.length}');
      
      // Debug: Show all assets that start with 'samples'
      final allSampleAssets = manifestMap.keys
          .where((path) => path.startsWith('samples/'))
          .toList();
      
      print('📁 All sample-related assets: ${allSampleAssets.length}');
      for (final path in allSampleAssets) {
        print('  📄 $path');
      }
      
      // Get all sample file paths (only audio files)
      final samplePaths = manifestMap.keys
          .where((path) => path.startsWith('samples/') && _isAudioFile(path))
          .toList();
      
      print('🎵 Audio files found: ${samplePaths.length}');
      for (final path in samplePaths) {
        print('  🎶 $path');
      }
      
      // Build dynamic folder structure
      _currentItems = _buildDynamicStructure(samplePaths, _currentPath);
      
    } catch (e) {
      print('Error loading samples: $e');
      _currentItems = [];
    }
    
    setState(() => _isLoading = false);
  }

  List<SampleItem> _buildDynamicStructure(List<String> allSamplePaths, List<String> currentPath) {
    final currentPathPrefix = currentPath.isEmpty ? 'samples/' : 'samples/${currentPath.join('/')}/';
    print('🔍 Building structure for path: $currentPath (prefix: "$currentPathPrefix")');
    
    final folders = <String>{};
    final files = <SampleItem>[];
    
    for (final samplePath in allSamplePaths) {
      if (samplePath.startsWith(currentPathPrefix)) {
        // Remove the current path prefix to get relative path
        final relativePath = samplePath.substring(currentPathPrefix.length);
        final pathParts = relativePath.split('/');
        
        if (pathParts.length == 1 && pathParts[0].isNotEmpty) {
          // It's a file in the current directory
          files.add(SampleItem(
            name: pathParts[0],
            path: samplePath,
            isFolder: false,
            size: 0,
          ));
        } else if (pathParts.length > 1 && pathParts[0].isNotEmpty) {
          // It's a file in a subdirectory, so we add the subdirectory as a folder
          folders.add(pathParts[0]);
        }
      }
    }
    
    // Convert folders to SampleItems
    final folderItems = folders.map((folderName) => SampleItem(
      name: folderName,
      path: '', // Folders don't have file paths
      isFolder: true,
      size: 0,
    )).toList();
    
    // Sort everything alphabetically
    folderItems.sort((a, b) => a.name.compareTo(b.name));
    files.sort((a, b) => a.name.compareTo(b.name));
    
    final result = [...folderItems, ...files];
    print('📁 Found ${folders.length} folders and ${files.length} files');
    
    return result;
  }

  bool _isAudioFile(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return ['wav', 'mp3', 'aac', 'm4a', 'flac', 'ogg'].contains(ext);
  }

  void _navigateToFolder(String folderName) {
    setState(() {
      _currentPath.add(folderName);
      _isLoading = true;
    });
    _loadRootSamples();
  }

  void _navigateBack() {
    if (_currentPath.isNotEmpty) {
      setState(() {
        _currentPath.removeLast();
        _isLoading = true;
      });
      _loadRootSamples();
    }
  }

  Future<void> _pickExternalFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        widget.onSampleSelected(
          result.files.single.path!,
          result.files.single.name,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _selectSample(SampleItem item) {
    if (item.isFolder) {
      _navigateToFolder(item.name);
    } else {
      widget.onSampleSelected(item.path, item.name);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SAMPLE BROWSER',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            Text(
              'SLOT ${String.fromCharCode(65 + widget.slotIndex)}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.cyanAccent,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_currentPath.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.folder_open, color: Colors.orangeAccent),
              onPressed: _navigateBack,
              tooltip: 'Back to parent folder',
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Colors.grey.shade900,
            ],
          ),
        ),
        child: Column(
          children: [
            // Current path breadcrumb
            if (_currentPath.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Text(
                  'samples/${_currentPath.join('/')}',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
              ),
            
            // External file picker button
            Container(
              margin: const EdgeInsets.all(16),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickExternalFile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.folder_open),
                label: const Text(
                  'BROWSE DEVICE FILES',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            
            // Bundled samples section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.library_music, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  const Text(
                    'BUNDLED SAMPLES',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_currentItems.length} items',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Sample list
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.cyanAccent),
                    )
                  : _currentItems.isEmpty
                      ? const Center(
                          child: Text(
                            'No samples found in this folder',
                            style: TextStyle(
                              color: Colors.grey,
                              fontFamily: 'monospace',
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _currentItems.length,
                          itemBuilder: (context, index) {
                            final item = _currentItems[index];
                            return _buildSampleItem(item);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSampleItem(SampleItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1f2937),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.isFolder ? Colors.orangeAccent.withOpacity(0.3) : Colors.cyanAccent.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: item.isFolder 
            ? [
                BoxShadow(
                  color: Colors.orangeAccent.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.isFolder ? Colors.orangeAccent : Colors.cyanAccent,
          child: Icon(
            item.isFolder ? Icons.folder : Icons.audio_file,
            color: Colors.black,
          ),
        ),
        title: Text(
          item.name,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.isFolder ? 'Folder' : _getFileExtension(item.name).toUpperCase(),
          style: TextStyle(
            color: item.isFolder ? Colors.orangeAccent : Colors.cyanAccent,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        trailing: Icon(
          item.isFolder ? Icons.chevron_right : Icons.play_arrow,
          color: item.isFolder ? Colors.orangeAccent : Colors.cyanAccent,
        ),
        onTap: () => _selectSample(item),
      ),
    );
  }

  String _getFileExtension(String filename) {
    return filename.split('.').last;
  }
}

// Data model for sample items
class SampleItem {
  final String name;
  final String path;
  final bool isFolder;
  final int size;

  SampleItem({
    required this.name,
    required this.path,
    required this.isFolder,
    required this.size,
  });
}

 