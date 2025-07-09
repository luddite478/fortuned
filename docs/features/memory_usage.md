### **📊 Memory Usage Tracking**
**Real-time Memory Monitoring:**
- **Per-slot tracking** - Shows memory usage for each loaded sample
- **Total memory display** - Aggregate memory consumption across all slots
- **Memory-only counting** - Only samples loaded in memory mode are tracked
- **Automatic updates** - Memory display refreshes when samples are loaded/unloaded

**Native Implementation:**
- **Precise calculation** - Uses miniaudio's PCM frame data to calculate exact memory usage
- **Format awareness** - Accounts for sample rate, channels, and bit depth
- **Efficient tracking** - Minimal overhead with static memory counters
- **Memory safety** - Proper cleanup and tracking when samples are unloaded