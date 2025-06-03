import 'dart:ffi';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ffi/ffi.dart';
import 'miniaudio.dart';

void main() {
  initEngine();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Sample Selector')),
        body: SampleSelector(),
      ),
    );
  }
}

class SampleSelector extends StatefulWidget {
  @override
  State<SampleSelector> createState() => _SampleSelectorState();
}

class _SampleSelectorState extends State<SampleSelector> {
  final List<String?> samplePaths = List.filled(8, null);

  void _selectSample(int index) async {
    String? filePath = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    ).then((result) => result?.files.single.path);

    if (filePath != null) {
      setState(() {
        samplePaths[index] = filePath;
      });
    }
  }

  void _playSample(int index) {
    final path = samplePaths[index];
    if (path != null) {
      final cPath = path.toNativeUtf8();
      playSample(cPath);
      malloc.free(cPath);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No sample attached to this button')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: samplePaths.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              ElevatedButton(
                onPressed: () => _selectSample(index),
                child: Text('Attach Sample ${index + 1}'),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => _playSample(index),
                child: Text('Play Sample ${index + 1}'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  samplePaths[index] ?? 'No sample attached',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}