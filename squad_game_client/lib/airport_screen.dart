import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'dart:async';

class AirportScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final int prisonEndTime;

  const AirportScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.prisonEndTime,
  });

  @override
  State<AirportScreen> createState() => _AirportScreenState();
}

class _AirportScreenState extends State<AirportScreen> {
  int _prisonEndTime = 0;
  Timer? _countdownTimer;

  // Live check
  bool get _isInPrison => _prisonEndTime > SocketService().currentServerTime;

  int get _remainingSeconds {
    if (!_isInPrison) return 0;
    return ((_prisonEndTime - SocketService().currentServerTime) / 1000)
        .ceil()
        .clamp(0, 60);
  }

  @override
  void initState() {
    super.initState();
    _prisonEndTime = widget.prisonEndTime;

    // Live countdown while screen is open
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Listen for stats updates (in case you get re-imprisoned)
    SocketService().socket?.on('update-stats', _handleStatsUpdate);
  }

  void _handleStatsUpdate(dynamic data) {
    if (data is Map && data.containsKey('prisonEndTime')) {
      setState(() => _prisonEndTime = data['prisonEndTime'] ?? 0);
    }
  }

  @override
  void didUpdateWidget(covariant AirportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prisonEndTime != oldWidget.prisonEndTime) {
      setState(() => _prisonEndTime = widget.prisonEndTime);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    SocketService().socket?.off('update-stats', _handleStatsUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInPrison) {
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
                'Time left: $_remainingSeconds seconds',
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
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, currentStats, child) {
        final socketService = SocketService();
        final available = socketService.normalLocations
            .where((city) => city != currentStats['location'])  // ← Use currentStats
            .toList();

        // ← Add these (move from outside)
        final int? cost = _selectedDestination != null
            ? socketService.travelCosts[_selectedDestination!]  // ← "final" instead of "get"
            : null;

        final bool canTravel = _selectedDestination != null &&
                              cost != null &&
                              (currentStats['balance'] ?? 0) >= cost;  // ← Use currentStats balance

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.blue[50],
              child: Column(
                children: [
                  const Text('You are in', style: TextStyle(fontSize: 18)),
                  Text(currentStats['location'] ?? widget.currentLocation,  // ← Use currentStats
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
                      'Flight to $_selectedDestination costs \$${cost}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange),
                    )
                  else
                    const Text('Pick a city above 👆', style: TextStyle(fontSize: 18, color: Colors.grey)),

                  const SizedBox(height: 12),

                  if (_selectedDestination == null)
                    const Text('Please select a destination', style: TextStyle(color: Colors.red, fontSize: 16))
                  else if (cost! > (currentStats['balance'] ?? widget.currentBalance))  // ← Use currentStats
                    const Text('Not enough money!', style: TextStyle(color: Colors.red, fontSize: 16))
                  else
                    const Text('Ready to fly! ✈️', style: TextStyle(color: Colors.green, fontSize: 16)),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canTravel ? _travel : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canTravel ? Colors.green : Colors.grey,
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
      },
    );
  }

  // Your existing fields and methods (kept exactly as before)
  String? _selectedDestination;

  void _travel() {
    final currentStats = SocketService().statsNotifier.value;  // Get latest inside
    final int? cost = _selectedDestination != null
        ? SocketService().travelCosts[_selectedDestination!]
        : null;

    if (_selectedDestination == null || cost == null || (currentStats['balance'] ?? 0) < cost) return;

    SocketService().travel(_selectedDestination!);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✈️ Flying to new city... Enjoy the flight!')),
    );
  }
}
