# Node Graph Viz (PyQt5)

16x16 grid sequencer with diagonal ladder pattern for samples.

- 16x16 grid table layout
- Samples load on diagonal cells: (1,1), (2,2), (3,3)...(16,16) forming a ladder
- Click diagonal cells to load samples
- Time-scaled waveforms extend across multiple cells showing real duration
- Waveforms automatically scale based on BPM and sample length
- Playback moves left-to-right triggering samples at their position
- Grid zoom (0.5x - 5.0x) to scale the entire table
- Tempo adjustable (20-300 BPM) - waveforms adjust in real-time
- Each position uses its own miniaudio node for audio playback
- Optional native audio backend using miniaudio node graph (ctypes binding)

References: [miniaudio manual](https://miniaud.io/docs/manual/index.html), [node graph example](https://miniaud.io/docs/examples/node_graph.html)

## Requirements
- macOS, Python 3.9+
- `uv` package manager
- Clang (for native backend build)

## Quick start (UI only)
```bash
cd /Users/romansmirnov/projects/fortuned/tools/node_graph_viz
uv venv
. .venv/bin/activate
uv pip install -e .
uv run node-graph-viz
```

## Enable native miniaudio backend (audio)
```bash
cd /Users/romansmirnov/projects/fortuned/tools/node_graph_viz/native
chmod +x build.sh
./build.sh
# Exports are optional if the dylib is in native/build
export NODEGRAPH_LIB="$(pwd)/build/libnodegraph.dylib"
```

Then run the app. In the UI, press Start to begin playback; clicking a step under a lane will also trigger that lane via the backend.

Notes:
- The backend uses a simple custom node (mix) feeding the node graph endpoint, following the concepts from the miniaudio node graph documentation and example.
- The UI remains functional without the backend; audio is only active when the dylib is present.
