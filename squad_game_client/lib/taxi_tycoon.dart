import 'package:flutter/material.dart';
import 'garage_screen.dart';
import 'hr_screen.dart';
import 'socket_service.dart';
import 'assign_vehicle_screen.dart';
import 'dart:async';

class TaxiTycoonScreen extends StatefulWidget {
  const TaxiTycoonScreen({super.key});

  @override
  State<TaxiTycoonScreen> createState() => _TaxiTycoonScreenState();
}

class _TaxiTycoonScreenState extends State<TaxiTycoonScreen> {
  final Set<int> _selectedIndices = {};
  final Set<int> _selectedDriverIndices = {};

  int? _getNextSalaryTime() {
    final hired = SocketService().statsNotifier.value['hiredDrivers'] as List<dynamic>? ?? [];
    if (hired.isEmpty) return null;

    int? earliest;
    for (final driver in hired) {
      final nextTime = driver['nextSalaryPaymentTime'] as int?;
      if (nextTime != null && (earliest == null || nextTime < earliest)) {
        earliest = nextTime;
      }
    }
    return earliest;
  }

  Timer? _jobRefreshTimer;

  @override
  void initState() {
    super.initState();
    
    // NEW: Refresh UI every second so countdowns are live
    _jobRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

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
    _jobRefreshTimer?.cancel();   // ← NEW: Clean up timer
    SocketService().socket?.off('fleet-result');
    super.dispose();
  }

  // ==================== NEW: Toggle driver selection on tap ====================
  void _toggleDriverSelection(int index) {
    setState(() {
      if (_selectedDriverIndices.contains(index)) {
        _selectedDriverIndices.remove(index);
      } else {
        _selectedDriverIndices.add(index);
      }
    });
  }

  // ==================== NEW: Clear driver selection (when tapping "fire driver") ====================
  void _clearDriverSelection() {
    setState(() => _selectedDriverIndices.clear());
  }

  bool _isDriverAssigned(int index) {
    final hired = SocketService().statsNotifier.value['hiredDrivers'] as List<dynamic>? ?? [];
    if (index >= hired.length) return false;
    final driver = hired[index] as Map<String, dynamic>;

    final fleet = SocketService().statsNotifier.value['taxiFleet'] as List<dynamic>? ?? [];
    return fleet.any((v) {
      final vehicle = v as Map<String, dynamic>;
      return vehicle['assignedDriverName'] == driver['name'];
    });
  }

  void _unassignSelectedDriver(String driverName) {
    SocketService().unassignDriverFromVehicle(driverName);
    _clearDriverSelection(); // optional: clear selection after unassign
  }

    // ==================== FIRE CONFIRMATION + ACTUAL FIRING ====================
  void _showFireConfirmation() {
    final hired = SocketService().statsNotifier.value['hiredDrivers'] as List<dynamic>? ?? [];
    final fleet = SocketService().statsNotifier.value['taxiFleet'] as List<dynamic>? ?? [];

    final selectedDrivers = _selectedDriverIndices
        .map((index) => hired[index] as Map<String, dynamic>)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _selectedDriverIndices.length > 1 ? 'Fire Selected Drivers?' : 'Fire Driver?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: selectedDrivers.map((driver) {
              final bool isAssigned = fleet.any((v) {
                final vehicle = v as Map<String, dynamic>;
                return vehicle['assignedDriverName'] == driver['name'];
              });

              return ListTile(
                leading: const Icon(Icons.person, color: Colors.purple),
                title: Text(driver['name'] ?? 'Unknown Driver'),
                subtitle: Text(
                  'Skill: ${driver['drivingSkill'] ?? 0} • Salary: \$${driver['salary'] ?? 0}\n'
                  'Assigned to vehicle: ${isAssigned ? 'Yes' : 'No'}',
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // === ACTUAL FIRING ===
              SocketService().fireDrivers(selectedDrivers);
              _clearDriverSelection();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Confirm Fire'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndices.isNotEmpty || _selectedDriverIndices.isNotEmpty) {
          setState(() {
            _selectedIndices.clear();
            _selectedDriverIndices.clear();
          });
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
                      onTap: () => _openGarage(context)
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildBigButton(
                      context, 
                      title: "HR", 
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

                        // ==================== DRIVERS SECTION ====================
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Drivers', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),

                  // Live salary countdown when nothing is selected
                  if (_selectedDriverIndices.isEmpty)
                    ValueListenableBuilder<Map<String, dynamic>>(
                      valueListenable: SocketService().statsNotifier,
                      builder: (context, stats, child) {
                        final nextSalary = _getNextSalaryTime();
                        if (nextSalary == null) return const SizedBox.shrink();

                        final now = SocketService().currentServerTime;
                        final remainingMs = nextSalary - now;
                        if (remainingMs <= 0) {
                          return const Text(
                            'Salaries due now',
                            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                          );
                        }

                        final minutes = (remainingMs / 60000).floor();
                        final seconds = ((remainingMs % 60000) / 1000).floor();

                        return Text(
                          'Next salaries in ${minutes}m ${seconds.toString().padLeft(2, '0')}s',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        );
                      },
                    )

                  // Selection options (shown only when drivers are selected)
                  else if (_selectedDriverIndices.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedDriverIndices.length == 1)
                          GestureDetector(
                            onTap: () {
                              final selectedIndex = _selectedDriverIndices.first;
                              final hired = SocketService().statsNotifier.value['hiredDrivers'] as List<dynamic>? ?? [];
                              final driver = hired[selectedIndex] as Map<String, dynamic>;

                              final fleet = SocketService().statsNotifier.value['taxiFleet'] as List<dynamic>? ?? [];
                              bool isAssigned = fleet.any((v) {
                                final vehicle = v as Map<String, dynamic>;
                                return vehicle['assignedDriverName'] == driver['name'];
                              });

                              if (isAssigned) {
                                _unassignSelectedDriver(driver['name']);
                              } else {
                                showDialog(
                                  context: context,
                                  builder: (_) => AssignVehicleScreen(
                                    driver: driver,
                                    onAssigned: _clearDriverSelection,
                                  ),
                                );
                              }
                            },
                            child: Text(
                              _isDriverAssigned(_selectedDriverIndices.first) ? 'unassign' : 'assign vehicle',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                          ),

                        if (_selectedDriverIndices.length == 1)
                          const SizedBox(width: 16),

                        // FIRE BUTTON – now shows confirmation dialog
                        GestureDetector(
                          onTap: _showFireConfirmation,
                          child: Text(
                            _selectedDriverIndices.length > 1 ? 'fire drivers' : 'fire driver',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: ValueListenableBuilder<Map<String, dynamic>>(
                valueListenable: SocketService().statsNotifier,
                builder: (context, stats, child) {
                  final hired = stats['hiredDrivers'] as List<dynamic>? ?? [];
                  final fleet = stats['taxiFleet'] as List<dynamic>? ?? [];

                  if (hired.isEmpty) {
                    return const Center(
                      child: Text(
                        'No drivers hired yet.\nScout and hire some!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: hired.length,
                    itemBuilder: (context, index) {
                      final d = hired[index] as Map<String, dynamic>;
                      final bool isSelected = _selectedDriverIndices.contains(index);

                      // Find if this driver is assigned to any vehicle
                      String? assignedVehicleName;
                      for (final v in fleet) {
                        final vehicle = v as Map<String, dynamic>;
                        if (vehicle['assignedDriverName'] == d['name']) {
                          assignedVehicleName = vehicle['name'];
                          break;
                        }
                      }

                      return GestureDetector(
                        onTap: () => _toggleDriverSelection(index),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: isSelected
                                ? const BorderSide(color: Colors.blue, width: 3)
                                : BorderSide.none,
                          ),
                          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.person, size: 48, color: Colors.purple),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d['name'] ?? 'Driver',
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Skill: ${d['drivingSkill'] ?? 0} • Salary: \$${d['salary'] ?? 0} • Potential: ${d['potential'] ?? 0}',
                                      ),
                                      const SizedBox(height: 8),

                                      // ← NEW: Assignment indicator
                                      if (assignedVehicleName != null)
                                        Row(
                                          children: [
                                            const Icon(Icons.directions_car, size: 18, color: Colors.green),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Assigned to $assignedVehicleName',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                color: Colors.green,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        const Text(
                                          'No vehicle assigned',
                                          style: TextStyle(fontSize: 15, color: Colors.grey),
                                        ),
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

            const Divider(height: 2, thickness: 2),

            // ==================== FLEET SECTION  ====================
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
                                      Text(
                                        v['name'] ?? 'Vehicle',
                                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Power: ${v['power'] ?? 0} • Defense: ${v['defense'] ?? 0} • Health: ${v['health'] ?? 100}/100',
                                        style: const TextStyle(fontSize: 15, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(v['description'] ?? '', style: const TextStyle(fontSize: 14)),

                                      // ==================== STATUS + LIVE COUNTDOWN ====================
                                      if (v['assignedDriverName'] != null && v['assignedDriverName'] != '')
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Status
                                              Row(
                                                children: [
                                                  Icon(
                                                    v['status'] == 'Job ongoing' ? Icons.work : Icons.search,
                                                    size: 18,
                                                    color: v['status'] == 'Job ongoing' ? Colors.orange : Colors.green,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    v['status'] ?? 'Finding customer',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      color: v['status'] == 'Job ongoing' ? Colors.orange : Colors.green,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),

                                              // Live Job Countdown (only when Job ongoing)
                                              if (v['status'] == 'Job ongoing' && v['jobEndTime'] != null)
                                                ValueListenableBuilder<Map<String, dynamic>>(
                                                  valueListenable: SocketService().statsNotifier,
                                                  builder: (context, stats, child) {
                                                    final now = DateTime.now().millisecondsSinceEpoch;
                                                    final endTime = (v['jobEndTime'] as num?)?.toInt() ?? 0;
                                                    final remainingMs = endTime - now;

                                                    if (remainingMs <= 0) {
                                                      return const SizedBox.shrink();
                                                    }

                                                    final minutes = (remainingMs / 60000).floor();
                                                    final seconds = ((remainingMs % 60000) / 1000).floor();

                                                    return Padding(
                                                      padding: const EdgeInsets.only(top: 4),
                                                      child: Text(
                                                        'Job ends in ${minutes}m ${seconds}s',
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          color: Colors.orange,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
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
        height: 100,
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
            const SizedBox(height: 6),
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