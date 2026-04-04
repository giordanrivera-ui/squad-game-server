import 'package:flutter/material.dart';
import 'socket_service.dart';

class ChatScreen extends StatefulWidget {
  final String partner;

  const ChatScreen({super.key, required this.partner});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // NEW: Mark conversation as read when opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocketService().markAsRead(partner: widget.partner);
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _handleDecline(Map<String, dynamic> inviteData) {
    final String leaderName = inviteData['leader'] ?? 'the leader';
    final String declineMsg = "${SocketService().statsNotifier.value['displayName'] ?? 'A player'} has declined the invitation.";

    SocketService().sendPrivateMessage(leaderName, declineMsg);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You declined the invitation.'), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final socketService = SocketService();

    return Scaffold(
      appBar: AppBar(title: Text('💬 Chat with ${widget.partner}')),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: socketService.inboxNotifier,
        builder: (context, allMessages, child) {
          // Only messages with this friend
          final chatMessages = allMessages.where((item) {
            if (item['type'] != 'private') return false;
            final data = item['data'] as Map<String, dynamic>;
            final bool isFromMe = data['isFromMe'] ?? false;
            return isFromMe 
              ? (data['to'] == widget.partner) 
              : (data['from'] == widget.partner);
          }).toList();

          // Oldest at top for nice chat flow
          chatMessages.sort((a, b) => 
            (a['timestamp'] ?? '').compareTo(b['timestamp'] ?? ''));

          if (chatMessages.isEmpty) {
            return const Center(child: Text('No messages yet. Say hi! 👋'));
          }

          return ListView.builder(
            reverse: true,           // newest message at bottom
            padding: const EdgeInsets.all(12),
            itemCount: chatMessages.length,
            itemBuilder: (context, index) {
              final item = chatMessages[chatMessages.length - 1 - index];
              final data = item['data'] as Map<String, dynamic>;
              final bool isFromMe = data['isFromMe'] ?? false;

              // ==================== SPECIAL INVITATION CARD ====================
              if (data['type'] == 'special_invite') {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${data['leader']} has invited you to occupy the ${data['position']} position in the Special Operation:',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(data['operation'] ?? '', style: const TextStyle(fontSize: 18, color: Colors.orange, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {}, // Accept does nothing for now
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
                                child: const Text('Accept', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _handleDecline(data),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
                                child: const Text('Decline', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              else {
                final String msgText = data['msg'] ?? '';
                final String msgId = data['id'] ?? '';
              
                return Align(
                  alignment: isFromMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isFromMe ? Colors.blue[100] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: isFromMe 
                          ? CrossAxisAlignment.end 
                          : CrossAxisAlignment.start,
                      children: [
                        Text(msgText, style: const TextStyle(fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => socketService.deleteMessage(msgId),
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
          );
        },
      ),

      // Bottom input bar
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(25)),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue, size: 32),
                onPressed: () {
                  final text = _inputController.text.trim();
                  if (text.isNotEmpty) {
                    SocketService().sendPrivateMessage(widget.partner, text);
                    _inputController.clear();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}