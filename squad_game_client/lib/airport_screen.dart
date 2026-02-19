import 'package:flutter/material.dart';
import 'constants.dart';
import 'socket_service.dart';

class AirportScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;

  const AirportScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
  });

  @override
  State<AirportScreen> createState() => _AirportScreenState();
}

class _AirportScreenState extends State<AirportScreen> {
  String? _selectedDestination;           // which city the player picked
  final SocketService _socketService = SocketService();

  // How much does the selected city cost?
  int? get _cost => _selectedDestination != null 
      ? GameConstants.travelCosts[_selectedDestination!] 
      : null;

  // Is the Travel button allowed to work?
  bool get _canTravel => _selectedDestination != null && 
                         _cost != null && 
                         widget.currentBalance >= _cost!;

  void _travel() {
    if (!_canTravel) return;

    _socketService.travel(_selectedDestination!);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✈️ Flying to new city... Enjoy the flight!')),
    );

    Navigator.pop(context);   // go back to main game screen
  }

  @override
  Widget build(BuildContext context) {
    // All cities except the one you are already in
    final available = GameConstants.normalLocations
        .where((city) => city != widget.currentLocation)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('✈️ Airport')),
      body: Column(
        children: [
          // Top box showing where you are now
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.blue[50],
            child: Column(
              children: [
                const Text('You are in', style: TextStyle(fontSize: 18)),
                Text(widget.currentLocation, 
                     style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text('Money: \$${widget.currentBalance}', 
                     style: const TextStyle(fontSize: 20, color: Colors.green)),
              ],
            ),
          ),

          // List of cities with radio buttons
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

          // Cost text + helper message + Travel button
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Big cost text when you pick a city
                if (_selectedDestination != null)
                  Text(
                    'Flight to $_selectedDestination costs \$${_cost}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange),
                  )
                else
                  const Text('Pick a city above 👆', style: TextStyle(fontSize: 18, color: Colors.grey)),

                const SizedBox(height: 12),

                // Helper text under the travel button
                if (_selectedDestination == null)
                  const Text('Please select a destination', style: TextStyle(color: Colors.red, fontSize: 16))
                else if (_cost! > widget.currentBalance)
                  const Text('Not enough money!', style: TextStyle(color: Colors.red, fontSize: 16))
                else
                  const Text('Ready to fly! ✈️', style: TextStyle(color: Colors.green, fontSize: 16)),

                const SizedBox(height: 20),

                // The big Travel button (grey when you can't use it)
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
      ),
    );
  }
}