import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;
  final ValueNotifier<bool> isConnected = ValueNotifier(false);

  // The permanent mailbox
  final ValueNotifier<List<Map<String, dynamic>>> inboxNotifier = ValueNotifier([]);

  String? _currentEmail;

  void connect(String email, String displayName) {
    if (socket != null && socket!.connected) return;

    _currentEmail = email;

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

    // Private message received
    socket?.on(SocketEvents.privateMessage, (data) {
      if (data is Map<String, dynamic>) {
        final normalized = Map<String, dynamic>.from(data);
        if (!normalized.containsKey('isFromMe')) normalized['isFromMe'] = false;
        if (!normalized.containsKey('id')) {
          normalized['id'] = DateTime.now().millisecondsSinceEpoch.toString();
        }

        final newItem = <String, dynamic>{
          'type': 'private',
          'data': normalized,
          'timestamp': DateTime.now().toIso8601String(),
        };

        // FIXED: type-safe way (no more List<dynamic> error)
        inboxNotifier.value = [newItem, ...inboxNotifier.value];
        _saveMessagesToFirestore();
      }
    });

    // Announcement from mods
    socket?.on(SocketEvents.announcement, (text) {
      if (text is String && text.isNotEmpty) {
        final newItem = <String, dynamic>{
          'type': 'announcement',
          'text': text,
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        };

        // FIXED: type-safe way
        inboxNotifier.value = [newItem, ...inboxNotifier.value];
        _saveMessagesToFirestore();
      }
    });

    socket?.onDisconnect((_) {
      isConnected.value = false;
      print('❌ Disconnected from server');
    });
  }

  // Load old messages from your cloud box
  Future<void> loadMessages() async {
    if (_currentEmail == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(_currentEmail)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['messages'] != null) {
          final loaded = (data['messages'] as List<dynamic>)
              .map((m) => Map<String, dynamic>.from(m as Map<dynamic, dynamic>))
              .toList();

          // Newest on top
          loaded.sort((a, b) =>
              (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));

          inboxNotifier.value = loaded;
          return;
        }
      }
      inboxNotifier.value = [];
    } catch (e) {
      print('Error loading messages: $e');
      inboxNotifier.value = [];
    }
  }

  // Delete only from YOUR box
  Future<void> deleteMessage(String id) async {
    inboxNotifier.value = inboxNotifier.value
        .where((item) {
          if (item['type'] == 'announcement') {
            return item['id'] != id;
          } else {
            return (item['data'] as Map<String, dynamic>)['id'] != id;
          }
        })
        .toList();
    await _saveMessagesToFirestore();
  }

  Future<void> _saveMessagesToFirestore() async {
    if (_currentEmail == null) return;
    try {
      final fullList = inboxNotifier.value
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      await FirebaseFirestore.instance
          .collection('players')
          .doc(_currentEmail)
          .set({'messages': fullList}, SetOptions(merge: true));
    } catch (e) {
      print('Error saving messages: $e');
    }
  }

  void robBank() => socket?.emit(SocketEvents.robBank);
  void sendMessage(String msg) {
    if (msg.isNotEmpty) socket?.emit(SocketEvents.message, msg);
  }
  void travel(String destination) => socket?.emit(SocketEvents.travel, destination);

  void sendPrivateMessage(String to, String msg) {
    if (to.isNotEmpty && msg.isNotEmpty) {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      socket?.emit(SocketEvents.privateMessage, {
        'to': to,
        'msg': msg,
        'id': id
      });
    }
  }

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