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
  bool _scouted = false; // switches UI after successful scout

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

    // Tell server to generate drivers and deduct cost
    SocketService().scoutDrivers(count);

    // UI will switch automatically when stats update
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

        // If we have scouted drivers, show them instead of scout UI
        if (scoutedDrivers.isNotEmpty) {
          _scouted = true;
        }

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
                // HEADER
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('👥 Human Resource', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close, size: 32), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 2),

                // PREVIEW SECTION (hidden when keyboard is open)
                Visibility(
                  visible: !keyboardVisible,
                  child: Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_alt, size: 120, color: Colors.grey),
                            const SizedBox(height: 24),
                            const Text('No drivers hired yet', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text(
                              'Scout for talented drivers to join your taxi fleet.\nThey will generate passive income over time.',
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

                // BOTTOM SECTION – either Scout UI or Scouted Drivers list
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
        );
      },
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
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              );
            },
          ),
        ),
      ],
    );
  }
}