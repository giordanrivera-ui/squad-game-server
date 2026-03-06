import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';  // NEW: Import StatusAppBar

class InventoryPage extends StatefulWidget {
  final List<dynamic> initialInventory;
  final Map<String, dynamic> initialStats;  // NEW: Full stats for app bar
  final String initialTime;  // NEW: Initial time for app bar

  const InventoryPage({
    super.key,
    required this.initialInventory,
    required this.initialStats,
    required this.initialTime,
  });

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late List<dynamic> _inventory;
  late Map<String, dynamic> _stats;  // NEW: Local stats for live update
  late String _time;  // NEW: Local time for live update
  late Map<String, Map<String, dynamic>> grouped;
  final Map<String, bool> _checked = {};
  final Map<String, int> _quantities = {};
  int _totalSellValue = 0;

  @override
  void initState() {
    super.initState();
    _inventory = List.from(widget.initialInventory);
    _stats = Map.from(widget.initialStats);  // NEW
    _time = widget.initialTime;  // NEW
    _groupInventory();

    // Listen for live updates
    SocketService().socket?.on('update-stats', _handleUpdateStats);
    SocketService().socket?.on('time', _handleUpdateTime);  // NEW: For time updates
  }

  @override
  void dispose() {
    SocketService().socket?.off('update-stats', _handleUpdateStats);
    SocketService().socket?.off('time', _handleUpdateTime);  // NEW
    super.dispose();
  }

  // Handler to refresh inventory + stats on update
  void _handleUpdateStats(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      setState(() {
        _stats = {..._stats, ...data};  // Merge updates
        _inventory = List.from(data['inventory'] ?? _inventory);
        _groupInventory();
        // Reset selections on update
        _checked.clear();
        _quantities.clear();
        _totalSellValue = 0;
      });
    }
  }

  // NEW: Handler for time updates
  void _handleUpdateTime(dynamic data) {
    if (data is String && mounted) {
      setState(() => _time = data);
    }
  }

  void _groupInventory() {
    grouped = {};
    for (var item in _inventory) {
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
        total += qty * (cost * 0.6).floor();
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
          toSell.add({...baseItem, 'name': name});
        }
      }
    });

    if (toSell.isEmpty) return;

    // NEW: Dialog for rate choice
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sell at What Rate?'),
        content: const Text('Higher rate = higher risk of failure and ban.'),
        actions: [
          TextButton(
            onPressed: () => _confirmSell(ctx, toSell, 60),
            child: const Text('60% (Safe)'),
          ),
          TextButton(
            onPressed: () => _confirmSell(ctx, toSell, 80),
            child: const Text('80% (Medium Risk)'),
          ),
          TextButton(
            onPressed: () => _confirmSell(ctx, toSell, 100),
            child: const Text('100% (High Risk)'),
          ),
        ],
      ),
    );
  }

  // NEW: Helper to calc value at rate and emit
  void _confirmSell(BuildContext ctx, List<Map<String, dynamic>> toSell, int rate) {
    Navigator.pop(ctx);

    int adjustedValue = 0;
    for (var item in toSell) {
      final cost = (item['cost'] as int?) ?? 0;
      adjustedValue += (cost * (rate / 100)).floor();
    }

    SocketService().sellItems(toSell, adjustedValue, rate);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selling at $rate%...')));

    setState(() {
      _checked.clear();
      _quantities.clear();
      _totalSellValue = 0;  // Reset (UI will update on socket)
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSell = _totalSellValue > 0;

    return Scaffold(
      appBar: StatusAppBar(  // NEW: Add StatusAppBar
        title: 'Inventory',
        stats: _stats,
        time: _time,
        onMenuPressed: () => Navigator.pop(context),  // Back button
      ),
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