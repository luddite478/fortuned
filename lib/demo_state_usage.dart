import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'services/app_state_service.dart';

// Example widget showing how to use the Sample Slots state
class SampleSlotStatusWidget extends StatelessWidget {
  const SampleSlotStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final sampleSlots = appState.sampleSlots;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sample Slots Status:'),
            Text('Total Slots: ${SampleSlotsState.maxSlots}'),
            Text('Loaded Slots: ${sampleSlots.loadedSlotsCount}'),
            Text('Playing Slots: ${sampleSlots.playingSlots.length}'),
            Text('Total Memory: ${sampleSlots.formatMemorySize(sampleSlots.totalMemoryUsage)}'),
            Text('Selected Slot: ${sampleSlots.selectedSlotIndex}'),
            Text('Active Bank: ${sampleSlots.activeBank}'),
            
            const SizedBox(height: 16),
            
            // Display individual slot info
            ...List.generate(SampleSlotsState.maxSlots, (index) {
              final slot = sampleSlots.getSlot(index);
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: slot.isPlaying ? Colors.green : 
                           slot.isLoaded ? Colors.blue : Colors.grey,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Text('Slot $index: '),
                    Expanded(
                      child: Text(
                        slot.fileName ?? 'Empty',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (slot.isLoaded) ...[
                      Icon(Icons.check, color: Colors.green, size: 16),
                      Text(' ${sampleSlots.formatMemorySize(slot.memoryUsage)}'),
                    ],
                    if (slot.isPlaying)
                      const Icon(Icons.play_arrow, color: Colors.green, size: 16),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// Example widget showing how to use the Chat state
class ChatStatusWidget extends StatelessWidget {
  const ChatStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final chat = appState.chat;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat Status:'),
            Text('Connected: ${chat.isConnected ? "Yes" : "No"}'),
            Text('Current User: ${chat.currentUserId ?? "None"}'),
            Text('Online Users: ${chat.onlineUsers.length}'),
            Text('Total Conversations: ${chat.conversations.length}'),
            Text('Total Unread: ${chat.totalUnreadCount}'),
            Text('Active Conversation: ${chat.activeConversationId ?? "None"}'),
            
            const SizedBox(height: 16),
            
            // Display online users
            if (chat.onlineUsers.isNotEmpty) ...[
              const Text('Online Users:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...chat.onlineUsers.map((user) => 
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text('• $user'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            
            // Display conversations
            if (chat.conversations.isNotEmpty) ...[
              const Text('Conversations:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...chat.conversationsList.map((conversation) => 
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: conversation.contactId == chat.activeConversationId ? 
                             Colors.blue : Colors.grey,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        conversation.isOnline ? Icons.circle : Icons.circle_outlined,
                        color: conversation.isOnline ? Colors.green : Colors.grey,
                        size: 12,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(conversation.contactName)),
                      Text('${conversation.messages.length} msgs'),
                      if (conversation.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// Example of using the AppStateService
class StateServiceExample extends StatefulWidget {
  const StateServiceExample({Key? key}) : super(key: key);

  @override
  State<StateServiceExample> createState() => _StateServiceExampleState();
}

class _StateServiceExampleState extends State<StateServiceExample> {
  
  void _loadExampleSample() {
    final service = Provider.of<AppStateService>(context, listen: false);
    service.loadSample(0, '/path/to/sample.wav', 'example_sample.wav');
    service.updateSlotLoadStatus(0, true, memoryUsage: 1024 * 1024); // 1MB
  }
  
  void _playSlot(int slotIndex) {
    final service = Provider.of<AppStateService>(context, listen: false);
    service.updateSlotPlayStatus(slotIndex, true);
  }
  
  void _stopSlot(int slotIndex) {
    final service = Provider.of<AppStateService>(context, listen: false);
    service.updateSlotPlayStatus(slotIndex, false);
  }
  
  void _connectToChat() async {
    final service = Provider.of<AppStateService>(context, listen: false);
    final connected = await service.connectChat('user_${DateTime.now().millisecondsSinceEpoch}');
    
    if (connected) {
      // Request online users after connecting
      service.requestOnlineUsers();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to chat')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect to chat')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('State Management Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Sample Slots Demo
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sample Slots Demo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const SampleSlotStatusWidget(),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: _loadExampleSample,
                          child: const Text('Load Example Sample'),
                        ),
                        ElevatedButton(
                          onPressed: () => _playSlot(0),
                          child: const Text('Play Slot 0'),
                        ),
                        ElevatedButton(
                          onPressed: () => _stopSlot(0),
                          child: const Text('Stop Slot 0'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Chat Demo
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Chat Demo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const ChatStatusWidget(),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _connectToChat,
                      child: const Text('Connect to Chat'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 