### 🎛️ Node Graph Based Mixing
The simple-mixing callback works but limits us when we want many independent voices that can keep playing while others are replaced.  Miniaudio's *node-graph* API solves this by giving every sound its own node whose output is automatically mixed by the graph.

**What changed natively**
1. A global `ma_node_graph` is created during `miniaudio_init()`.
2. Every slot (now up to **1024** instead of 8) receives its own `ma_data_source_node` that wraps the slot's decoder.
3. The device callback became one line – it just calls `ma_node_graph_read_pcm_frames()` which reads the mixed result from the graph's endpoint (it also keeps the same capture logic for recording).
4. Play/stop now just **un-mute / mute** the node (volume 1.0 ↔ 0.0).  That means:
   • A sound keeps playing across steps until explicitly stopped or naturally ends.  
   • Re-triggering a slot simply rewinds the decoder and unmutes the node – perfectly sample-accurate restarts with no clicks.
5. All slots' resources (decoder, memory, node) are cleaned up in the correct order.  The graph itself is torn down in `miniaudio_cleanup()`.

**Dart / Flutter API impact**
• `MiniaudioLibrary.slotCount` now returns 1024, giving head-room for much larger grids (e.g. 16×48 = 768 cells) and future features.

**Benefits achieved**
• Unlimited simultaneous voices (practically 1024) with individual volume control.
• Built-in clipping prevention and high-quality mixing handled by miniaudio.
• Cleaner, shorter data callback and easier future DSP insertions (filters, delays, etc.) – just insert more nodes!
