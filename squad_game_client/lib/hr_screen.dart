import 'package:flutter/material.dart';
import 'socket_service.dart';

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});

  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> {
  final TextEditingController _scoutCountController = TextEditingController(text: '1');
  int _totalCost = 20;
  bool _scouted = false;

  // Selection tracking
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _scoutCountController.addListener(_updateCost);
    _updateCost();
  }

  void _updateCost() {
    final int count = int.tryParse(_scoutCountController.text) ?? 1;
    final int cost = count * 20;
    setState(() => _totalCost = cost.clamp(20, 10000));
  }

  void _scoutDrivers() {
    final count = int.tryParse(_scoutCountController.text) ?? 1;
    if (count < 1) return;
    SocketService().scoutDrivers(count);
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  int _getSelectedTotalSalary(List<dynamic> drivers) {
    int total = 0;
    for (int i in _selectedIndices) {
      if (i < drivers.length) {
        final driver = drivers[i] as Map<String, dynamic>;
        total += (driver['salary'] as num?)?.toInt() ?? 0;
      }
    }
    return total;
  }

  // NEW: Hire the selected drivers
  void _hireSelectedDrivers(List<dynamic> allDrivers) {
    if (_selectedIndices.isEmpty) return;

    final List<dynamic> driversToHire = _selectedIndices
        .map((i) => allDrivers[i] as Map<String, dynamic>)
        .toList();

    // Send wrapped (same pattern as remove-from-fleet - safer)
    SocketService().hireDriversWrapped(driversToHire);   // ← new method (see below)

    // Do NOT clear selection yet - wait for server confirmation
  }

  Future<void> _confirmAndClear() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Human Resource?'),
        content: const Text(
          'Your currently scouted drivers will be lost and cannot be recovered.\n\nAre you sure you want to leave?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, discard'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      SocketService().clearScoutedDrivers();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _scoutCountController.removeListener(_updateCost);
    _scoutCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        final List<dynamic> scoutedDrivers = stats['scoutedDrivers'] as List<dynamic>? ?? [];

        if (scoutedDrivers.isNotEmpty) {
          _scouted = true;
        } else {
          _selectedIndices.clear();
        }

        return WillPopScope(
          onWillPop: () async {
            await _confirmAndClear();
            return false;
          },
          child: Dialog(
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
                  // HEADER
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: const Text(
                              '👥 Human Resource',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 32),
                          onPressed: _confirmAndClear,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 2),

                  // PREVIEW SECTION
                  Visibility(
                    visible: !keyboardVisible,
                    child: Flexible(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _selectedIndices.isNotEmpty && scoutedDrivers.isNotEmpty
                            ? _buildSelectedPreview(scoutedDrivers)
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.people_alt, size: 110, color: Colors.grey),
                                    const SizedBox(height: 20),
                                    const Text('No drivers hired yet', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Scout for talented drivers to join your taxi fleet.',
                                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),

                  const Divider(height: 1, thickness: 2),

                  // BOTTOM SECTION
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _scouted && scoutedDrivers.isNotEmpty
                          ? _buildScoutedDriversList(scoutedDrivers)
                          : _buildScoutUI(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Preview when drivers are selected
  Widget _buildSelectedPreview(List<dynamic> allDrivers) {
    final totalSalary = _getSelectedTotalSalary(allDrivers);

    return Column(
      children: [
        // Hire button at the top of preview
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _hireSelectedDrivers(allDrivers),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: Colors.green[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              'Hire for \$$totalSalary/hour',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 20),

        const Text('Selected Drivers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: _selectedIndices.length,
            itemBuilder: (context, i) {
              final index = _selectedIndices.elementAt(i);
              final driver = allDrivers[index] as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.person, color: Colors.purple),
                  title: Text(driver['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Skill: ${driver['drivingSkill']} • Salary: \$${driver['salary']} • Potential: ${driver['potential']}',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScoutUI() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _scoutCountController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Number of drivers',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: ElevatedButton(
                onPressed: _scoutDrivers,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: Colors.purple[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Scout for Drivers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Total Cost: ', style: TextStyle(fontSize: 18, color: Colors.white70)),
              Text('\$$_totalCost', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(width: 8),
              Text('(\$20 per recruit)', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScoutedDriversList(List<dynamic> drivers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Scouted Drivers', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index] as Map<String, dynamic>;
              final bool isSelected = _selectedIndices.contains(index);

              return GestureDetector(
                onTap: () => _toggleSelection(index),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isSelected ? const BorderSide(color: Colors.blue, width: 3) : BorderSide.none,
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
                              Text(driver['name'] ?? 'Unknown', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Driving Skill: ${driver['drivingSkill'] ?? 0} • Salary: \$${driver['salary'] ?? 0} • Potential: ${driver['potential'] ?? 0}'),
                              if (driver['weapon'] != null)
                                Text('Weapon: ${driver['weapon']['name']}', style: const TextStyle(color: Colors.orange)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}