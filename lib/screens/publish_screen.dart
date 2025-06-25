import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sequencer_state.dart';

class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _isPublic = true;
  bool _isPublishing = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  List<String> _parseTags(String tagsText) {
    return tagsText
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  Future<void> _publishProject() async {
    if (_titleController.text.trim().isEmpty) {
      _showErrorDialog('Title is required');
      return;
    }

    setState(() {
      _isPublishing = true;
    });

    try {
      final sequencerState = context.read<SequencerState>();
      final success = await sequencerState.publishToDatabase(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        tags: _tagsController.text.trim().isEmpty 
            ? null 
            : _parseTags(_tagsController.text),
        isPublic: _isPublic,
      );

      if (success) {
        if (mounted) {
          _showSuccessDialog();
        }
      } else {
        if (mounted) {
          _showErrorDialog('Failed to publish project. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('An error occurred: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Success!'),
        content: const Text('Your project has been published successfully.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close publish screen
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Publish Project'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        hintText: 'Enter project title',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 100,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Describe your project (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      maxLength: 500,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Tags',
                        hintText: 'electronic, beats, experimental (comma-separated)',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 200,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Privacy settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy Settings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    
                    // Public option
                    Container(
                      decoration: BoxDecoration(
                        color: _isPublic ? Colors.green.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isPublic ? Colors.green : Colors.grey.withOpacity(0.3),
                          width: _isPublic ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.public,
                          color: _isPublic ? Colors.green : Colors.grey,
                        ),
                        title: const Text('Public Project'),
                        subtitle: const Text('Visible to everyone, allows collaboration'),
                        trailing: Radio<bool>(
                          value: true,
                          groupValue: _isPublic,
                          onChanged: (value) {
                            setState(() {
                              _isPublic = true;
                            });
                          },
                        ),
                        onTap: () {
                          setState(() {
                            _isPublic = true;
                          });
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Private option
                    Container(
                      decoration: BoxDecoration(
                        color: !_isPublic ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !_isPublic ? Colors.blue : Colors.grey.withOpacity(0.3),
                          width: !_isPublic ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.lock,
                          color: !_isPublic ? Colors.blue : Colors.grey,
                        ),
                        title: const Text('Private Project'),
                        subtitle: const Text('Only visible to you and invited users'),
                        trailing: Radio<bool>(
                          value: false,
                          groupValue: _isPublic,
                          onChanged: (value) {
                            setState(() {
                              _isPublic = false;
                            });
                          },
                        ),
                        onTap: () {
                          setState(() {
                            _isPublic = false;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Project info
            Consumer<SequencerState>(
              builder: (context, sequencer, child) {
                final loadedSamples = sequencer.loadedSlots.length;
                final gridCells = sequencer.gridSamples.where((s) => s != null).length;
                
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Project Summary',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('BPM:', style: Theme.of(context).textTheme.bodyMedium),
                            Text('${sequencer.bpm}', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Loaded Samples:', style: Theme.of(context).textTheme.bodyMedium),
                            Text('$loadedSamples', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Pattern Cells:', style: Theme.of(context).textTheme.bodyMedium),
                            Text('$gridCells', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Sound Grids:', style: Theme.of(context).textTheme.bodyMedium),
                            Text('${sequencer.numSoundGrids}', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            const Spacer(),
            
            // Publish button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: ElevatedButton(
                onPressed: _isPublishing ? null : _publishProject,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: _isPublishing
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Publishing...'),
                        ],
                      )
                    : const Text(
                        'Publish Project',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            
            // Cancel button
            TextButton(
              onPressed: _isPublishing ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
} 