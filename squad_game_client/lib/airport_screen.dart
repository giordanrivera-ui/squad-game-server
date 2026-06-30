import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'dart:async';
import 'game_header.dart';
import 'package:google_fonts/google_fonts.dart';

class AirportScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final int prisonEndTime;
  final String time;
  final VoidCallback onMenuPressed;

  const AirportScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.prisonEndTime,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  State<AirportScreen> createState() => _AirportScreenState();
}

class _AirportScreenState extends State<AirportScreen> {
  int _prisonEndTime = 0;
  Timer? _countdownTimer;
  String? _selectedDestination;

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

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/airport_bg.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: _isInPrison
            ? Container(
                // Dark overlay that covers behind the GameHeader's rounded corners
                color: Colors.black.withOpacity(0.55),
                child: Column(
                  children: [
                    GameHeader(
                      statsNotifier: SocketService().statsNotifier,
                      time: widget.time,
                      onMenuPressed: widget.onMenuPressed,
                    ),
                    Expanded(
                      child: SafeArea(
                        top: false,
                        child: _buildPrisonView(),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  GameHeader(
                    statsNotifier: SocketService().statsNotifier,
                    time: widget.time,
                    onMenuPressed: widget.onMenuPressed,
                  ),
                  Expanded(
                    child: SafeArea(
                      top: false,
                      child: _buildMainContent(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ==================== PRISON VIEW ====================
  Widget _buildPrisonView() {
    return Center(
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
    );
  }

  // ==================== MAIN AIRPORT CONTENT ====================
  Widget _buildMainContent() {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, currentStats, child) {
        final socketService = SocketService();
        final available = socketService.normalLocations
            .where((city) => city != currentStats['location'])
            .toList();

        final int? cost = _selectedDestination != null
            ? socketService.travelCosts[_selectedDestination!]
            : null;

        final bool canTravel = _selectedDestination != null &&
            cost != null &&
            (currentStats['balance'] ?? 0) >= cost;

        return Column(
          children: [
            // ==================== TITLE ====================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.90),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Center(
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: "NATIONAL",
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color.fromARGB(220, 60, 60, 60),
                                ),
                              ),
                              TextSpan(
                    text:"              .", style: TextStyle( fontSize: 16, color: Color.fromARGB(0, 60, 60, 60)),
                  ),
                              TextSpan(
                                text: '\nAIRPORT\n',
                                style: GoogleFonts.bebasNeue(
                                  fontSize: 52,
                                  fontWeight: FontWeight.w700,
                                  color: const Color.fromARGB(220, 60, 60, 60),
                                  letterSpacing: 2.5,
                                  height: 1.1,
                                ),
                              ),
                              TextSpan(
                                text: "        OF ${(currentStats['location'] ?? widget.currentLocation).toUpperCase()}",
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color.fromARGB(220, 30, 30, 30),
                                  letterSpacing: 0.5,
                                  height: 0.75,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
            ),

            // ==================== DESTINATION CARDS ====================
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: available.length,
                itemBuilder: (context, index) {
                  final city = available[index];
                  final cityCost = socketService.travelCosts[city] ?? 0;
                  final bool isSelected = _selectedDestination == city;

                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedDestination = city);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.orange.withOpacity(0.15)
                            : Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? Colors.orange : Colors.grey.shade300,
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.flight_takeoff,
                            size: 32,
                            color: isSelected ? Colors.orange : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  city,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.orange.shade800 : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Flight Cost: \$$cityCost',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isSelected ? Colors.orange.shade700 : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.orange, size: 28),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ==================== BOTTOM SECTION ====================
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
                    const Text('Pick a city above 👆', style: TextStyle(fontSize: 18, color: Colors.white70)),

                  const SizedBox(height: 12),

                  if (_selectedDestination == null)
                    const Text('Please select a destination', style: TextStyle(color: Colors.red, fontSize: 16))
                  else if (cost! > (currentStats['balance'] ?? widget.currentBalance))
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

  void _travel() {
    final currentStats = SocketService().statsNotifier.value;
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