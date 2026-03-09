import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'classes.dart';
import 'dart:async';

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key});

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  late List<Properties> _ownedProperties;
  late int _currentBalance;
  Timer? _incomeTimer;

  final List<Properties> _allProperties = [
    Properties(
      name: 'Micropod',
      description: 'A tiny, prefabricated pod apartment perfect for budget-conscious urban dwellers. Minimalist living at its finest.',
      cost: 15000,
      income: 840,
    ),
    Properties(
      name: 'Cottage',
      description: 'Quaint countryside cottage with a thatched roof and blooming garden. Ideal for romantic getaways.',
      cost: 45000,
      income: 2150,
    ),
    Properties(
      name: 'Bungalow',
      description: 'Single-story home with a low-pitched roof and wide veranda, offering relaxed tropical living.',
      cost: 98000,
      income: 4400,
    ),
    Properties(
      name: 'Townhouse',
      description: 'Multi-floor urban dwelling sharing walls with neighbors, combining city convenience with home ownership.',
      cost: 150000,
      income: 6400,
    ),
    Properties(
      name: 'Suburban home',
      description: 'Spacious family house in quiet neighborhoods with yards, perfect for raising kids away from city bustle.',
      cost: 210000,
      income: 8750,
    ),
    Properties(
      name: 'Villa',
      description: 'Luxurious countryside estate with gardens and pools, evoking Mediterranean elegance and privacy.',
      cost: 300000,
      income: 11880,
    ),
    Properties(
      name: 'Mansion',
      description: 'Grand, opulent residence with multiple rooms, often featuring historical architecture and vast grounds.',
      cost: 500000,
      income: 18520,
    ),
    Properties(
      name: 'Mid-Rise Block',
      description: 'Multi-story apartment building offering urban living with amenities like gyms and rooftop terraces.',
      cost: 1200000,
      income: 43400,
    ),
    Properties(
      name: 'Residential Tower',
      description: 'High-rise condominium with panoramic views, security, and luxury facilities for cosmopolitan lifestyles.',
      cost: 3800000,
      income: 126700,
    ),
    Properties(
      name: 'Skyscraper',
      description: 'Towering mixed-use structure dominating city skylines, housing offices, residences, and commercial spaces.',
      cost: 9000000,
      income: 276900,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ownedProperties = [];
    _currentBalance = 0; // Change to widget.currentBalance if passed

    SocketService().socket?.on('update-stats', _handleStatsUpdate);

    _incomeTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      SocketService().collectIncome();
    });
  }

  void _handleStatsUpdate(dynamic data) {
    if (data is Map<String, dynamic> && mounted) {
      setState(() {
        _currentBalance = data['balance'] ?? _currentBalance;
        _ownedProperties = List<Properties>.from(
          (data['properties'] ?? []).map((name) => _allProperties.firstWhere((p) => p.name == name))
        );
      });
    }
  }

  @override
  void dispose() {
    SocketService().socket?.off('update-stats', _handleStatsUpdate);
    _incomeTimer?.cancel();
    super.dispose();
  }

  void _buyProperty(Properties property) {
    if (_currentBalance < property.cost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough balance!')));
      return;
    }

    setState(() {
      _currentBalance -= property.cost;
      _ownedProperties.add(property);
    });

    SocketService().buyProperty(property.name);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Purchased ${property.name}!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Properties')),
      body: ListView.builder(
        itemCount: _allProperties.length,
        itemBuilder: (context, index) {
          final property = _allProperties[index];
          final isOwned = _ownedProperties.contains(property);

          return Card(
            child: ListTile(
              title: Text(property.name),
              subtitle: Text(property.description + '\nCost: \$${property.cost} | Income: \$${property.income}/4hrs'),
              trailing: isOwned 
                ? const Icon(Icons.check, color: Colors.green)
                : ElevatedButton(
                    onPressed: () => _buyProperty(property),
                    child: const Text('Buy'),
                  ),
            ),
          );
        },
      ),
    );
  }
}