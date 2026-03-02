import 'package:flutter/material.dart';
import 'socket_service.dart';

class AirportScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final int prisonEndTime;           // ← NEW: Added for prison system

  const AirportScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.prisonEndTime,     // ← NEW
  });

  @override
  State<AirportScreen> createState() => _AirportScreenState();
}

class _AirportScreenState extends State<AirportScreen> {
  String? _selectedDestination;

  // Check if player is currently in prison
  bool get _isInPrison => widget.prisonEndTime > DateTime.now().millisecondsSinceEpoch;

  int? get _cost => _selectedDestination != null
      ? SocketService().travelCosts[_selectedDestination!]
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
  }

  @override
  Widget build(BuildContext context) {
    // If player is in prison, show prison screen instead of airport
    if (_isInPrison) {
      final remainingSeconds = ((widget.prisonEndTime - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();

      return Scaffold(
        backgroundColor: Colors.grey[900],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.gavel, size: 100, color: Colors.redAccent),
              const SizedBox(height: 30),
              const Text(
                'YOU ARE IN PRISON',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                'Time left: $remainingSeconds seconds',
                style: const TextStyle(fontSize: 20, color: Colors.orangeAccent),
              ),
              const SizedBox(height: 40),
              const Text(
                'You cannot travel while in prison.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Normal Airport Screen (only shown when NOT in prison)
    final socketService = SocketService();
    final available = socketService.normalLocations
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
              final cityCost = socketService.travelCosts[city] ?? 0;

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