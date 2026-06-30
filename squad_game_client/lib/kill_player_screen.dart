import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'socket_service.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'game_header.dart';

class KillPlayerScreen extends StatefulWidget {
  final String time;
  final VoidCallback onMenuPressed;

  const KillPlayerScreen({
    super.key,
    required this.time,
    required this.onMenuPressed,
  });

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

  bool _isHitlistMode = false;
  List<Map<String, dynamic>> _hitlist = [];
  Timer? _hitlistTimer;

  void _onHitlistUpdate(dynamic data) {
    _loadHitlist();
  }

  @override
  void initState() {
    super.initState();
    SocketService().socket?.on('kill-result', _handleKillResult);
    SocketService().socket?.on('hit-claimed', _handleHitClaimed);
    _loadHitlist();
    SocketService().socket?.on('hitlist-update', _onHitlistUpdate);

    _hitlistTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _hitlist.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bulletsController.dispose();
    SocketService().socket?.off('kill-result', _handleKillResult);
    SocketService().socket?.off('hit-claimed', _handleHitClaimed);
    _hitlistTimer?.cancel();
    SocketService().socket?.off('hitlist-update', _onHitlistUpdate);
    super.dispose();
  }

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
        'endTime': doc.data()['endTime'],
      }).where((hit) => hit['endTime'] > DateTime.now().millisecondsSinceEpoch)
      .toList();
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
      _searchError = _searchResults.isEmpty ? 'No alive players found.' : '';
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
      });
    }
  }

  void _showBountyDialog(String target) {
    final rewardController = TextEditingController();
    String selectedOption = '5 Minutes';

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
              inputFormatters: [ThousandsFormatter()],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedOption,
              items: ['5 Minutes', '1 Day', '2 Days', '3 Days', '4 Days', '5 Days', '6 Days', '7 Days']
                  .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                  .toList(),
              onChanged: (v) => selectedOption = v!,
              decoration: const InputDecoration(labelText: 'Duration'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final cleanReward = rewardController.text.replaceAll(',', '');
              final reward = int.tryParse(cleanReward) ?? 0;

              if (reward >= 1000) {
                final days = selectedOption == '5 Minutes' 
                    ? 0 
                    : int.parse(selectedOption.split(' ')[0]);
                final durationMinutes = selectedOption == '5 Minutes' ? 5 : days * 1440;

                SocketService().placeHit(target, reward, durationMinutes);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Bounty placed on $target!')),
                );
                _searchController.clear();
                setState(() => _searchResults = []);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  String _getEquippedWeaponImage() {
    final equipped = SocketService().statsNotifier.value['weapon'];
    if (equipped == null) return 'assets/weapon-empty.jpg';
    return 'assets/${equipped['name']}.jpg';
  }

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

  void _handleHitClaimed(dynamic data) {
    if (data is Map && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You claimed a bounty of \$${data['reward']} for killing ${data['target']}!')),
      );
    }
  }

  void _attemptKill() {
    if (_selectedTarget == null) return;

    SocketService().socket?.emit('attempt-kill', {
      'target': _selectedTarget,
      'bullets': _bullets,
    });
  }

  String _formatRemainingTime(int endTimeMs) {
    final remainingMs = endTimeMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return '00:00:00';

    final hours = (remainingMs ~/ 3600000).toString().padLeft(3, '0');
    final mins = ((remainingMs % 3600000) ~/ 60000).toString().padLeft(2, '0');
    final secs = ((remainingMs % 60000) ~/ 1000).toString().padLeft(2, '0');
    return '$hours:$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            // ==================== GAME HEADER ====================
            GameHeader(
              statsNotifier: SocketService().statsNotifier,
              time: widget.time,
              onMenuPressed: widget.onMenuPressed,
            ),

            // ==================== CONTENT ====================
            Expanded(
              child: SafeArea(
                top: false,
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                  child: ValueListenableBuilder<Map<String, dynamic>>(
                    valueListenable: SocketService().statsNotifier,
                    builder: (context, stats, child) {
                      final balance = stats['balance'] ?? 0;
                      final ownBullets = stats['bullets'] ?? 0;
                      final equippedWeapon = stats['weapon'];
                      final hasWeapon = (equippedWeapon?['power'] ?? 0) > 0;

                      final canKill = _selectedTarget != null &&
                          _bullets > 0 &&
                          _bullets <= ownBullets &&
                          balance >= 10000 &&
                          hasWeapon;

                      return Column(
                        children: [
                          // HITLIST SECTION
                          // ==================== HITLIST SECTION (with rounded corners) ====================
Padding(
  padding: const EdgeInsets.all(16.0),
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
    decoration: BoxDecoration(
      color: const Color.fromARGB(200, 255, 200, 210), // Slightly stronger pink
      borderRadius: BorderRadius.circular(20),          // ← Rounded corners
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HITLIST',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 10),
        if (_hitlist.isEmpty)
          const Text(
            'No active hits right now.',
            style: TextStyle(color: Colors.grey),
          )
        else
          ..._hitlist.map((hit) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  hit['target'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Row(
                  children: [
                    Text('\$${NumberFormat('#,###').format(hit['reward'])} reward '),
                    Text('(${_formatRemainingTime(hit['endTime'])})'),
                  ],
                ),
                trailing: const Icon(Icons.whatshot, color: Colors.red),
              )),
      ],
    ),
  ),
),

                          // Toggle + Search
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Text('Normal Kill', style: TextStyle(color: Colors.white, fontSize: 16)),
                                Switch(
                                  value: _isHitlistMode,
                                  onChanged: (v) => setState(() => _isHitlistMode = v),
                                ),
                                const Text('Place Bounty', style: TextStyle(color: Colors.white, fontSize: 16)),
                              ],
                            ),
                          ),

                          // Search bar
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                labelText: 'Search player',
                                labelStyle: TextStyle(color: Colors.white),
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: _searchPlayers,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),

                          if (_searchError.isNotEmpty)
                            Center(child: Text(_searchError, style: const TextStyle(color: Colors.red))),

                          if (_isSearching)
                            const Center(child: CircularProgressIndicator())
                          else if (_searchResults.isEmpty && _selectedTarget == null)
                            const Center(child: Text('Search for a player above', style: TextStyle(color: Colors.white)))
                          else if (_selectedTarget == null)
                            Expanded(
                              child: ListView.builder(
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final name = _searchResults[index]['displayName'] as String;
                                  return ListTile(
                                    title: Text(name, style: const TextStyle(color: Colors.white)),
                                    onTap: () => _selectPlayer(name),
                                  );
                                },
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Target: $_selectedTarget', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 20),
                                  const Text('Bullets to Use:', style: TextStyle(color: Colors.white)),
                                  TextField(
                                    controller: _bulletsController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      hintText: 'Enter number of bullets',
                                      hintStyle: TextStyle(color: Colors.white),
                                    ),
                                    onChanged: (value) => setState(() => _bullets = int.tryParse(value) ?? 0),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  if (_bullets == 0)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Text('Enter bullets to proceed.', style: TextStyle(color: Colors.red)),
                                    ),
                                  const SizedBox(height: 20),
                                  const Text('Equipped Weapon:', style: TextStyle(color: Colors.white)),
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
                                      child: Text('You need to equip a weapon.', style: TextStyle(color: Colors.red)),
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
                                      child: Text('Need at least \$10,000 for mobilizing costs.', style: TextStyle(color: Colors.red)),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    final clean = newValue.text.replaceAll(',', '');
    if (!RegExp(r'^\d+$').hasMatch(clean)) return oldValue;

    final numValue = int.parse(clean);
    final formatted = NumberFormat('#,###').format(numValue);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}