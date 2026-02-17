// Updated main.dart - Copy this entire code and replace your old main.dart
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import 'dart:math';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Squad Game',
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  IO.Socket? socket;
  List<String> messages = [];
  TextEditingController _controller = TextEditingController();

  // New: Game stats
  String time = 'Loading...';
  Map<String, dynamic> stats = {'balance': 0, 'health': 100};
  bool cooldown = false;
  Timer? cooldownTimer;

  @override
  void initState() {
    super.initState();
    connectToServer();
  }

  void connectToServer() {
    socket = IO.io('https://squad-game-server.onrender.com', IO.OptionBuilder()
        .setTransports(['websocket'])
        .build());

    socket?.onConnect((_) {
      print('Connected to server!');
      setState(() => messages.add('Connected!'));
    });

    // Listen for UK time updates
    socket?.on('time', (data) {
      if (mounted) setState(() => time = data);
    });

    // Initial player stats
    socket?.on('init', (data) {
      if (mounted) setState(() => stats = Map<String, dynamic>.from(data));
    });

    // Updated stats after rob
    socket?.on('update-stats', (data) {
      if (mounted) setState(() => stats = Map<String, dynamic>.from(data));
    });

    // Chat messages
    socket?.on('message', (data) {
      if (mounted) setState(() => messages.add(data));
    });
  }

  void robBank() {
    if (cooldown || socket == null) return;

    socket?.emit('rob-bank');
    setState(() => cooldown = true);

    // Client-side cooldown timer (60 seconds)
    cooldownTimer = Timer(Duration(seconds: 60), () {
      if (mounted) setState(() => cooldown = false);
    });
  }

  @override
  void dispose() {
    cooldownTimer?.cancel();
    socket?.disconnect();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balance = stats['balance']?.toStringAsFixed(0) ?? '0';
    final health = (stats['health'] ?? 0) / 100.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Squad Game'),
        backgroundColor: Colors.blue[800],
      ),
      body: Column(
        children: [
          // Top: UK Time, Bank Balance, Health Bar
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[900],
            child: Column(
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Bank: \$${balance}',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.green[400],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 12),
                Stack(
                  children: [
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.red[300],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    Container(
                      height: 12,
                      width: (health * MediaQuery.of(context).size.width * 0.8),
                      decoration: BoxDecoration(
                        color: Colors.green[400],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Health: ${stats['health']?.toStringAsFixed(0) ?? '100'}/100',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          // Chat messages (expanded)
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(messages[index]),
                dense: true,
              ),
            ),
          ),
          // Chat input
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(hintText: 'Type message...'),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendMessage,
                  child: Text('Send'),
                ),
              ],
            ),
          ),
          // Rob Bank button
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: cooldown ? null : robBank,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  cooldown ? 'Rob Cooldown (60s)' : '💰 ROB A BANK 💰',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final msg = _controller.text.trim();
    if (msg.isNotEmpty && socket != null) {
      socket?.emit('message', msg);
      _controller.clear();
    }
  }
}