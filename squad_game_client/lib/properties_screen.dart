import 'package:flutter/material.dart';
import 'socket_service.dart';

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key});

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    // Listen for updates
    SocketService().socket?.on('update-stats', _handleUpdate);
    // Initial claim on open
    SocketService().claimIncome();
  }

  void _handleUpdate(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      setState(() => _stats = data);
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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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