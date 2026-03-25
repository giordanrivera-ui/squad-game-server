import 'package:flutter/material.dart';
import 'socket_service.dart'; // For future stats if needed
import 'status_app_bar.dart'; // Reuse the nice app bar
import 'properties_screen.dart';

class BusinessesScreen extends StatelessWidget {
  const BusinessesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        return Scaffold(
          appBar: StatusAppBar(
            title: 'Businesses',
            statsNotifier: SocketService().statsNotifier,
            time: 'Live', // You can pass real time if you want
            onMenuPressed: () => Navigator.pop(context),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Taxi Tycoon - Large vertical rectangle
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // TODO: Open Taxi Tycoon screen in future
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🚕 Taxi Tycoon coming soon!')),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
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
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                
                // Real Estate - Large vertical rectangle
Expanded(
  child: GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PropertiesScreen(
            initialStats: SocketService().statsNotifier.value,
          ),
        ),
      );
    },
    child: Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
              color: Colors.white.withOpacity(0.9),
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
      },
    );
  }
}