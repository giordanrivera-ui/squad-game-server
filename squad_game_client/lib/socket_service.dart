import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;
  final ValueNotifier<bool> isConnected = ValueNotifier(false);

  // Mailbox for private messages + announcements (shared with all screens)
  final ValueNotifier<List<Map<String, dynamic>>> inboxNotifier = ValueNotifier([]);

  void connect(String email, String displayName) {
    if (socket != null && socket!.connected) return;

    socket = IO.io(
      GameConstants.serverUrl,
      IO.OptionBuilder().setTransports(['websocket']).build(),
    );

    socket?.onConnect((_) {
      isConnected.value = true;
      print('✅ Connected to server!');
      socket?.emit(SocketEvents.register, {
        'email': email,
        'displayName': displayName,
      });
    });

    // NEW mailbox listeners
    socket?.on(SocketEvents.privateMessage, (data) {
      if (data is Map<String, dynamic>) {
        final normalized = Map<String, dynamic>.from(data);
        if (!normalized.containsKey('isFromMe')) {
          normalized['isFromMe'] = false;
        }
        final newItem = {
          'type': 'private',
          'data': normalized,
          'timestamp': DateTime.now(),
        };
        inboxNotifier.value = List.from(inboxNotifier.value)..add(newItem);
      }
    });

    socket?.on(SocketEvents.announcement, (text) {
      if (text is String && text.isNotEmpty) {
        final newItem = {
          'type': 'announcement',
          'text': text,
          'timestamp': DateTime.now(),
        };
        inboxNotifier.value = List.from(inboxNotifier.value)..add(newItem);
      }
    });

    socket?.onDisconnect((_) {
      isConnected.value = false;
      print('❌ Disconnected from server');
    });
  }

  void robBank() => socket?.emit(SocketEvents.robBank);
  void sendMessage(String msg) {
    if (msg.isNotEmpty) socket?.emit(SocketEvents.message, msg);
  }
  void travel(String destination) => socket?.emit(SocketEvents.travel, destination);

  // NEW: send private letter
  void sendPrivateMessage(String to, String msg) {
    if (to.isNotEmpty && msg.isNotEmpty) {
      socket?.emit(SocketEvents.privateMessage, { 'to': to, 'msg': msg });
    }
  }

  // NEW: send announcement (for testing / future mods)
  void sendAnnouncement(String text) {
    if (text.isNotEmpty) {
      socket?.emit(SocketEvents.announcement, text);
    }
  }

  void disconnect() {
    socket?.disconnect();
    isConnected.value = false;
  }
}