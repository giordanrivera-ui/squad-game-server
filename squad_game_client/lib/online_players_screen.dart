import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'view_profile.dart';

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

  // In online_players_screen.dart (update _showProfile method)
  void _showProfile(BuildContext context, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewProfileScreen(displayName: name),
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