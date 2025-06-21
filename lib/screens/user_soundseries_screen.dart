import 'package:flutter/material.dart';
import '../services/user_profile_service.dart';

class UserSoundseriesScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const UserSoundseriesScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<UserSoundseriesScreen> createState() => _UserSoundseriesScreenState();
}

class _UserSoundseriesScreenState extends State<UserSoundseriesScreen> {
  List<UserSeries> _soundseries = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSoundseries();
  }

  Future<void> _loadSoundseries() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final soundseries = await UserProfileService.getUserSeries(widget.userId);

      setState(() {
        _soundseries = soundseries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.userName}\'s Soundseries',
          style: const TextStyle(
            color: Color(0xFF374151),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildSoundseriesContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 16),
          const Text(
            'Failed to load soundseries',
            style: TextStyle(
              color: Color(0xFF374151),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Unknown error',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadSoundseries,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundseriesContent() {
    if (_soundseries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note_outlined,
              size: 64,
              color: Color(0xFF9CA3AF),
            ),
            SizedBox(height: 16),
            Text(
              'No soundseries found',
              style: TextStyle(
                color: Color(0xFF374151),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This user hasn\'t created any soundseries yet.',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _soundseries.length,
      itemBuilder: (context, index) {
        return _buildSoundseriesCard(_soundseries[index]);
      },
    );
  }

  Widget _buildSoundseriesCard(UserSeries series) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Play button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(series.coverColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    onPressed: () => _playSoundseries(series),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Title and info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        series.title,
                        style: const TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 14,
                            color: Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(series.duration),
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Status indicators
                if (series.isLocked)
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: Color(0xFF9CA3AF),
                  ),
              ],
            ),
          ),
          
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _viewSoundseriesDetails(series),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openInSequencer(series),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Open'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF374151),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  void _playSoundseries(UserSeries series) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing: ${series.title}')),
    );
  }

  void _viewSoundseriesDetails(UserSeries series) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Fetch detailed soundseries data
      final soundseriesData = await UserProfileService.getSoundSeries(series.id);
      
      // Hide loading
      Navigator.of(context).pop();
      
      // Show details dialog
      _showSoundseriesDetailsDialog(soundseriesData);
      
    } catch (e) {
      // Hide loading
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading details: $e')),
      );
    }
  }

  void _showSoundseriesDetailsDialog(SoundSeriesData data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('BPM: ${data.bpm}'),
              Text('Key: ${data.key}'),
              const SizedBox(height: 16),
              if (data.sources.isNotEmpty && data.sources.first.gridStacks.isNotEmpty) ...[
                const Text(
                  'Grid Pattern:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildGridVisualization(data.sources.first.gridStacks.first),
                const SizedBox(height: 12),
                Text('Created by: ${data.sources.first.gridStacks.first.metadata.user}'),
                Text('BPM: ${data.sources.first.gridStacks.first.metadata.bpm}'),
                Text('Key: ${data.sources.first.gridStacks.first.metadata.key}'),
                Text('Time: ${data.sources.first.gridStacks.first.metadata.timeSignature}'),
              ],
              if (data.sources.isNotEmpty && data.sources.first.samples.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Samples Used:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...data.sources.first.samples.map((sample) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        sample.isPublic ? Icons.public : Icons.lock,
                        size: 14,
                        color: sample.isPublic ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text('${sample.name} (${sample.id})'),
                    ],
                  ),
                )),
              ],
              if (data.renders.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Available Renders:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...data.renders.map((render) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${render.quality} quality (v${render.version})'),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildGridVisualization(GridData gridData) {
    if (gridData.layers.isEmpty) {
      return const Text('No grid data available');
    }
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: gridData.layers.map((layer) {
          return Row(
            children: layer.map((cell) {
              return Expanded(
                child: Container(
                  height: 32,
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: cell.isEmpty 
                        ? const Color(0xFFF9FAFB)
                        : const Color(0xFF374151),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: cell.isEmpty 
                      ? null 
                      : const Icon(
                          Icons.music_note,
                          size: 16,
                          color: Colors.white,
                        ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  void _openInSequencer(UserSeries series) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening ${series.title} in sequencer')),
    );
  }
} 