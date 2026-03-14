import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';
import 'dart:async';  // NEW: For Timer

class InventoryPage extends StatefulWidget {
  final List<dynamic> initialInventory;
  final Map<String, dynamic> initialStats;
  final String initialTime;

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
  late Map<String, dynamic> _stats;
  late String _time;
  late Map<String, Map<String, dynamic>> grouped;
  final Map<String, bool> _checked = {};
  final Map<String, int> _quantities = {};
  int _totalSellValue = 0;

  // NEW: For ban countdown
  late int _sellBanEndTime;
  Timer? _banTimer;
  int _banRemainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _inventory = List.from(widget.initialInventory);
    _stats = Map.from(widget.initialStats);
    _time = widget.initialTime;
    _sellBanEndTime = _stats['sellBanEndTime'] ?? 0;  // NEW
    _groupInventory();
    _startBanCountdown();  // NEW

    SocketService().socket?.on('update-stats', _handleUpdateStats);
    SocketService().socket?.on('time', _handleUpdateTime);
    SocketService().socket?.on('sell-result', _handleSellResult);
  }

  @override
  void dispose() {
    SocketService().socket?.off('update-stats', _handleUpdateStats);
    SocketService().socket?.off('time', _handleUpdateTime);
    SocketService().socket?.off('sell-result', _handleSellResult);
    _banTimer?.cancel();  // NEW
    super.dispose();
  }

  void _handleUpdateStats(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      setState(() {
        _stats = {..._stats, ...data};
        _inventory = List.from(data['inventory'] ?? _inventory);
        _sellBanEndTime = data['sellBanEndTime'] ?? _sellBanEndTime;  // NEW
        _groupInventory();
        _checked.clear();
        _quantities.clear();
        _totalSellValue = 0;
        _startBanCountdown();  // NEW: Restart countdown on update
      });
    }
  }

  void _handleUpdateTime(dynamic data) {
    if (data is String && mounted) {
      setState(() => _time = data);
    }
  }

  void _handleSellResult(dynamic data) {
    if (data is Map && mounted) {
      final bool success = data['success'] ?? false;
      final String msg = data['message'] ?? (success ? 'Items sold!' : 'Sale failed.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  // NEW: Start/update ban countdown
  void _startBanCountdown() {
    _banTimer?.cancel();

    final now = DateTime.now().millisecondsSinceEpoch;
    _banRemainingSeconds = ((_sellBanEndTime - now) / 1000).ceil().clamp(0, 999999);  // Large max for hours

    if (_banRemainingSeconds > 0) {
      _banTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _banRemainingSeconds--;
          if (_banRemainingSeconds <= 0) {
            timer.cancel();
            _sellBanEndTime = 0;  // Clear if ended
          }
        });
      });
    }
  }

  String _formatBanTime(int seconds) {
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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
      _totalSellValue = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSell = _totalSellValue > 0 && _banRemainingSeconds <= 0;  // NEW: Check not banned
    final isBanned = _banRemainingSeconds > 0;  // NEW

    return Scaffold(
      appBar: StatusAppBar(
        title: 'Inventory',
        statsNotifier: SocketService().statsNotifier,
        time: _time,
        onMenuPressed: () => Navigator.pop(context),
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
                                onChanged: isBanned ? null : (v) {  // NEW: Disable if banned
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
                              if (checked && !isBanned)  // NEW: Hide qty if banned
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
                  if (isBanned)  // NEW: Show ban countdown
                    Text(
                      'Banned from selling for ${_formatBanTime(_banRemainingSeconds)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                    )
                  else
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