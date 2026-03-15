import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'socket_service.dart';

class KillPlayerScreen extends StatefulWidget {
  const KillPlayerScreen({super.key});

  @override
  State<KillPlayerScreen> createState() => _KillPlayerScreenState();
}

class _KillPlayerScreenState extends State<KillPlayerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _bulletsController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _searchError = '';
  String? _selectedTarget;
  int _bullets = 0;
  // NEW: Hitlist mode
  bool _isHitlistMode = false;
  List<Map<String, dynamic>> _hitlist = [];

  @override
  void initState() {
    super.initState();
    SocketService().socket?.on('kill-result', _handleKillResult);
    SocketService().socket?.on('hit-claimed', _handleHitClaimed);
    _loadHitlist();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bulletsController.dispose();
    SocketService().socket?.off('kill-result', _handleKillResult);
    SocketService().socket?.off('hit-claimed', _handleHitClaimed);
    super.dispose();
  }

  // Load live hitlist from Firestore
  Future<void> _loadHitlist() async {
    final snap = await FirebaseFirestore.instance
        .collection('hitlist')
        .where('active', isEqualTo: true)
        .get();

    setState(() {
      _hitlist = snap.docs.map((doc) => {
        'id': doc.id,
        'target': doc.data()['target'],
        'reward': doc.data()['reward'],
      }).toList();
    });
  }

  Future<void> _searchPlayers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);

    final searchLower = query.toLowerCase();
    final querySnap = await FirebaseFirestore.instance
        .collection('players')
        .where('displayNameLower', isGreaterThanOrEqualTo: searchLower)
        .where('displayNameLower', isLessThan: searchLower + '\uf8ff')
        .where('dead', isEqualTo: false)
        .get();

    setState(() {
      _searchResults = querySnap.docs.map((doc) => {
        'displayName': doc.data()['displayName'],
      }).toList();
      _isSearching = false;
    });
  }

  void _selectPlayer(String name) {
    if (_isHitlistMode) {
      _showBountyDialog(name);
    } else {
      setState(() {
        _selectedTarget = name;
        _bullets = 0;
        _bulletsController.clear();
      });
    }
  }

  void _showBountyDialog(String target) {
    final rewardController = TextEditingController();
    int selectedDays = 1;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Place Bounty on $target'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rewardController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reward Amount (\$)'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: selectedDays,
              items: List.generate(7, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} days'))),
              onChanged: (v) => selectedDays = v!,
              decoration: const InputDecoration(labelText: 'Duration'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final reward = int.tryParse(rewardController.text) ?? 0;
              if (reward >= 1000) {
                SocketService().placeHit(target, reward, selectedDays);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Bounty placed on $target!')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Minimum bounty is \$1000')),
                );
              }
            },
            child: const Text('Place Bounty'),
          ),
        ],
      ),
    );
  }

  // Handle normal kill result
  void _handleKillResult(dynamic data) {
    if (data is Map && mounted) {
      final bool success = data['success'] ?? false;
      final String message = data['message'] ?? (success ? 'Kill successful!' : 'Kill unsuccessful.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      if (success) {
        setState(() {
          _selectedTarget = null;
          _bullets = 0;
          _bulletsController.clear();
        });
      }
    }
  }

  // Handle bounty claimed notification
  void _handleHitClaimed(dynamic data) {
    if (data is Map && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You claimed a bounty of \$${data['reward']} for killing ${data['target']}!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // HITLIST SECTION (always at top)
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.red[50],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('HITLIST', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 8),
              if (_hitlist.isEmpty)
                const Text('No active hits right now.', style: TextStyle(color: Colors.grey))
              else
                ..._hitlist.map((hit) => ListTile(
                      title: Text(hit['target'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('\$${hit['reward']} reward'),
                      trailing: const Icon(Icons.whatshot, color: Colors.red),
                    )),
            ],
          ),
        ),

        // Toggle + Search
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Normal Kill', style: TextStyle(fontSize: 16)),
              Switch(
                value: _isHitlistMode,
                onChanged: (v) => setState(() => _isHitlistMode = v),
              ),
              const Text('Place Bounty', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(labelText: 'Search player', border: OutlineInputBorder()),
            onSubmitted: _searchPlayers,
          ),
        ),

        // NEW: Show search error if any
        if (_searchError.isNotEmpty)
          Center(child: Text(_searchError, style: const TextStyle(color: Colors.red))),

        // Search results or normal kill UI
        if (_isSearching)
          const Center(child: CircularProgressIndicator())
        else if (_searchResults.isEmpty && _selectedTarget == null)
          const Center(child: Text('Search for a player above'))
        else if (_selectedTarget == null)
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final player = _searchResults[index];
                final name = player['displayName'] as String;
                return ListTile(
                  title: Text(name),
                  onTap: () => _selectPlayer(name),
                );
              },
            ),
          )
        else
          // Normal kill flow (bullets + weapon + button)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Target: $_selectedTarget', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                const Text('Bullets to Use:'),
                TextField(
                  controller: _bulletsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter number of bullets'),
                  onChanged: (value) => setState(() => _bullets = int.tryParse(value) ?? 0),
                ),
                // NEW: Use _bullets in a check (e.g., show warning if 0)
                if (_bullets == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Enter bullets to proceed.', style: TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 20),
                const Text('Equipped Weapon:'),
                // (Keep your existing weapon selection UI here)
                ElevatedButton(
                  onPressed: _bullets > 0 ? () { /* your attemptKill logic */ } : null,
                  child: const Text('Kill Player'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}