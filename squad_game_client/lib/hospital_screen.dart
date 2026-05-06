import 'package:flutter/material.dart';
import 'public_hospital_screen.dart';
import 'socket_service.dart';

class HospitalScreen extends StatelessWidget {
  const HospitalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        final String currentLocation = stats['location'] ?? 'Unknown';
        final int numHospitals = SocketService().hospitalCounts[currentLocation] ?? 1;

        return Scaffold(
          appBar: AppBar(title: const Text('Hospital Services')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ==================== PUBLIC HOSPITAL (always first) ====================
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PublicHospitalScreen()),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Icon(Icons.local_hospital, size: 60, color: Colors.green),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Public Hospital',
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Standard healing • Orthopedic Surgeon',
                                style: TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ==================== ADDITIONAL HOSPITALS (player-run) ====================
              if (numHospitals >= 2)
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Player-run hospital coming soon!'),
                          backgroundColor: Colors.purple,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const Icon(Icons.business, size: 60, color: Colors.purple),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Private Hospital',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Player-run clinic • Advanced services',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}