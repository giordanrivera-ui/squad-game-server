import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';
import 'classes.dart';

class VehiclesPage extends StatefulWidget {
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final String currentLocation;

  const VehiclesPage({
    super.key,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.currentLocation,
  });

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  late int _currentBalance;
  late int _currentHealth;

  final Map<String, bool> _checked = {};
  final Map<String, int> _quantities = {};
  int _totalCost = 0;

  final List<Vehicle> _vehicles = [
    Vehicle(name: 'Bicycle', power: 50, cost: 350, skillReq: 0, description: 'A human-powered vehicle with two wheels, propelled by pedaling.', defense: 0),
    Vehicle(name: 'Motorcycle', power: 75, cost: 4200, skillReq: 0, description: 'A two-wheeled powered vehicle with a seat or saddle, designed for rider and passenger.', defense: 1),
    Vehicle(name: 'Corolla', power: 150, cost: 18000, skillReq: 0, description: 'A compact sedan known for reliability, fuel efficiency, and affordability.', defense: 2),
    Vehicle(name: 'Jeep', power: 200, cost: 36000, skillReq: 1, description: 'Rugged off-road SUV with removable doors/roof, excellent trail capability.', defense: 3),
    Vehicle(name: 'Strada Pickup Truck', power: 280, cost: 55000, skillReq: 1, description: 'Mid-size pickup with rugged design, diesel engine, good for work/adventure.', defense: 3),
    Vehicle(name: 'Hummer H1', power: 360, cost: 80000, skillReq: 2, description: 'Civilian version of military Humvee, extreme off-road 4x4 with high ground clearance.', defense: 4),
    Vehicle(name: 'M998 Humvee', power: 500, cost: 92000, skillReq: 4, description: 'Military 4x4 utility vehicle, highly mobile, multi-purpose.', defense: 4),
    Vehicle(name: 'M-ATV', power: 750, cost: 475000, skillReq: 5, description: 'Mine-resistant ambush-protected all-terrain vehicle for troop protection in hazardous environments.', defense: 5),
    Vehicle(name: 'MaxxPro MRAP', power: 900, cost: 1400000, skillReq: 6, description: 'Armored fighting vehicle designed for IED protection, V-hull design.', defense: 5),
    Vehicle(name: 'AMPV', power: 1200, cost: 4500000, skillReq: 8, description: 'Armored multi-purpose vehicle replacing M113, for troop transport and support.', defense: 6),
    Vehicle(name: 'Stryker M1126', power: 1500, cost: 5250000, skillReq: 10, description: 'Wheeled armored personnel carrier, highly mobile 8x8 for infantry transport.', defense: 7),
    Vehicle(name: 'M1 Abrams', power: 2000, cost: 8200000, skillReq: 12, description: 'Third-generation main battle tank with advanced armor, 120mm gun, high mobility.', defense: 8),
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
    for (var item in _vehicles) {
      final key = item.name;
      if (_checked[key] == true) {
        total += (_quantities[key] ?? 0) * item.cost;
      }
    }
    setState(() => _totalCost = total);
  }

  void _purchaseItems() {
    List<Map<String, dynamic>> purchased = [];
    for (var item in _vehicles) {
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

  Widget _buildSection(String title, List<Vehicle> items) {
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
        title: 'Vehicles',
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
                _buildSection('Vehicles', _vehicles),
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