import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'properties_screen.dart';
import 'taxi_tycoon/taxi_tycoon.dart';
import 'game_header.dart';

class BusinessesScreen extends StatelessWidget {
  final String time;
  final VoidCallback onMenuPressed;

  const BusinessesScreen({
    super.key,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            // ==================== GAME HEADER ====================
            GameHeader(
              statsNotifier: SocketService().statsNotifier,
              time: time,
              onMenuPressed: onMenuPressed,
            ),

            // ==================== CONTENT ====================
            Expanded(
              child: SafeArea(
                top: false,
                child: Container(
                  color: Colors.black.withOpacity(0.15),
                  child: Column(
                    children: [
                      // TAXI TYCOON BUTTON
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const TaxiTycoonScreen()),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage('assets/business-taxi.jpg'),
                                fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(
                                  Colors.black.withOpacity(0.40),
                                  BlendMode.darken,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.local_taxi, size: 110, color: Colors.white),
                                const SizedBox(height: 24),
                                const Text(
                                  'TAXI TYCOON',
                                  style: TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Own a fleet • Earn passive income',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white.withOpacity(0.95),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      //const SizedBox(height: 32),

                      // REAL ESTATE BUTTON
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PropertiesScreen(initialStats: {}), // Pass stats if needed
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage('assets/business-realestate.jpg'),
                                fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(
                                  Colors.black.withOpacity(0.40),
                                  BlendMode.darken,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.apartment, size: 110, color: Colors.white),
                                const SizedBox(height: 24),
                                const Text(
                                  'REAL ESTATE',
                                  style: TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Properties • Upgrades • Passive income',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white.withOpacity(0.95),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}