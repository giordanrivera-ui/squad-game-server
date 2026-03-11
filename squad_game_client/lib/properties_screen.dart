import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class PropertiesScreen extends StatefulWidget {
  final Map<String, dynamic> initialStats;

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
  Timer? _countdownTimer;
  static const int _incomeIntervalMs = 120000;  // 2 min test (change to 4*60*60*1000 = 14400000 for prod)

  @override
  void initState() {
    super.initState();
    _stats = widget.initialStats;

    SocketService().socket?.on('update-stats', _handleUpdate);
    SocketService().claimIncome();
    _fetchLatestStats();

    if ((_stats['ownedProperties'] as List?)?.isNotEmpty ?? false) {
      _startCountdowns();
    }
  }

  void _handleUpdate(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      setState(() {
        _stats = data;
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
          _stats = doc.data()!;
          _countdownTimer?.cancel();
          if ((_stats['ownedProperties'] as List?)?.isNotEmpty ?? false) {
            _startCountdowns();
          }
        });
      }
    } catch (e) {
      print('Error fetching stats: $e');
    }
  }

  void _startCountdowns() {
    _countdownTimer?.cancel();

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
          if (newRemaining <= 0) newRemaining = _incomeIntervalMs;
          return MapEntry(name, newRemaining.toInt());
        }));
      });
    });
  }

  @override
  void dispose() {
    SocketService().socket?.off('update-stats', _handleUpdate);
    _countdownTimer?.cancel();
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

        final imagePath = 'assets/$name.jpg';

        final progress = isOwned 
            ? (1 - ((_remainingMsByProp[name] ?? 0) / _incomeIntervalMs)).clamp(0.0, 1.0) 
            : 0.0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 150,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: double.infinity,
                        height: 150,
                        color: Colors.grey[300],
                        child: const Center(child: Text('No Image')),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Text('Cost: \$$cost', style: const TextStyle(color: Colors.blue)),
                Text('Income: \$$income / 4 hours', style: const TextStyle(color: Colors.green)),
                if (isOwned) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Next payout in ${(_remainingMsByProp[name] ?? 0) ~/ 60000} min ${(((_remainingMsByProp[name] ?? 0) % 60000) ~/ 1000)} sec',
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