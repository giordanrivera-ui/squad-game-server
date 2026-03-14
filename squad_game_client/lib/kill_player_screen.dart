// kill_player_screen.dart (UPDATED FILE)
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
  int? _targetExp;  // NEW: To calculate K

  @override
  void initState() {
    super.initState();
    // NEW: Listen for kill result from server
    SocketService().socket?.on('kill-result', _handleKillResult);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bulletsController.dispose();
    SocketService().socket?.off('kill-result', _handleKillResult);
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

      final playersQuery = await FirebaseFirestore.instance
          .collection('players')
          .where('displayNameLower', isGreaterThanOrEqualTo: searchLower)
          .where('displayNameLower', isLessThan: searchLower + '\uf8ff')
          .where('dead', isEqualTo: false)
          .get();

      setState(() {
        _searchResults = playersQuery.docs.map((doc) => {
          'displayName': doc.data()['displayName'],
          'type': 'alive',
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

  Future<void> _selectPlayer(String name) async {
    setState(() {
      _selectedTarget = name;
      _bullets = 0;
      _bulletsController.clear();
      _targetExp = null;  // Reset
    });

    // NEW: Fetch target's exp to calculate K
    try {
      final query = await FirebaseFirestore.instance
          .collection('players')
          .where('displayName', isEqualTo: name)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        setState(() => _targetExp = data['experience'] ?? 0);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading target info: $e')),
      );
    }
  }

  void _showWeaponInventory() {
    final inventory = SocketService().statsNotifier.value['inventory'] ?? [];
    final weapons = inventory.where((item) => (item['type'] as String?) == 'weapon').toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Weapon'),
        content: weapons.isEmpty
            ? const Text('No weapons in inventory.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: weapons.length,
                  itemBuilder: (context, index) {
                    final item = weapons[index];
                    return ListTile(
                      title: Text(item['name'] as String),
                      onTap: () {
                        SocketService().equipArmor('weapon', item);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getEquippedWeaponImage() {
    final equipped = SocketService().statsNotifier.value['weapon'];
    if (equipped == null) return 'assets/weapon-empty.jpg';

    final name = equipped['name'] as String;
    return 'assets/$name.jpg';
  }

  // NEW: Handle kill result from server (success/fail message)
  void _handleKillResult(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      final bool success = data['success'] ?? false;
      final String message = data['message'] ?? (success ? 'Kill successful!' : 'Kill unsuccessful.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      if (success) {
        // Optional: Reset screen or something
        setState(() {
          _selectedTarget = null;
          _bullets = 0;
          _bulletsController.clear();
        });
      }
    }
  }

  // NEW: Attempt kill on button click
  void _attemptKill() {
    if (_selectedTarget == null || _targetExp == null) return;

    // Emit to server (server will calculate/validate)
    SocketService().socket?.emit('attempt-kill', {
      'target': _selectedTarget,
      'bullets': _bullets,
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        final balance = stats['balance'] ?? 0;
        final ownBullets = stats['bullets'] ?? 0;
        final equippedWeapon = stats['weapon'];
        final o = equippedWeapon?['power'] ?? 0;
        final hasWeapon = o > 0;
        final canKill = _selectedTarget != null && 
                        _bullets > 0 && 
                        _bullets <= ownBullets && 
                        balance >= 10000 && 
                        hasWeapon &&
                        _targetExp != null;

        return Column(
          children: [
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
              child: _searchResults.isEmpty && _selectedTarget == null
                  ? const Center(child: Text('Search for a player above'))
                  : _selectedTarget == null
                      ? ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final player = _searchResults[index];
                            final name = player['displayName'] as String;

                            return ListTile(
                              title: Text(name),
                              onTap: () => _selectPlayer(name),
                            );
                          },
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Target: $_selectedTarget', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 20),
                              const Text('Bullets to Use:'),
                              TextField(
                                controller: _bulletsController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'Enter number of bullets',
                                ),
                                onChanged: (value) {
                                  setState(() => _bullets = int.tryParse(value) ?? 0);
                                },
                              ),
                              if (_bullets > ownBullets)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'You don\'t have enough bullets.',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              const Text('Equipped Weapon:'),
                              GestureDetector(
                                onTap: _showWeaponInventory,
                                child: Container(
                                  width: double.infinity,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Image.asset(
                                    _getEquippedWeaponImage(),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              if (!hasWeapon)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'You need to equip a weapon.',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: canKill ? _attemptKill : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: canKill ? Colors.red : Colors.grey,
                                  minimumSize: const Size(double.infinity, 50),
                                ),
                                child: const Text('Kill Player'),
                              ),
                              if (balance < 10000)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Need at least \$10,000 for mobilizing costs.',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}