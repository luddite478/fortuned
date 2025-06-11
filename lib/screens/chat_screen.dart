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
      backgroundColor: Colors.purple.shade900,
      appBar: AppBar(
        title: Text(
          '🚀 WEBSOCKET CHAT TEST 🚀',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 2,
          ),
        ),
        backgroundColor: Colors.purple,
        elevation: 10,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple.shade900,
              Colors.purple.shade700,
              Colors.purple.shade500,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated chat icon
              AnimatedContainer(
                duration: Duration(seconds: 2),
                curve: Curves.elasticOut,
                child: Icon(
                  Icons.chat_bubble,
                  size: 150,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 30),
              
              // Bright title
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      '✅ CHAT CLIENT ACTIVE!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Client ID: ${widget.clientId}',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.purple.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 15),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '🔌 WebSocket connection will show popup',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.purple.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 40),
              
              // Pulsing indicator
              AnimatedContainer(
                duration: Duration(milliseconds: 1000),
                curve: Curves.easeInOut,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.yellow,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.yellow.withOpacity(0.6),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.wifi,
                    size: 50,
                    color: Colors.purple.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 