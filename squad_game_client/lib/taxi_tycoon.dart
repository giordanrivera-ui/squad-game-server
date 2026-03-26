import 'package:flutter/material.dart';
import 'garage_screen.dart';
import 'socket_service.dart';

class TaxiTycoonScreen extends StatelessWidget {
  const TaxiTycoonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚕 Taxi Tycoon'),
        backgroundColor: Colors.blue[900],
      ),
      body: Column(
        children: [
          // TOP SECTION – Two big buttons
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: _buildBigButton(
                    context,
                    title: "Vehicles",
                    icon: Icons.directions_car,
                    color: Colors.blue,
                    onTap: () => _openGarage(context),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildBigButton(
                    context,
                    title: "Human Resource",
                    icon: Icons.people_alt,
                    color: Colors.purple,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Human Resource coming soon!')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 2, thickness: 2),

          // MIDDLE SECTION – Drivers
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Drivers', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Center(
              child: Text(
                'Your hired drivers will appear here',
                style: TextStyle(fontSize: 17, color: Colors.grey),
              ),
            ),
          ),

          const Divider(height: 2, thickness: 2),

          // BOTTOM SECTION – Fleet
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Fleet', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            flex: 3,
            child: ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: SocketService().statsNotifier,
              builder: (context, stats, child) {
                final fleet = stats['taxiFleet'] as List<dynamic>? ?? [];

                if (fleet.isEmpty) {
                  return const Center(
                    child: Text(
                      'Your taxi fleet is empty.\nAssign vehicles from the Garage!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: fleet.length,
                  itemBuilder: (context, index) {
                    final v = fleet[index] as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car, size: 60, color: Colors.blue),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v['name'] ?? 'Vehicle', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('Power: ${v['power'] ?? 0} • Defense: ${v['defense'] ?? 0} • Health: ${v['health'] ?? 100}/100',
                                      style: const TextStyle(fontSize: 15, color: Colors.grey)),
                                  const SizedBox(height: 8),
                                  Text(v['description'] ?? '', style: const TextStyle(fontSize: 14)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigButton(BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withOpacity(0.8)]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: Colors.white),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _openGarage(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const GarageScreen(),
    );
  }
}