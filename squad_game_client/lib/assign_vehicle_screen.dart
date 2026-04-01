import 'package:flutter/material.dart';
import 'socket_service.dart';

class AssignVehicleScreen extends StatelessWidget {
  final Map<String, dynamic> driver;
  final VoidCallback? onAssigned;

  const AssignVehicleScreen({
    super.key,
    required this.driver,
    this.onAssigned,
  });

  @override
  Widget build(BuildContext context) {
    final fleet = SocketService().statsNotifier.value['taxiFleet'] as List<dynamic>? ?? [];

    final availableVehicles = fleet.where((v) {
      final vehicle = v as Map<String, dynamic>;
      return (vehicle['assignedDriverName'] == null || vehicle['assignedDriverName'] == '');
    }).toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Assign to ${driver['name'] ?? 'Driver'}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 2),
            Expanded(
              child: availableVehicles.isEmpty
                  ? const Center(
                      child: Text(
                        'No unassigned vehicles in your fleet.\nAssign vehicles from the Garage first!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: availableVehicles.length,
                      itemBuilder: (context, index) {
                        final vehicle = availableVehicles[index] as Map<String, dynamic>;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: const Icon(Icons.directions_car, size: 48, color: Colors.blue),
                            title: Text(
                              vehicle['name'] ?? 'Vehicle',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            subtitle: Text(
                              'Power: ${vehicle['power'] ?? 0} • Health: ${vehicle['health'] ?? 100}/100',
                            ),
                            onTap: () {
                              // driverId is inside the driver map — it is sent correctly
                              SocketService().assignDriverToVehicle(driver, vehicle);

                              // Deselect driver in HR screen
                              onAssigned?.call();

                              Navigator.pop(context);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}