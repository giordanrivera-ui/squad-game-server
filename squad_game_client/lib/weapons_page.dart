import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';
import 'classes.dart';

class WeaponsPage extends StatefulWidget {
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final String currentLocation;

  const WeaponsPage({
    super.key,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.currentLocation,
  });

  @override
  State<WeaponsPage> createState() => _WeaponsPageState();
}

class _WeaponsPageState extends State<WeaponsPage> {
  late int _currentBalance;
  late int _currentHealth;

  final Map<String, bool> _checked = {};
  final Map<String, int> _quantities = {};
  int _totalCost = 0;

  final List<Weapon> _weapons = [
    Weapon(name: 'Small Knife', description: 'A compact blade for quick stabs and slashes in close-quarters combat.', power: 10, cost: 30),
    Weapon(name: 'Baseball Bat', description: 'A sturdy wooden club ideal for blunt force trauma in melee situations.', power: 18, cost: 120),
    Weapon(name: 'Machete', description: 'A large chopping blade effective for hacking through obstacles or enemies.', power: 25, cost: 250),
    Weapon(name: 'Splitting Maul', description: 'A heavy hammer-axe hybrid designed for powerful overhead strikes.', power: 30, cost: 350),
    Weapon(name: 'Ruger Mark IV', description: 'A reliable .22 caliber pistol perfect for target practice and small game.', power: 70, cost: 520),
    Weapon(name: 'Glock 45 Gen 5', description: 'A versatile 9mm handgun known for its durability and high-capacity magazine.', power: 150, cost: 700),
    Weapon(name: 'Remington R1 Enhanced', description: 'A 1911-style .45 pistol with improved ergonomics and accuracy.', power: 190, cost: 780),
    Weapon(name: 'Walther PDP Pro', description: 'A premium 9mm striker-fired pistol optimized for tactical use with modular ergonomics, crisp trigger, and full optics-ready capability.', power: 210, cost: 850),
    Weapon(name: 'Mossberg 590 Shotgun', description: 'A pump-action 12-gauge shotgun excellent for close-range crowd control.', power: 260, cost: 1200),
    Weapon(name: 'MP5 SMG', description: 'A compact 9mm submachine gun favored for its controllability in full-auto fire.', power: 330, cost: 4000),
    Weapon(name: 'H&K UMP5', description: 'A .45 caliber submachine gun offering superior stopping power in CQB.', power: 380, cost: 4600),
    Weapon(name: 'SLR104 AK-74', description: 'A modernized 5.45mm assault rifle with reliable performance in various conditions.', power: 405, cost: 6200),
    Weapon(name: 'CZ Bren 2', description: "A modern Czech 5.56mm assault rifle renowned for its exceptional reliability, lightweight modular design, and superior ergonomics.", power: 430, cost: 7500),
    Weapon(name: 'M4 Carbine', description: 'A lightweight 5.56mm carbine widely used for its modularity and accuracy.', power: 480, cost: 8400),
    Weapon(name: 'SCAR-16 Mk II', description: 'A battle-proven 5.56mm assault rifle with quick barrel swap capabilities.', power: 530, cost: 10500),
    Weapon(name: 'M16A4', description: 'A full-length 5.56mm rifle known for its precision in semi-automatic fire.', power: 550, cost: 16400),
    Weapon(name: 'XM7', description: 'A next-generation 6.8x51mm battle rifle adopted by the U.S. Army for superior range, penetration, and lethality compared to legacy 5.56mm platforms.', power: 575, cost: 17200),
    Weapon(name: 'M24 Sniper', description: 'A bolt-action 7.62mm rifle designed for long-range precision shots.', power: 610, cost: 22000),
    Weapon(name: 'Barrett M82', description: 'A .50 caliber anti-materiel rifle capable of penetrating light armor at distance.', power: 640, cost: 28000),
  ];

  @override
  void initState() {
    super.initState();
    _currentBalance = widget.currentBalance;
    _currentHealth = widget.currentHealth;

    SocketService().socket?.on('update-stats', _handleStatsUpdate);
  }

  void _handleStatsUpdate(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      setState(() {
        _currentBalance = data['balance'] ?? _currentBalance;
        _currentHealth = data['health'] ?? _currentHealth;
      });
    }
  }

  @override
  void dispose() {
    SocketService().socket?.off('update-stats', _handleStatsUpdate);
    super.dispose();
  }

  void _updateTotal() {
    int total = 0;
    for (var item in _weapons) {
      final key = item.name;
      if (_checked[key] == true) {
        total += (_quantities[key] ?? 0) * item.cost;
      }
    }
    setState(() => _totalCost = total);
  }

  void _purchaseItems() {
    List<Map<String, dynamic>> purchased = [];
    for (var item in _weapons) {
      final key = item.name;
      final qty = _quantities[key] ?? 0;
      if (_checked[key] == true && qty > 0) {
        for (int i = 0; i < qty; i++) {
          purchased.add(item.toMap());
        }
      }
    }

    setState(() {
      _currentBalance -= _totalCost;
    });

    SocketService().purchaseArmor(purchased, _totalCost); // Reuse purchase logic or create new event if needed

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Items purchased!')));

    setState(() {
      _checked.clear();
      _quantities.clear();
      _totalCost = 0;
    });
  }

  Widget _buildSection(String title, List<Weapon> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        ...items.map((item) {
          final key = item.name;
          final checked = _checked[key] ?? false;
          final quantity = _quantities[key] ?? 1;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: checked,
                    onChanged: (v) {
                      setState(() {
                        _checked[key] = v!;
                        if (!v) _quantities[key] = 0;
                        else _quantities[key] = 1;
                      });
                      _updateTotal();
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Cost: ${item.cost}'),
                        const SizedBox(height: 4),
                        Text(item.description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  if (checked)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: quantity > 1 ? () {
                            setState(() => _quantities[key] = quantity - 1);
                            _updateTotal();
                          } : null,
                        ),
                        Text('$quantity'),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setState(() => _quantities[key] = quantity + 1);
                            _updateTotal();
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPurchase = _totalCost > 0 && _currentBalance >= _totalCost;

    return Scaffold(
      appBar: StatusAppBar(
        title: 'Weapons',
        statsNotifier: SocketService().statsNotifier,
        time: widget.currentTime,
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection('Weapons', _weapons),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total Cost: $_totalCost', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canPurchase ? _purchaseItems : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canPurchase ? Colors.green : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Purchase items', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}