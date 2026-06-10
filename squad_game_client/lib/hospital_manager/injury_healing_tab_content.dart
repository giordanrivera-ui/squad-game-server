import 'package:flutter/material.dart';
import '../socket_service.dart';

class InjuryHealingTabContent extends StatefulWidget {
  final Map<String, dynamic> hospital;
  final bool isStartingResearch;
  final void Function(int) onUpdateHealCost; // Changed from VoidCallback to accept the new cost value
  final Function(int) onUpdateHealingDuration;
  final VoidCallback onStartEfficientDoctorsResearch;

  const InjuryHealingTabContent({
    super.key,
    required this.hospital,
    required this.isStartingResearch,
    required this.onUpdateHealCost,
    required this.onUpdateHealingDuration,
    required this.onStartEfficientDoctorsResearch,
  });

  @override
  State<InjuryHealingTabContent> createState() => _InjuryHealingTabContentState();
}

class _InjuryHealingTabContentState extends State<InjuryHealingTabContent> {
  final TextEditingController _costController = TextEditingController();
  int _healingTimeInSeconds = 240;

  @override
  void initState() {
    super.initState();
    _syncFromHospital(widget.hospital);
  }

  @override
  void didUpdateWidget(covariant InjuryHealingTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hospital != oldWidget.hospital) {
      _syncFromHospital(widget.hospital);
    }
  }

  void _syncFromHospital(Map<String, dynamic> hospitalData) {
    // Only sync healing duration (this can change due to research)
    final durationMs = (hospitalData['customHealingDuration'] as num?)?.toInt() ?? 240000;
    final bool hasEfficient = hospitalData['hasEfficientDoctors'] == true;
    final int minClamp = hasEfficient ? 120 : 180;
    _healingTimeInSeconds = (durationMs / 1000).round().clamp(minClamp, 240);
  }

  @override
  void dispose() {
    _costController.dispose();
    super.dispose();
  }

  // ==================== Dynamic Maintenance Fee Calculator ====================
  int _calculateMaintenanceFee(int durationSeconds) {
    if (durationSeconds >= 240) return 10;

    int fee = 10;

    if (durationSeconds < 240) {
      final reductionsTier1 = ((240 - durationSeconds) / 20).floor();
      fee += reductionsTier1.clamp(0, 3) * 4;
    }

    if (durationSeconds < 180) {
      final reductionsTier2 = ((180 - durationSeconds) / 20).floor();
      fee += reductionsTier2 * 5;
    }

    return fee;
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ==================== HEAL COST EDITOR ====================
        Card(
          margin: const EdgeInsets.only(bottom: 24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Heal Cost (paid to you)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _costController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          prefixText: '\$',
                          border: OutlineInputBorder(),
                          hintText: 'Enter amount',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        // Validation and update logic now lives here (where the TextField is)
                        final newCost = int.tryParse(_costController.text);
                        if (newCost == null || newCost < 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a valid cost ≥ \$1')),
                          );
                          return;
                        }
                        widget.onUpdateHealCost(newCost);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ==================== EFFICIENT DOCTORS RESEARCH CARD ====================
        ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: SocketService().hospitalOwnershipNotifier,
          builder: (context, ownership, _) {
            final docId = widget.hospital['docId'] ?? '';
            final freshHospital = (ownership[docId] as Map<String, dynamic>?) ?? widget.hospital;

            final bool hasResearched = freshHospital['hasEfficientDoctors'] == true;
            final int? researchEndTime = freshHospital['efficientDoctorsResearchEndTime'] as int?;
            final bool isResearching = researchEndTime != null && researchEndTime > SocketService().currentServerTime;

            int remainingSeconds = 0;
            if (isResearching) {
              remainingSeconds = ((researchEndTime - SocketService().currentServerTime) / 1000).ceil().clamp(0, 30);
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 24),
              color: hasResearched ? Colors.green[900] : Colors.grey[850],
              child: InkWell(
                onTap: (hasResearched || isResearching || widget.isStartingResearch)
                    ? null
                    : widget.onStartEfficientDoctorsResearch,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hasResearched ? Icons.check_circle : Icons.science,
                            color: hasResearched ? Colors.greenAccent : Colors.amber,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Efficient Doctors',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          if (isResearching)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'RESEARCHING... ${remainingSeconds}s',
                                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            )
                          else if (hasResearched)
                            const Text('✅ RESEARCHED', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))
                          else
                            const Text('\$1000 • 30s', style: TextStyle(color: Colors.amber)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasResearched
                            ? 'Effect: Unlocks 2:00 minimum healing duration with 20-second increments.'
                            : 'Research this technology to reduce the minimum healing time from 3:00 to 2:00 and allow finer control (every 20 seconds).',
                        style: TextStyle(fontSize: 15, color: hasResearched ? Colors.greenAccent : Colors.white70),
                      ),
                      if (!hasResearched && !isResearching)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Tap to begin research →',
                            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // ==================== HEALING DURATION SLIDER + LIVE MAINTENANCE FEE ====================
        ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: SocketService().hospitalOwnershipNotifier,
          builder: (context, ownership, _) {
            final docId = widget.hospital['docId'] ?? '';
            final freshHospital = (ownership[docId] as Map<String, dynamic>?) ?? widget.hospital;
            final bool hasEfficientDoctors = freshHospital['hasEfficientDoctors'] == true;

            final double minTime = hasEfficientDoctors ? 120.0 : 180.0;
            final int divisions = hasEfficientDoctors ? 6 : 3;

            // Auto-clamp when Efficient Doctors research completes
            if (hasEfficientDoctors && _healingTimeInSeconds < 120) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _healingTimeInSeconds = 120;
                  });
                }
              });
            }

            final int currentFee = _calculateMaintenanceFee(_healingTimeInSeconds);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Healing Duration (for new patients)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _healingTimeInSeconds.toDouble().clamp(minTime, 240.0),
                  min: minTime,
                  max: 240,
                  divisions: divisions,
                  label: _formatTime(_healingTimeInSeconds),
                  onChanged: (double value) {
                    setState(() {
                      _healingTimeInSeconds = value.round();
                    });
                  },
                  onChangeEnd: (double value) {
                    widget.onUpdateHealingDuration(value.round());
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: hasEfficientDoctors
                        ? const [
                            Text('2:00', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('2:20', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('2:40', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('3:00', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('3:20', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('3:40', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('4:00', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ]
                        : const [
                            Text('3:00', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('3:20', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('3:40', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('4:00', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasEfficientDoctors
                      ? 'Efficient Doctors researched — 2:00 minimum unlocked'
                      : 'Research "Efficient Doctors" to unlock 2:00 minimum',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 16),

                // Live Maintenance Fee
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_money, color: Colors.red, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Maintenance Fee',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.red),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$$currentFee every 2 minutes',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ],
    );
  }
}
