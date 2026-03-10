import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:firebase_auth/firebase_auth.dart';  // For FirebaseAuth
import 'package:cloud_firestore/cloud_firestore.dart';  // For FirebaseFirestore
import 'dart:async';

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
  Timer? _countdownTimer;  // For per-second progress updates
  static const int _incomeIntervalMs = 120000;  // 2 min test (change to 4*60*60*1000 = 14400000 for prod)

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
        // Restart countdown if stats update (e.g., after claim or buy)
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
          // Restart countdown after fetch
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
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final claims = _stats['propertyClaims'] as List<dynamic>? ?? [];
    _remainingMsByProp = {};
    for (final claim in claims) {
      final name = claim['name'] as String?;
      final lastClaim = claim['lastClaim'] as int? ?? 0;
      if (name != null) {
        final elapsedMs = nowMs - lastClaim;
        final remaining = (_incomeIntervalMs - (elapsedMs % _incomeIntervalMs)).clamp(0, _incomeIntervalMs);
        _remainingMsByProp[name] = remaining.toInt();  // Store as int for ms
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

  @override
  Widget build(BuildContext context) {
    final socketService = SocketService();
    final owned = List<String>.from(_stats['ownedProperties'] ?? []);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: socketService.properties.length,
      itemBuilder: (context, index) {
        final prop = socketService.properties[index];
        final name = prop['name'] as String;
        final cost = prop['cost'] as int;
        final income = prop['income'] as int;
        final desc = prop['description'] as String;
        final isOwned = owned.contains(name);
        final canAfford = !isOwned && (_stats['balance'] ?? 0) >= cost;

        // Image path: assumes assets/$name.jpg (handles spaces in name like "Suburban home.jpg")
        final imagePath = 'assets/$name.jpg';

        // For owned, calculate progress (0.0 to 1.0) towards next income
        final progress = isOwned 
            ? (1 - ((_remainingMsByProp[name] ?? 0) / _incomeIntervalMs)).clamp(0.0, 1.0) 
            : 0.0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image at the top
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),  // Optional: rounded corners for nice look
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,  // Fill the space nicely
                    width: double.infinity,  // Full width of card
                    height: 150,  // Fixed height; adjust as needed
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
                const SizedBox(height: 12),  // Space between image and details
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Text('Cost: \$$cost', style: const TextStyle(color: Colors.blue)),
                Text('Income: \$$income / 4 hours', style: const TextStyle(color: Colors.green)),
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
    );
  }
}