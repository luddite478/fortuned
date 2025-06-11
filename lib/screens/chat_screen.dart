import 'package:flutter/material.dart';
import '../services/chat_client.dart';

class ChatTestScreen extends StatefulWidget {
  final String clientId;
  
  const ChatTestScreen({Key? key, required this.clientId}) : super(key: key);
  
  @override
  State<ChatTestScreen> createState() => _ChatTestScreenState();
}

class _ChatTestScreenState extends State<ChatTestScreen> {
  late ChatClient _chatClient;
  
  @override
  void initState() {
    super.initState();
    _chatClient = ChatClient();
    _setupListeners();
    _connectToServer();
  }
  
  void _setupListeners() {
    // Listen for connection status
    _chatClient.connectionStream.listen((connected) {
      if (connected) {
        _showConnectionPopup('✅ Connected Successfully!', Colors.green);
      } else {
        _showConnectionPopup('❌ Disconnected', Colors.red);
      }
    });
    
    // Listen for errors
    _chatClient.errorStream.listen((error) {
      _showConnectionPopup('⚠️ Error: $error', Colors.orange);
    });
    
    // Listen for incoming messages (optional - just for testing)
    _chatClient.messageStream.listen((message) {
      print('📨 Received: ${message.from}: ${message.message}');
    });
  }
  
  void _showConnectionPopup(String message, Color color) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Connection Status'),
          content: Text(message),
          backgroundColor: color.withOpacity(0.1),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
    
    // Auto-dismiss after 2 seconds
    Future.delayed(Duration(seconds: 2), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }
  
  Future<void> _connectToServer() async {
    final success = await _chatClient.connect(widget.clientId);
    if (!success) {
      _showConnectionPopup('❌ Failed to connect to server', Colors.red);
    }
  }
  
  @override
  void dispose() {
    _chatClient.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat Test: ${widget.clientId}'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 100,
              color: Colors.grey,
            ),
            SizedBox(height: 20),
            Text(
              'Chat Client Service Running',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 10),
            Text(
              'Client ID: ${widget.clientId}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            SizedBox(height: 20),
            Text(
              'Connection status will show as popup',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
} 