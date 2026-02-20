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

  // Track unread messages
  final ValueNotifier<bool> hasUnreadMessages = ValueNotifier(false);

  String? _currentEmail;

  List<String> normalLocations = [];
  Map<String, int> travelCosts = {};

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

    socket?.on(SocketEvents.init, (data) {
      if (data is Map) {
        normalLocations = List<String>.from(data['locations'] ?? []);
        travelCosts = Map<String, int>.from(data['travelCosts'] ?? {});
        print('Got locations from server: $normalLocations');
      }
    });

    // Private message received
    socket?.on(SocketEvents.privateMessage, (data) {
      if (data is Map<String, dynamic>) {
        final normalized = Map<String, dynamic>.from(data);
        if (!normalized.containsKey('isFromMe')) normalized['isFromMe'] = false;
        if (!normalized.containsKey('id')) {
          normalized['id'] = DateTime.now().millisecondsSinceEpoch.toString();
        }

        // NEW: Check if already have this message (no duplicates)
        if (inboxNotifier.value.any((m) => m['data']?['id'] == normalized['id'])) return;

        final newItem = <String, dynamic>{
          'type': 'private',
          'data': normalized,
          'timestamp': DateTime.now().toIso8601String(),
          'isRead': false,
        };

        inboxNotifier.value = [newItem, ...inboxNotifier.value];
        _saveMessagesToFirestore();
        _updateUnreadStatus();
      }
    });

    // Announcement from mods
    socket?.on(SocketEvents.announcement, (data) {
      if (data is Map && data['text'] is String && data['text'].isNotEmpty && data['id'] is String) {
        // NEW: Check if already have this announcement
        if (inboxNotifier.value.any((m) => m['id'] == data['id'])) return;

        final newItem = <String, dynamic>{
          'type': 'announcement',
          'text': data['text'],
          'id': data['id'],
          'timestamp': DateTime.now().toIso8601String(),
          'isRead': false,
        };

        inboxNotifier.value = [newItem, ...inboxNotifier.value];
        _saveMessagesToFirestore();
        _updateUnreadStatus();
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

          loaded.sort((a, b) =>
              (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));

          inboxNotifier.value = loaded;
        }
      }

      // NEW: Load big announcements from special box
      final annSnap = await FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('timestamp', descending: true)
          .get();

      for (var annDoc in annSnap.docs) {
        var item = annDoc.data();
        final id = item['id'] ?? annDoc.id; // Use doc id if no id
        item['id'] = id;
        item['type'] = 'announcement';
        item['isRead'] = false; // New ones are unread

        if (!inboxNotifier.value.any((m) => m['id'] == id)) {
          inboxNotifier.value.add(item);
        }
      }

      // Sort all messages by time
      inboxNotifier.value.sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));
      _updateUnreadStatus();
    } catch (e) {
      print('Error loading messages: $e');
      inboxNotifier.value = [];
      _updateUnreadStatus();
    }
  }

  // Update unread status
  void _updateUnreadStatus() {
    hasUnreadMessages.value = inboxNotifier.value.any((msg) => !(msg['isRead'] ?? true));
  }

  // Mark messages as read
  void markAsRead({String? partner, bool announcements = false}) {
    bool changed = false;
    inboxNotifier.value = inboxNotifier.value.map((item) {
      if (announcements && item['type'] == 'announcement' && !(item['isRead'] ?? true)) {
        item['isRead'] = true;
        changed = true;
      } else if (partner != null && item['type'] == 'private') {
        final data = item['data'] as Map<String, dynamic>;
        final bool isFromMe = data['isFromMe'] ?? false;
        final String msgPartner = isFromMe ? (data['to'] ?? '') : (data['from'] ?? '');
        if (msgPartner == partner && !(item['isRead'] ?? true)) {
          item['isRead'] = true;
          changed = true;
        }
      }
      return item;
    }).toList();

    if (changed) {
      _saveMessagesToFirestore();
      _updateUnreadStatus();
    }
  }

  // Delete message
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
    _updateUnreadStatus();
  }

  // Delete conversation
  Future<void> deleteConversation(String partner) async {
    inboxNotifier.value = inboxNotifier.value
        .where((item) {
          if (item['type'] != 'private') return true;
          final data = item['data'] as Map<String, dynamic>;
          final bool isFromMe = data['isFromMe'] ?? false;
          final String msgPartner = isFromMe ? (data['to'] ?? '') : (data['from'] ?? '');
          return msgPartner != partner;
        })
        .toList();
    await _saveMessagesToFirestore();
    _updateUnreadStatus();
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