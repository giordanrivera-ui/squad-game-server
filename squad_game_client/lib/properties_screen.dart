import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:firebase_auth/firebase_auth.dart';  // For FirebaseAuth
import 'package:cloud_firestore/cloud_firestore.dart';  // For FirebaseFirestore
import 'dart:async';
import 'package:intl/intl.dart'; 
import 'status_app_bar.dart';

class PropertiesScreen extends StatefulWidget {
  final Map<String, dynamic> initialStats;  // Assuming this is added from previous fix

  const PropertiesScreen({
    super.key,
    required this.initialStats,
  });

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  Map<String, dynamic> _stats = {};
  Map<String, int> _remainingMsByProp = {};  // Per-property remaining ms
  Map<String, bool> _expandedProps = {};  // NEW: Per-property expansion state
  Timer? _countdownTimer;
  static const int _incomeIntervalMs = 120000;  // 2 min test (change to 4*60*60*1000 = 14400000 for prod)

  // NEW: Constant list of upgrades
  static const List<String> upgrades = [
    'Fiber Optic',
    'Smart Appliances',
    'Double Glazing',
    'Energy Recovery Ventilation',
  ];

  // NEW: Map of upgrade costs per property
  static const Map<String, Map<String, int>> upgradeCosts = {
    'Fiber Optic': {
      'Micropod': 540,
      'Cottage': 720,
      'Bungalow': 900,
      'Townhouse': 1080,
      'Suburban home': 1260,
      'Villa': 1530,
      'Mansion': 1800,
      'Mid-Rise Block': 2070,
      'Residential Tower': 2530,
      'Skyscraper': 3200,
    },
    'Smart Appliances': {
      'Micropod': 800,
      'Cottage': 1000,
      'Bungalow': 1200,
      'Townhouse': 1400,
      'Suburban home': 1600,
      'Villa': 1900,
      'Mansion': 2220,
      'Mid-Rise Block': 2550,
      'Residential Tower': 3200,
      'Skyscraper': 4700,
    },
    'Double Glazing': {
      'Micropod': 1100,
      'Cottage': 1320,
      'Bungalow': 1550,
      'Townhouse': 1800,
      'Suburban home': 2020,
      'Villa': 2250,
      'Mansion': 2600,
      'Mid-Rise Block': 2900,
      'Residential Tower': 4000,
      'Skyscraper': 5500,
    },
    'Energy Recovery Ventilation': {
      'Micropod': 1450,
      'Cottage': 1700,
      'Bungalow': 1950,
      'Townhouse': 2200,
      'Suburban home': 2500,
      'Villa': 2750,
      'Mansion': 3250,
      'Mid-Rise Block': 3800,
      'Residential Tower': 4500,
      'Skyscraper': 6500,
    },
  };

  // NEW: Map of upgrade income boosts per property
  static const Map<String, Map<String, int>> upgradeBoosts = {
    'Fiber Optic': {
      'Micropod': 30,
      'Cottage': 40,
      'Bungalow': 50,
      'Townhouse': 60,
      'Suburban home': 70,
      'Villa': 85,
      'Mansion': 100,
      'Mid-Rise Block': 115,
      'Residential Tower': 140,
      'Skyscraper': 175,
    },
    'Smart Appliances': {
      'Micropod': 40,
      'Cottage': 50,
      'Bungalow': 60,
      'Townhouse': 70,
      'Suburban home': 80,
      'Villa': 95,
      'Mansion': 110,
      'Mid-Rise Block': 125,
      'Residential Tower': 150,
      'Skyscraper': 210,
    },
    'Double Glazing': {
      'Micropod': 50,
      'Cottage': 60,
      'Bungalow': 70,
      'Townhouse': 80,
      'Suburban home': 90,
      'Villa': 100,
      'Mansion': 115,
      'Mid-Rise Block': 130,
      'Residential Tower': 170,
      'Skyscraper': 230,
    },
    'Energy Recovery Ventilation': {
      'Micropod': 60,
      'Cottage': 70,
      'Bungalow': 80,
      'Townhouse': 90,
      'Suburban home': 90,
      'Villa': 110,
      'Mansion': 130,
      'Mid-Rise Block': 150,
      'Residential Tower': 180,
      'Skyscraper': 260,
    },
  };

  @override
  void initState() {
    super.initState();
    _stats = widget.initialStats;  // Set initial stats

    // Listen for updates
    SocketService().socket?.on('update-stats', _handleUpdate);
    // Initial claim on open
    SocketService().claimIncome();
    // Fetch latest stats as backup
    _fetchLatestStats();

    // Start countdown if player owns any properties
    if ((_stats['ownedProperties'] as List?)?.isNotEmpty ?? false) {
      _startCountdowns();
    }
  }

  void _handleUpdate(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      setState(() {
        _stats = data;
        // Restart countdown if stats update (e.g., after claim)
        _countdownTimer?.cancel();
        if ((_stats['ownedProperties'] as List?)?.isNotEmpty ?? false) {
          _startCountdowns();
        }
      });
    }
  }

  Future<void> _fetchLatestStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(user.email)
          .get();

      if (doc.exists && doc.data() != null) {
        setState(() {
          _stats = doc.data()!;  // Update with fresh data
          // Start/restart countdown after fetch
          _countdownTimer?.cancel();
          if ((_stats['ownedProperties'] as List?)?.isNotEmpty ?? false) {
            _startCountdowns();
          }
        });
      }
    } catch (e) {
      print('Error fetching stats: $e');  // For debugging
    }
  }

  // Start the local countdown timer (client-side only, no server hits)
  void _startCountdowns() {
    _countdownTimer?.cancel();

    // Initial calc for each owned property
    final nowMs = SocketService().currentServerTime;  // NEW: Synced time
    final claims = _stats['propertyClaims'] as List<dynamic>? ?? [];
    _remainingMsByProp = {};
    for (final claim in claims) {
      final name = claim['name'] as String?;
      final lastClaim = claim['lastClaim'] as int? ?? 0;
      if (name != null) {
        final elapsedMs = nowMs - lastClaim;
        final remaining = (_incomeIntervalMs - (elapsedMs % _incomeIntervalMs)).clamp(0, _incomeIntervalMs);
        _remainingMsByProp[name] = remaining.toInt();
      }
    }

    if (_remainingMsByProp.isEmpty) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingMsByProp = Map.from(_remainingMsByProp.map((name, remaining) {
          var newRemaining = remaining - 1000;
          if (newRemaining <= 0) newRemaining = _incomeIntervalMs;  // Reset cycle
          return MapEntry(name, newRemaining.toInt());
        }));
      });
    });
  }

  @override
  void dispose() {
    SocketService().socket?.off('update-stats', _handleUpdate);
    _countdownTimer?.cancel();  // Clean up timer
    super.dispose();
  }

  // NEW: Show full image popup
  void _showFullImage(String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Image.asset(
          imagePath,
          fit: BoxFit.contain,  // Full image without cropping
        ),
      ),
    );
  }

  // NEW: Toggle expansion for a property
  void _toggleExpand(String name) {
    setState(() {
      _expandedProps[name] = !(_expandedProps[name] ?? false);
    });
  }

  // NEW: Buy upgrade
  void _buyUpgrade(String propertyName, String upgradeName) {
    SocketService().buyUpgrade(propertyName, upgradeName);
  }

  @override
Widget build(BuildContext context) {
  final socketService = SocketService();
  final owned = List<String>.from(_stats['ownedProperties'] ?? []);

  return Scaffold(   // ← ADD THIS
    appBar: StatusAppBar(   // ← ADD THIS
      title: 'Properties',
      statsNotifier: socketService.statsNotifier,
      time: 'Live',
      onMenuPressed: () => Navigator.pop(context),
    ),
    body: ListView.builder(   // ← Your existing ListView stays exactly the same
      padding: const EdgeInsets.all(16),
      itemCount: socketService.properties.length,
      itemBuilder: (context, index) {
        // ... (everything inside your itemBuilder remains 100% unchanged)
        final prop = socketService.properties[index];
        final name = prop['name'] as String;
        final cost = prop['cost'] as int;
        final baseIncome = prop['income'] as int;
        final desc = prop['description'] as String;
        final isOwned = owned.contains(name);
        final canAfford = !isOwned && (_stats['balance'] ?? 0) >= cost;

        // Image path: assumes assets/$name.jpg (handles spaces in name like "Suburban home.jpg")
        final imagePath = 'assets/$name.jpg';

        // For owned, calculate progress (0.0 to 1.0) towards next income
        final progress = isOwned 
            ? (1 - ((_remainingMsByProp[name] ?? 0) / _incomeIntervalMs)).clamp(0.0, 1.0) 
            : 0.0;

        // NEW: Check if expanded
        final isExpanded = _expandedProps[name] ?? false;

        // NEW: Owned upgrades and total boost
        final ownedUps = List<String>.from(_stats['ownedUpgrades']?[name] ?? []);
        int totalBoost = 0;
        for (final up in ownedUps) {
          totalBoost += upgradeBoosts[up]?[name] ?? 0;
        }
        final income = baseIncome + totalBoost;
        final incomeText = totalBoost > 0 
            ? '\$${NumberFormat('#,###').format(baseIncome)} (+\$${NumberFormat('#,###').format(totalBoost)}) / 4 hours'
            : '\$${NumberFormat('#,###').format(income)} / 4 hours';

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // NEW: Make image clickable
                GestureDetector(
                  onTap: () => _showFullImage(imagePath),  // Show popup on tap
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),  // Optional: rounded corners for nice look
                    child: Image.asset(
                      imagePath,
                      fit: BoxFit.cover,  // Fill the space nicely
                      width: double.infinity,  // Full width of card
                      height: 180,  // Fixed height; adjust as needed
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback if image not found (e.g., for properties without assets yet)
                        return Container(
                          width: double.infinity,
                          height: 150,
                          color: Colors.grey[300],
                          child: const Center(child: Text('No Image')),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),  // Space between image and details
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                if (!isOwned)  // NEW: Only show cost if not owned
                  Text('Cost: \$${NumberFormat('#,###').format(cost)}', style: const TextStyle(color: Colors.blue)),  // EDITED: Add commas
                Text('Income: $incomeText', style: const TextStyle(color: Colors.green)),  // UPDATED: Show with bonus
                if (isOwned) ...[  // Progress bar for owned properties
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,  // Fills as time approaches next payout
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Next payout in ${(_remainingMsByProp[name] ?? 0) ~/ 60000} min ${(((_remainingMsByProp[name] ?? 0) % 60000) ~/ 1000)} sec',  // Human-readable time left
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  // NEW: Expand/Collapse arrow for upgrades
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => _toggleExpand(name),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Available upgrades', style: TextStyle(fontWeight: FontWeight.bold)),
                        Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                      ],
                    ),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 8),
                    ...upgrades.map((upgrade) {
                      final cost = upgradeCosts[upgrade]?[name] ?? 0;
                      final formattedCost = NumberFormat('#,###').format(cost);
                      final isPurchased = ownedUps.contains(upgrade);
                      final canAffordUpgrade = (_stats['balance'] ?? 0) >= cost;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: isPurchased ? const Icon(Icons.check, color: Colors.green) : null,
                        title: Text('$upgrade (\$${formattedCost})'),
                        onTap: isPurchased || !canAffordUpgrade ? null : () => _buyUpgrade(name, upgrade),
                        enabled: !isPurchased && canAffordUpgrade,
                        tileColor: isPurchased ? Colors.grey[200] : null,
                      );
                    }),
                  ],
                ],
                if (!isOwned)
                  ElevatedButton(
                    onPressed: canAfford ? () {
                      SocketService().buyProperty(name);
                    } : null,
                    child: const Text('Buy'),
                  )
                else
                  const Text('Owned', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    ),
  );
}
}