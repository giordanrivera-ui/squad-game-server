import 'package:flutter/material.dart';
import 'socket_service.dart';

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
        builder: (context, messages, child) {
          if (messages.isEmpty) {
            return const Center(
              child: Text(
                'No messages yet.\nSay hi to someone! 👋',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final item = messages[index];
              final String msgId = item['type'] == 'announcement'
                  ? item['id']
                  : (item['data'] as Map)['id'];

              if (item['type'] == 'announcement') {
                return ListTile(
                  leading: const Icon(Icons.campaign, color: Colors.orange, size: 32),
                  title: const Text('📢 Mod Announcement', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(item['text']),
                  tileColor: Colors.orange[50],
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => socketService.deleteMessage(msgId),
                  ),
                );
              } else {
                final data = item['data'] as Map<String, dynamic>;
                final bool isFromMe = data['isFromMe'] ?? false;
                final String label = isFromMe 
                    ? 'To ${data['to']}' 
                    : 'From ${data['from']}';
                return ListTile(
                  leading: Icon(
                    isFromMe ? Icons.arrow_outward : Icons.arrow_back,
                    color: isFromMe ? Colors.green : Colors.blue,
                  ),
                  title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(data['msg'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => socketService.deleteMessage(msgId),
                  ),
                );
              }
            },
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

  // _showNewMessageDialog and _showTestAnnouncementDialog stay EXACTLY the same as before
  // (I didn't change them — just copy them from your current file if you want)
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