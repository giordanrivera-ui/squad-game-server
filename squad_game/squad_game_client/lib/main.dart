import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;  // Import the tool

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: GameScreen());
  }
}

class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  IO.Socket? socket;  // The "walkie-talkie"
  List<String> messages = [];  // List of chat messages
  TextEditingController _controller = TextEditingController();  // For typing

  @override
  void initState() {
    super.initState();
    // Connect to YOUR server (change to your public IP later)
    socket = IO.io('http://squadgame.ddns.net:3000/', IO.OptionBuilder()  // For now, local test
        .setTransports(['websocket'])  // Use fast connection
        .build());

    socket?.onConnect((_) => setState(() => messages.add('Connected!')));  // Show "Joined"
    socket?.on('message', (data) => setState(() => messages.add(data)));  // Add incoming messages
  }

  @override
  void dispose() {
    socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Simple Game')),
      body: Column(
        children: [
          Expanded(  // Chat area
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) => ListTile(title: Text(messages[index])),
            ),
          ),
          Padding(  // Typing box
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _controller)),
                ElevatedButton(
                  onPressed: () {
                    String msg = _controller.text;
                    socket?.emit('message', msg);  // Send to server
                    _controller.clear();
                  },
                  child: Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}