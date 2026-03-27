import 'package:flutter/material.dart';
import 'garage_screen.dart';
import 'hr_screen.dart';
import 'socket_service.dart';

class TaxiTycoonScreen extends StatefulWidget {
  const TaxiTycoonScreen({super.key});

  @override
  State<TaxiTycoonScreen> createState() => _TaxiTycoonScreenState();
}

class _TaxiTycoonScreenState extends State<TaxiTycoonScreen> {
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();

    // NEW: Listen for real server response (fleet-result)
    SocketService().socket?.on('fleet-result', (data) {
      if (data is Map && mounted) {
        final bool success = data['success'] ?? false;
        final String message = data['message'] ?? 'Operation complete';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    SocketService().socket?.off('fleet-result');   // ← Add this line
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndices.isNotEmpty) {
          setState(() => _selectedIndices.clear());
          return false;
        }
        return true;
      },
      child: Scaffold(
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
                        showDialog(
                          context: context,
                          barrierDismissible: true,   // Allows tapping outside to close
                          builder: (context) => const HrScreen(),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Fleet',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  if (_selectedIndices.isNotEmpty)
                    GestureDetector(
                      onTap: _showRemoveConfirmation,
                      child: const Text(
                        'remove from fleet',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
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
                      final bool isSelected = _selectedIndices.contains(index);

                      return GestureDetector(
                        onLongPress: () {
                          setState(() {
                            if (isSelected) {
                              _selectedIndices.remove(index);
                            } else {
                              _selectedIndices.add(index);
                            }
                          });
                        },
                        child: Card(
                          elevation: isSelected ? 0 : 6,
                          color: isSelected ? Colors.yellow.withOpacity(0.25) : null,
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
                                      Text(v['name'] ?? 'Vehicle',
                                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Power: ${v['power'] ?? 0} • Defense: ${v['defense'] ?? 0} • Health: ${v['health'] ?? 100}/100',
                                        style: const TextStyle(fontSize: 15, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(v['description'] ?? '', style: const TextStyle(fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
      ),
    );
  }

  // ==================== CONFIRMATION DIALOG ====================
  void _showRemoveConfirmation() {
    final selectedCount = _selectedIndices.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Fleet?'),
        content: Text(
          'Are you sure you want to remove $selectedCount vehicle${selectedCount == 1 ? '' : 's'} from your fleet?\n\n'
          'They will be moved back to your inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performRemoveFromFleet();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

    // ==================== ACTUAL REMOVAL (MINIMAL DATA FIX) ====================
    void _performRemoveFromFleet() {
      final stats = SocketService().statsNotifier.value;
      final fleet = stats['taxiFleet'] as List<dynamic>? ?? [];

      final vehiclesToRemove = _selectedIndices
          .map((index) {
            final v = fleet[index] as Map<String, dynamic>;
            // Send ONLY the fields the server matches on – eliminates all serialization issues
            return {
              'name': v['name'],
              'power': v['power'],
              'health': v['health'] ?? 100,
            };
          })
          .toList();

      if (vehiclesToRemove.isEmpty) return;

      // Send to server
      SocketService().removeFromFleet(vehiclesToRemove);

      // Clear selection immediately
      setState(() => _selectedIndices.clear());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Removing vehicles from fleet...'),
          backgroundColor: Colors.orange,
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