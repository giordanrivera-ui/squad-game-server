import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final socketService = SocketService();

    // NEW: Mark announcements as read when opening this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      socketService.markAsRead(announcements: true);
    });

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: socketService.inboxNotifier,
      builder: (context, allMessages, child) {
        if (allMessages.isEmpty) {
          return const Center(
            child: Text(
              'No messages yet.\nSay hi to someone! 👋',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        final announcements = allMessages.where((m) => m['type'] == 'announcement').toList();
        final privateMessages = allMessages.where((m) => m['type'] == 'private').toList();
        final conversations = _buildConversations(privateMessages);

        return ListView(
          children: [
            if (announcements.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('📢 Mod Announcements', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ...announcements.map((item) {
                final id = item['id'] ?? '';
                return ListTile(
                  leading: const Icon(Icons.campaign, color: Colors.orange, size: 32),
                  title: const Text('Mod Announcement', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(item['text'] ?? ''),
                  tileColor: Colors.orange[50],
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => socketService.deleteMessage(id),
                  ),
                );
              }),
              const Divider(),
            ],

            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('💬 Conversations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (conversations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No conversations yet')),
              )
            else
              ...conversations.map((conv) {
                final partner = conv['partner'] as String;
                final lastMsg = conv['lastPreview'] as String;
                return ListTile(
                  leading: const Icon(Icons.person, color: Colors.blue, size: 36),
                  title: Text(partner, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  subtitle: Text(lastMsg.length > 40 ? '${lastMsg.substring(0, 37)}...' : lastMsg),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(partner: partner),
                      ),
                    );
                  },
                  trailing: IconButton(  // NEW: Trash icon for deleting conversation
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _showDeleteConfirmation(context, partner),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  // NEW: Confirmation dialog for deleting conversation
  void _showDeleteConfirmation(BuildContext context, String partner) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text('Are you sure you want to delete all messages with $partner? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              SocketService().deleteConversation(partner);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Conversation with $partner deleted.')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildConversations(List<Map<String, dynamic>> privateMsgs) {
    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (var item in privateMsgs) {
      final data = item['data'] as Map<String, dynamic>;
      final bool isFromMe = data['isFromMe'] ?? false;
      final String partner = isFromMe ? (data['to'] ?? '') : (data['from'] ?? '');

      if (partner.isEmpty) continue;
      groups.putIfAbsent(partner, () => []).add(item);
    }

    final List<Map<String, dynamic>> result = [];
    groups.forEach((partner, msgs) {
      msgs.sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));

      // NEW: Safe preview that works for both normal messages AND special invites
      final rawMsg = msgs.first['data']['msg'];
      String lastPreview;

      if (rawMsg is String) {
        lastPreview = rawMsg;
      } else if (rawMsg is Map && rawMsg['type'] == 'special_invite') {
        lastPreview = "🎟️ Invited you to ${_getOperationShortName(rawMsg['operation'])} as ${rawMsg['position']}";
      } else {
        lastPreview = "Special message";
      }

      result.add({
        'partner': partner,
        'lastPreview': lastPreview,
        'lastTimestamp': msgs.first['timestamp'] ?? '',
      });
    });

    result.sort((a, b) => (b['lastTimestamp'] ?? '').compareTo(a['lastTimestamp'] ?? ''));
    return result;
  }

  // Tiny helper for nice preview text
  String _getOperationShortName(String? op) {
    if (op == null) return 'Special Op';
    if (op.contains('cartel')) return 'Cartel Raid';
    if (op.contains('Bank')) return 'Bank Heist';
    if (op.contains('Siege')) return 'Military Siege';
    return op;
  }
}