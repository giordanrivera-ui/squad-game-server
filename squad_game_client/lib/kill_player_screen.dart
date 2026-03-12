import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class KillPlayerScreen extends StatefulWidget {
  const KillPlayerScreen({super.key});

  @override
  State<KillPlayerScreen> createState() => _KillPlayerScreenState();
}

class _KillPlayerScreenState extends State<KillPlayerScreen> {
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
      setState(() {
        _searchResults = [];
        _searchError = '';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = '';
    });

    try {
      final searchLower = query.toLowerCase();

      // Query only alive players (dead == false)
      final playersQuery = await FirebaseFirestore.instance
          .collection('players')
          .where('displayNameLower', isGreaterThanOrEqualTo: searchLower)
          .where('displayNameLower', isLessThan: searchLower + '\uf8ff')
          .where('dead', isEqualTo: false)  // Only alive players
          .get();

      setState(() {
        _searchResults = playersQuery.docs.map((doc) => {
          'displayName': doc.data()['displayName'],
          'type': 'alive',  // All are alive
        }).toList();
        _isSearching = false;
        if (_searchResults.isEmpty) {
          _searchError = 'No alive players found.';
        }
      });
    } catch (e) {
      setState(() {
        _searchError = 'Error searching: $e';
        _isSearching = false;
      });
    }
  }

  void _selectPlayerToKill(String name) {
    // For now, just show a message (mechanics later)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected $name to kill. (Mechanics coming soon)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search for alive players to kill',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchPlayers(_searchController.text),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _searchPlayers,
            ),
          ),
          if (_isSearching) const Center(child: CircularProgressIndicator()),
          if (_searchError.isNotEmpty) Center(child: Text(_searchError)),
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('Search for a player above.'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final player = _searchResults[index];
                      final name = player['displayName'] as String;
                      return ListTile(
                        title: Text(name),
                        onTap: () => _selectPlayerToKill(name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}