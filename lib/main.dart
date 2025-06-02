import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:ffi/ffi.dart';
import 'miniaudio.dart';

void main() {
  initEngine();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final List<String> samplePaths = List.generate(8, (i) => 'sample_$i.wav');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Simple Tracker')),
        body: TrackerGrid(samplePaths: samplePaths),
      ),
    );
  }
}

class TrackerGrid extends StatefulWidget {
  final List<String> samplePaths;

  const TrackerGrid({required this.samplePaths});

  @override
  State<TrackerGrid> createState() => _TrackerGridState();
}

class _TrackerGridState extends State<TrackerGrid> {
  final int steps = 16;
  late List<List<bool>> grid;

  @override
  void initState() {
    super.initState();
    grid = List.generate(widget.samplePaths.length, (_) => List.filled(steps, false));
  }

  void _trigger(int track, int step) {
    final path = widget.samplePaths[track];
    final cPath = path.toNativeUtf8();
    playSample(cPath);
    malloc.free(cPath);
  }

  void _toggle(int track, int step) {
    setState(() {
      grid[track][step] = !grid[track][step];
    });
  }

  void _playSequence() async {
    for (int step = 0; step < steps; step++) {
      for (int track = 0; track < widget.samplePaths.length; track++) {
        if (grid[track][step]) _trigger(track, step);
      }
      await Future.delayed(Duration(milliseconds: 250));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(onPressed: _playSequence, child: Text('Play')),
        Expanded(
          child: ListView.builder(
            itemCount: widget.samplePaths.length,
            itemBuilder: (context, track) {
              return Row(
                children: List.generate(steps, (step) {
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _toggle(track, step),
                      child: Container(
                        margin: EdgeInsets.all(2),
                        height: 30,
                        color: grid[track][step] ? Colors.green : Colors.grey,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }
}
