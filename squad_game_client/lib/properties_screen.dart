import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:firebase_auth/firebase_auth.dart';  // For FirebaseAuth
import 'package:cloud_firestore/cloud_firestore.dart';  // For FirebaseFirestore

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
  }

  void _handleUpdate(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      setState(() => _stats = data);
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
        setState(() => _stats = doc.data()!);  // Update with fresh data
      }
    } catch (e) {
      print('Error fetching stats: $e');  // For debugging
    }
  }

  @override
  void dispose() {
    SocketService().socket?.off('update-stats', _handleUpdate);
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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // NEW: Add image at the top, above all details (including name)
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