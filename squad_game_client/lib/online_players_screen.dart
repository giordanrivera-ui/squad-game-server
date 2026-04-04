import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'view_profile.dart';
import 'socket_service.dart';
import 'invite_to_special_op_screen.dart';   // ← NEW IMPORT
import 'package:cloud_firestore/cloud_firestore.dart';

class OnlinePlayersScreen extends StatefulWidget {
  final List<String> onlinePlayers;

  const OnlinePlayersScreen({
    super.key,
    required this.onlinePlayers,
  });

  @override
  State<OnlinePlayersScreen> createState() => _OnlinePlayersScreenState();
}

class _OnlinePlayersScreenState extends State<OnlinePlayersScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _searchError = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchPlayers(String query) async {
    if (query.isEmpty) {
      setState(() { _searchResults = []; _searchError = ''; });
      return;
    }

    setState(() { _isSearching = true; _searchError = ''; });

    try {
      final searchLower = query.toLowerCase();

      final playersQuery = await FirebaseFirestore.instance
          .collection('players')
          .where('displayNameLower', isGreaterThanOrEqualTo: searchLower)
          .where('displayNameLower', isLessThan: searchLower + '\uf8ff')
          .get();

      final deadQuery = await FirebaseFirestore.instance
          .collection('deadProfiles')
          .where('displayNameLower', isGreaterThanOrEqualTo: searchLower)
          .where('displayNameLower', isLessThan: searchLower + '\uf8ff')
          .get();

      setState(() {
        _searchResults = [
          ...playersQuery.docs.map((doc) => {'displayName': doc.data()['displayName'], 'type': 'alive'}),
          ...deadQuery.docs.map((doc) => {'displayName': doc.data()['displayName'], 'type': 'dead'}),
        ];
        _isSearching = false;
        if (_searchResults.isEmpty) _searchError = 'No players found.';
      });
    } catch (e) {
      setState(() { _searchError = 'Error searching: $e'; _isSearching = false; });
    }
  }

  void _showPlayerMenu(BuildContext context, String name) {
    final stats = SocketService().statsNotifier.value;
    final String currentDisplayName = (stats['displayName'] ?? '').toString();
    final bool hasActiveSpecialOp = 
    (stats['activeSpecialOperation'] ?? '').toString().isNotEmpty;
    final bool isSelf = name == currentDisplayName;

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
              Navigator.push(
                context, 
                MaterialPageRoute(
                  builder: (_) => ViewProfileScreen(displayName: name)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.message),
            title: const Text('Message'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context, 
                MaterialPageRoute(
                  builder: (_) => ChatScreen(partner: name),
                  ),
                  );
            },
          ),
          if (hasActiveSpecialOp && !isSelf)
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('Invite to Special Operation'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InviteToSpecialOpScreen(targetName: name),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search for players',
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _searchPlayers(_searchController.text)),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: _searchPlayers,
          ),
        ),
        if (_isSearching) const Center(child: CircularProgressIndicator()),
        if (_searchError.isNotEmpty) Center(child: Text(_searchError)),
        if (_searchResults.isNotEmpty)
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final player = _searchResults[index];
                final name = player['displayName'] as String;
                final type = player['type'] as String;
                final displayText = type == 'dead' ? '$name (Dead)' : name;
                return ListTile(
                  title: Text(displayText),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ViewProfileScreen(displayName: name, isDead: type == 'dead'))),
                );
              },
            ),
          ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: widget.onlinePlayers.length,
            itemBuilder: (context, index) {
              final name = widget.onlinePlayers[index];
              return ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: Text(name, style: const TextStyle(fontSize: 18)),
                onTap: () => _showPlayerMenu(context, name),
              );
            },
          ),
        ),
      ],
    );
  }
}