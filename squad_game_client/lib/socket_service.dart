import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'constants.dart';

class SocketService {
  // This is a "singleton" - it means there is only ONE SocketService in the whole app
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;           // This holds the connection to the server
  final ValueNotifier<bool> isConnected = ValueNotifier(false);

  // This function starts the connection
  void connect(String email, String displayName) {
    if (socket != null && socket!.connected) return; // Already connected? Do nothing

    socket = IO.io(
      GameConstants.serverUrl,
      IO.OptionBuilder().setTransports(['websocket']).build(),
    );

    // When we successfully connect to the server
    socket?.onConnect((_) {
      isConnected.value = true;
      print('✅ Connected to server!');
      socket?.emit(SocketEvents.register, {
        'email': email,
        'displayName': displayName,
      });
    });

    // Listen for messages from the server
    socket?.on(SocketEvents.time, (data) {
      // We will handle this in GameScreen
    });

    socket?.on(SocketEvents.init, (data) {
      // We will handle this in GameScreen
    });

    socket?.on(SocketEvents.updateStats, (data) {
      // We will handle this in GameScreen
    });

    socket?.on(SocketEvents.message, (data) {
      // We will handle this in GameScreen
    });

    socket?.on(SocketEvents.onlinePlayers, (data) {
      // We will handle this in GameScreen
    });

    // If connection is lost
    socket?.onDisconnect((_) {
      isConnected.value = false;
      print('❌ Disconnected from server');
    });
  }

  // Send a rob request
  void robBank() {
    socket?.emit(SocketEvents.robBank);
  }

  // Send a chat message
  void sendMessage(String msg) {
    if (msg.isNotEmpty) {
      socket?.emit(SocketEvents.message, msg);
    }
  }

  // Disconnect when leaving the game
  void disconnect() {
    socket?.disconnect();
    isConnected.value = false;
  }
}