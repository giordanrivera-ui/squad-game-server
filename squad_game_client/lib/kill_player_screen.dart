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
  int? _targetExp;  // For calculating K

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
      if (_searchResults.isEmpty) {
        _searchError = 'No alive players found.';  // Set error if empty
      } else {
        _searchError = '';  // Clear if results
      }
    });
  }

  Future<void> _selectPlayer(String name) async {
    if (_isHitlistMode) {
      _showBountyDialog(name);
    } else {
      setState(() {
        _selectedTarget = name;
        _bullets = 0;
        _bulletsController.clear();
        _targetExp = null;  // Reset
      });

      // Fetch target's exp to calculate K
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
          ],
        );
      },
    );
  }
}