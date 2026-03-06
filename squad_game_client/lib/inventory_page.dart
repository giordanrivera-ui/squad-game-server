import 'package:flutter/material.dart';
import 'socket_service.dart';

class InventoryPage extends StatefulWidget {
  final List<dynamic> inventory;

  const InventoryPage({super.key, required this.inventory});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late Map<String, Map<String, dynamic>> grouped;
  final Map<String, bool> _checked = {};
  final Map<String, int> _quantities = {};
  int _totalSellValue = 0;

  @override
  void initState() {
    super.initState();
    _groupInventory();
  }

  void _groupInventory() {
    grouped = {};
    for (var item in widget.inventory) {
      final name = item['name'] as String;
      if (grouped.containsKey(name)) {
        grouped[name]!['quantity'] += 1;
      } else {
        grouped[name] = {...item, 'quantity': 1};
      }
    }
  }

  void _updateTotal() {
    int total = 0;
    grouped.forEach((name, item) {
      final key = name;
      if (_checked[key] == true) {
        final qty = _quantities[key] ?? 0;
        final cost = (item['cost'] as int?) ?? 0;
        total += qty * (cost * 0.6).floor();  // 60% of cost, floored to int
      }
    });
    setState(() => _totalSellValue = total);
  }

  void _sellItems() {
    List<Map<String, dynamic>> toSell = [];
    grouped.forEach((name, baseItem) {
      final key = name;
      final qty = _quantities[key] ?? 0;
      if (_checked[key] == true && qty > 0) {
        for (int i = 0; i < qty; i++) {
          toSell.add({...baseItem, 'name': name});  // Full item map
        }
      }
    });

    if (toSell.isEmpty) return;

    SocketService().sellItems(toSell, _totalSellValue);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Items sold!')));

    setState(() {
      _checked.clear();
      _quantities.clear();
      _totalSellValue = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSell = _totalSellValue > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: Column(
        children: [
          Expanded(
            child: grouped.isEmpty
                ? const Center(child: Text('Your inventory is empty.'))
                : ListView.builder(
                    itemCount: grouped.length,
                    itemBuilder: (context, index) {
                      final key = grouped.keys.elementAt(index);
                      final item = grouped[key]!;
                      final quantity = item['quantity'] as int;
                      final description = item['description'] as String? ?? 'No description';
                      final checked = _checked[key] ?? false;
                      final sellQty = _quantities[key] ?? 1;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
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
                                    Text('$key x$quantity', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              if (checked)
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove),
                                      onPressed: sellQty > 1 && sellQty <= quantity
                                          ? () {
                                              setState(() => _quantities[key] = sellQty - 1);
                                              _updateTotal();
                                            }
                                          : null,
                                    ),
                                    Text('$sellQty'),
                                    IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: sellQty < quantity
                                          ? () {
                                              setState(() => _quantities[key] = sellQty + 1);
                                              _updateTotal();
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (grouped.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: Column(
                children: [
                  Text('Sell Value: \$$_totalSellValue', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: canSell ? _sellItems : null,
                    style: ElevatedButton.styleFrom(backgroundColor: canSell ? Colors.red : Colors.grey),
                    child: const Text('Sell Selected Items'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}