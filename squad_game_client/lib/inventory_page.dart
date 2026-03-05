import 'package:flutter/material.dart';

class InventoryPage extends StatelessWidget {
  final List<dynamic> inventory;

  const InventoryPage({super.key, required this.inventory});

  @override
  Widget build(BuildContext context) {
    // Group items by name and sum quantities
    final Map<String, Map<String, dynamic>> grouped = {};
    for (var item in inventory) {
      final name = item['name'] as String;
      if (grouped.containsKey(name)) {
        grouped[name]!['quantity'] += 1;
      } else {
        grouped[name] = {...item, 'quantity': 1};
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: grouped.isEmpty
          ? const Center(child: Text('Your inventory is empty.'))
          : ListView.builder(
              itemCount: grouped.length,
              itemBuilder: (context, index) {
                final key = grouped.keys.elementAt(index);
                final item = grouped[key]!;
                final quantity = item['quantity'] as int;
                final description = item['description'] as String? ?? 'No description';  // Handle null
                return ListTile(
                  title: Text('$key x$quantity'),
                  subtitle: Text(description),
                );
              },
            ),
    );
  }
}