import 'package:flutter/material.dart';
import 'socket_service.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  Map<String, dynamic>? _selectedVehicle;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.05,
        vertical: size.height * 0.05,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: size.width * 0.90,
        height: size.height * 0.90,
        child: Column(
          children: [
            // ==================== HEADER (always visible) ====================
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🚗 Garage',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 32),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 2),

            // ==================== PREVIEW / CONFIRMATION SECTION (ALWAYS VISIBLE) ====================
            Padding(
              padding: const EdgeInsets.all(20),
              child: _selectedVehicle == null
                  ? const Center(
                      child: Column(
                        children: [
                          Icon(Icons.directions_car, size: 90, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Select a vehicle from your inventory',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Card(
                          elevation: 6,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.directions_car, size: 80, color: Colors.blue),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedVehicle!['name'] ?? 'Unknown Vehicle',
                                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Power: ${_selectedVehicle!['power'] ?? 0} | Defense: ${_selectedVehicle!['defense'] ?? 0}',
                                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _selectedVehicle!['description'] ?? 'No description available.',
                                        style: const TextStyle(fontSize: 14),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${_selectedVehicle!['name']} added to your fleet!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.blue[700],
                            ),
                            child: const Text(
                              'Assign to Fleet',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            const Divider(height: 1, thickness: 2),

            // ==================== SCROLLABLE FLEET GRID (only this part scrolls) ====================
            Expanded(
              child: ValueListenableBuilder<Map<String, dynamic>>(
                valueListenable: SocketService().statsNotifier,
                builder: (context, stats, child) {
                  final inventory = stats['inventory'] as List<dynamic>? ?? [];
                  final vehicles = inventory.where((item) =>
                      item is Map &&
                      item.containsKey('power') &&
                      item.containsKey('skillReq')).toList();

                  if (vehicles.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                          'No vehicles in inventory yet.\nBuy some from the Store!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 17, color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final double width = constraints.maxWidth;
                      final int columns = (width / 140).clamp(3.0, 6.0).toInt();

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            childAspectRatio: 1.0,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: vehicles.length,
                          itemBuilder: (context, index) {
                            final vehicle = vehicles[index] as Map<String, dynamic>;
                            final isSelected = _selectedVehicle == vehicle;

                            return GestureDetector(
                              onTap: () {
                                setState(() => _selectedVehicle = vehicle);
                              },
                              child: Card(
                                elevation: isSelected ? 12 : 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: isSelected
                                      ? const BorderSide(color: Colors.blue, width: 4)
                                      : BorderSide.none,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.directions_car,
                                      size: 48,
                                      color: isSelected ? Colors.blue : Colors.grey[700],
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          vehicle['name'] ?? 'Vehicle',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18, // base size – FittedBox shrinks it automatically
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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
}