// kill_player_screen.dart (UPDATED FILE)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'socket_service.dart';  // Import to access stats/inventory/equip

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

  @override
  void dispose() {
    _searchController.dispose();
    _bulletsController.dispose();
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
          'type': 'alive',  // All results are alive
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

  void _selectPlayer(String name) {
    setState(() {
      _selectedTarget = name;
      _bullets = 0;  // Reset bullets input
      _bulletsController.clear();
    });
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
                        SocketService().equipArmor('weapon', item);  // Equip the selected weapon
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

  @override
    Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        final balance = stats['balance'] ?? 0;
        final canKill = _selectedTarget != null && _bullets > 0 && balance >= 10000;

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
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: canKill ? () {
                                  // For now, does nothing (kill mechanics later)
                                } : null,
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