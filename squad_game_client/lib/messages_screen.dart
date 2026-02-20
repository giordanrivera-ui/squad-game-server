import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'chat_screen.dart';   // ← NEW import

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final socketService = SocketService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📬 Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: 'Test Mod Announcement',
            onPressed: () => _showTestAnnouncementDialog(context),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
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

          // Separate announcements and private messages
          final announcements = allMessages.where((m) => m['type'] == 'announcement').toList();
          final privateMessages = allMessages.where((m) => m['type'] == 'private').toList();

          // Build conversation list (one tile per friend)
          final conversations = _buildConversations(privateMessages);

          return ListView(
            children: [
              // === ANNOUNCEMENTS SECTION ===
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

              // === CONVERSATIONS SECTION (what you asked for) ===
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
                  );
                }),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewMessageDialog(context),
        child: const Icon(Icons.add_comment),
        tooltip: 'New Message',
      ),
    );
  }

  // Helper: group messages by friend
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
      // newest message first for preview
      msgs.sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));

      result.add({
        'partner': partner,
        'lastPreview': msgs.first['data']['msg'] ?? '',
        'lastTimestamp': msgs.first['timestamp'] ?? '',
      });
    });

    // Sort conversations by most recent message
    result.sort((a, b) => (b['lastTimestamp'] ?? '').compareTo(a['lastTimestamp'] ?? ''));

    return result;
  }

  // === SAME DIALOGS AS BEFORE (no change) ===
  void _showNewMessageDialog(BuildContext context) {
    final toController = TextEditingController();
    final msgController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Private Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: toController,
              decoration: const InputDecoration(labelText: 'To (exact player name)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: msgController,
              decoration: const InputDecoration(labelText: 'Your message'),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final to = toController.text.trim();
              final msg = msgController.text.trim();
              if (to.isNotEmpty && msg.isNotEmpty) {
                SocketService().sendPrivateMessage(to, msg);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Message sent to $to!')),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showTestAnnouncementDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test Mod Announcement'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Announcement text'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                SocketService().sendAnnouncement(text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Announcement sent to everyone!')),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}