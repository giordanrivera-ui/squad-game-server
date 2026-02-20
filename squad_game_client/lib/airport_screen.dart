import 'package:flutter/material.dart';
import 'constants.dart';
import 'socket_service.dart';

class AirportScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;
  final int currentHealth;
  final String currentTime;

  const AirportScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
  });

  @override
  State<AirportScreen> createState() => _AirportScreenState();
}

class _AirportScreenState extends State<AirportScreen> {
  String? _selectedDestination;

  int? get _cost => _selectedDestination != null
      ? GameConstants.travelCosts[_selectedDestination!]
      : null;

  bool get _canTravel => _selectedDestination != null &&
                         _cost != null &&
                         widget.currentBalance >= _cost!;

  void _travel() {
    if (!_canTravel) return;

    SocketService().travel(_selectedDestination!);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✈️ Flying to new city... Enjoy the flight!')),
    );

    // No Navigator.pop needed anymore
  }

  @override
  Widget build(BuildContext context) {
    final available = GameConstants.normalLocations
        .where((city) => city != widget.currentLocation)
        .toList();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: Colors.blue[50],
          child: Column(
            children: [
              const Text('You are in', style: TextStyle(fontSize: 18)),
              Text(widget.currentLocation,
                   style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (context, index) {
              final city = available[index];
              final cityCost = GameConstants.travelCosts[city] ?? 0;

              return RadioListTile<String>(
                title: Text(city, style: const TextStyle(fontSize: 18)),
                subtitle: Text('Cost: \$$cityCost'),
                value: city,
                groupValue: _selectedDestination,
                onChanged: (value) {
                  setState(() => _selectedDestination = value);
                },
              );
            },
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_selectedDestination != null)
                Text(
                  'Flight to $_selectedDestination costs \$${_cost}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange),
                )
              else
                const Text('Pick a city above 👆', style: TextStyle(fontSize: 18, color: Colors.grey)),

              const SizedBox(height: 12),

              if (_selectedDestination == null)
                const Text('Please select a destination', style: TextStyle(color: Colors.red, fontSize: 16))
              else if (_cost! > widget.currentBalance)
                const Text('Not enough money!', style: TextStyle(color: Colors.red, fontSize: 16))
              else
                const Text('Ready to fly! ✈️', style: TextStyle(color: Colors.green, fontSize: 16)),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canTravel ? _travel : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canTravel ? Colors.green : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text(
                    '✈️ TRAVEL NOW ✈️',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}