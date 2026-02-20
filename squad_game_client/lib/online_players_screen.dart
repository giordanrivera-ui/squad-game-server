import 'package:flutter/material.dart';
import 'chat_screen.dart';   // ← NEW import (important!)

class OnlinePlayersScreen extends StatelessWidget {
  final List<String> onlinePlayers;

  const OnlinePlayersScreen({
    super.key,
    required this.onlinePlayers,
  });

  void _showPlayerMenu(BuildContext context, String name) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: Text('View $name\'s Profile'),
            onTap: () {
              Navigator.pop(context);
              _showProfile(context, name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.message),
            title: const Text('Message'),
            onTap: () {
              Navigator.pop(context);           // close menu
              Navigator.push(                   // ← NEW: go straight to full chat
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(partner: name),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add),
            title: const Text('Invite to Operation'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Invite sent to $name!')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showProfile(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("$name's Profile"),
        content: const Text("Profile details will be shown here in the future."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (onlinePlayers.isEmpty) {
      return const Center(
        child: Text(
          'No one is online right now',
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      itemCount: onlinePlayers.length,
      itemBuilder: (context, index) {
        final name = onlinePlayers[index];
        return ListTile(
          leading: const Icon(Icons.person, color: Colors.blue),
          title: Text(name, style: const TextStyle(fontSize: 18)),
          onTap: () => _showPlayerMenu(context, name),
        );
      },
    );
  }
}