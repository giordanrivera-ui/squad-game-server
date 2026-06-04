import 'package:flutter/material.dart';
import 'status_app_bar.dart';
import 'socket_service.dart';
import 'dart:async';

class HospitalManagerScreen extends StatefulWidget {
  final Map<String, dynamic> hospital;

  const HospitalManagerScreen({super.key, required this.hospital});

  @override
  State<HospitalManagerScreen> createState() => _HospitalManagerScreenState();
}

class _HospitalManagerScreenState extends State<HospitalManagerScreen> {
  late bool offerInjuryHealing;
  late bool offerOrthopedicServices;
  late bool offerPerformanceTherapy;
  late bool offerDiseaseTherapy;

  late int _healCost;
  final TextEditingController _costController = TextEditingController();

  // ==================== NEW: Healing Duration Slider State ====================
  int _healingTimeInSeconds = 240; // Default 4:00
  Map<String, dynamic>? _lastSyncedHospitalData;

  // ==================== EFFICIENT DOCTORS RESEARCH STATE ====================
  Timer? _researchTimer;
  bool _isStartingResearch = false;

  @override
  void initState() {
    super.initState();
    _syncFromHospitalData(widget.hospital);
    _startResearchTimer();

    SocketService().socket?.on('research-result', _onResearchResult);
  }

  @override
  void dispose() {
    // ✅ ADD THIS LINE - Cleanly remove the listener
    SocketService().socket?.off('research-result', _onResearchResult);
    
    _researchTimer?.cancel();
    super.dispose();
  }

  void _onResearchResult(dynamic data) {
    if (!mounted) return;

    if (data is Map<String, dynamic>) {
      final bool success = data['success'] ?? false;
      final String message = data['message'] ?? 'Research action completed.';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        setState(() => _isStartingResearch = false);
      }
    }
  }

  void _startResearchTimer() {
    _researchTimer?.cancel();
    _researchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      // === AUTO-CLAIM RESEARCH WHEN TIMER HITS ZERO ===
      final docId = widget.hospital['docId'];
      if (docId != null) {
        final fresh = SocketService().hospitalOwnershipNotifier.value[docId] 
            as Map<String, dynamic>? ?? widget.hospital;

        final int? researchEndTime = fresh['efficientDoctorsResearchEndTime'] as int?;

        if (researchEndTime != null && researchEndTime > 0 && researchEndTime <= SocketService().currentServerTime) {
            SocketService().socket?.emit('claim-efficient-doctors-research', {'hospitalDocId': docId});
            print('[RESEARCH] Auto-claimed Efficient Doctors research for $docId');
        }
      }

      setState(() {}); // Refresh UI for countdown
    });
  }

  // ==================== Sync local state from hospital data (now includes duration + research) ====================
  void _syncFromHospitalData(Map<String, dynamic> hospitalData) {
    offerInjuryHealing = hospitalData['offerInjuryHealing'] ?? false;
    offerOrthopedicServices = hospitalData['offerOrthopedicServices'] ?? false;
    offerPerformanceTherapy = hospitalData['offerPerformanceTherapy'] ?? false;
    offerDiseaseTherapy = hospitalData['offerDiseaseTherapy'] ?? false;

    _healCost = (hospitalData['customHealCost'] as num?)?.toInt() ?? 50;
    _costController.text = _healCost.toString();

    // NEW: Load custom healing duration (default 240 seconds = 4 minutes)
    final durationMs = (hospitalData['customHealingDuration'] as num?)?.toInt() ?? 240000;
    final bool hasEfficient = hospitalData['hasEfficientDoctors'] == true;
    final int minClamp = hasEfficient ? 120 : 180;
    _healingTimeInSeconds = (durationMs / 1000).round().clamp(minClamp, 240);
  }

    void _saveSwitchState(String field, bool value) {
    final docId = widget.hospital['docId'];
    if (docId == null) return;

    SocketService().socket?.emit('update-hospital-service', {
      'docId': docId,
      'field': field,
      'value': value,
    });
  }

  void _updateHealCost() {
    final newCost = int.tryParse(_costController.text);
    if (newCost == null || newCost < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid cost ≥ \$1')),
      );
      return;
    }

    final docId = widget.hospital['docId'];
    if (docId == null) return;

    SocketService().socket?.emit('update-hospital-heal-cost', {
      'docId': docId,
      'newCost': newCost,
    });

    setState(() => _healCost = newCost);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Heal cost updated to \$$newCost')),
    );
  }

  // ==================== NEW: Update Healing Duration on Server ====================
  void _updateHealingDuration(int seconds) {
    final docId = widget.hospital['docId'];
    if (docId == null) return;

    final durationMs = seconds * 1000;

    SocketService().socket?.emit('update-hospital-healing-duration', {
      'docId': docId,
      'healingDurationMs': durationMs,
    });

    setState(() => _healingTimeInSeconds = seconds);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Healing time updated to ${_formatTime(seconds)}')),
    );
  }
  
  // ==================== Get list of currently active services ====================
  List<String> _getActiveServices() {
    final List<String> active = [];
    if (offerInjuryHealing) active.add('Injury Healing');
    if (offerOrthopedicServices) active.add('Orthopedic Services');
    if (offerPerformanceTherapy) active.add('Performance Therapy');
    if (offerDiseaseTherapy) active.add('Disease Therapy');
    return active;
  }

  // ==================== Dynamic bottom section ====================
  Widget _buildBottomSection() {
    final activeServices = _getActiveServices();

    if (activeServices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_hospital, size: 120, color: Colors.purple[300]),
              const SizedBox(height: 24),
              Text(
                '${widget.hospital['location']} Hospital #${widget.hospital['index']}',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _showReleaseConfirmation,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: Colors.red[700],
                  ),
                  child: const Text(
                    'Release Hospital',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return DefaultTabController(
        length: activeServices.length,
        child: Column(
          children: [
            TabBar(
              isScrollable: activeServices.length > 2,
              tabs: activeServices.map((service) => Tab(text: service)).toList(),
              labelColor: Colors.purple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.purple,
            ),
            Expanded(
              child: TabBarView(
                children: activeServices.map((service) {
                  return _buildServiceTab(service);
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ==================== Content for each service tab ====================
  Widget _buildServiceTab(String serviceName) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
          child: Column(
        children: [
          // ==================== HEAL COST EDITOR (only in Injury Healing tab) ====================
          if (serviceName == 'Injury Healing')
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
                          onPressed: _updateHealCost,
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          // ==================== HEALING DURATION SLIDER (only in Injury Healing tab) ====================
          if (serviceName == 'Injury Healing')
            ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: SocketService().hospitalOwnershipNotifier,
              builder: (context, ownership, _) {
                final docId = widget.hospital['docId'] ?? '';
                final freshHospital = (ownership[docId] as Map<String, dynamic>?) ?? widget.hospital;
                final bool hasEfficientDoctors = freshHospital['hasEfficientDoctors'] == true;

                // Dynamic min / divisions based on research
                final double minTime = hasEfficientDoctors ? 120.0 : 180.0;
                final int divisions = hasEfficientDoctors ? 6 : 3; // 20s steps

                // Clamp current value if research just completed
                if (hasEfficientDoctors && _healingTimeInSeconds < 120) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _healingTimeInSeconds = 120;
                      });
                    }
                  });
                }

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
                        _updateHealingDuration(value.round());
                      },
                    ),
                    // Dynamic time labels
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
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),

          // ==================== EFFICIENT DOCTORS RESEARCH CARD (Injury Healing tab) ====================
          if (serviceName == 'Injury Healing')
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
                    onTap: (hasResearched || isResearching || _isStartingResearch)
                      ? null
                      : () {
                          final docId = widget.hospital['docId'];
                          if (docId != null) {
                            setState(() => _isStartingResearch = true); // Disable tap immediately

                            SocketService().socket?.emit('start-efficient-doctors-research', {
                              'hospitalDocId': docId,
                            });
                          }
                        },
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

          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showReleaseConfirmation,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: Colors.red[700],
              ),
              child: const Text(
                'Release Hospital',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    )
    );
  }

  // ==================== Helper to format seconds into MM:SS ====================
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // ==================== Release confirmation dialog ====================
  Future<void> _showReleaseConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Hospital'),
        content: const Text(
          'Are you sure you want to release this hospital?\n\n'
          'It will no longer belong to you and can be claimed by any other player.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Release Hospital'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      SocketService().socket?.emit('release-hospital', {
        'docId': widget.hospital['docId'],
      });

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hospital released successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String location = widget.hospital['location'] ?? 'Unknown';
    final int index = widget.hospital['index'] ?? 0;
    final String hospitalName = '$location Hospital #$index';

    return Scaffold(
      appBar: StatusAppBar(
        title: hospitalName,
        statsNotifier: SocketService().statsNotifier,
        time: 'Live',
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: SocketService().hospitalOwnershipNotifier,
        builder: (context, ownership, child) {
          final String docId = widget.hospital['docId'] ?? '';
          final Map<String, dynamic> freshHospital = 
              (ownership[docId] as Map<String, dynamic>?) ?? widget.hospital;

          // ==================== ONLY sync if something important changed ====================
          final bool shouldSync = _lastSyncedHospitalData == null ||
              freshHospital['offerInjuryHealing'] != _lastSyncedHospitalData!['offerInjuryHealing'] ||
              freshHospital['customHealCost'] != _lastSyncedHospitalData!['customHealCost'] ||
              freshHospital['customHealingDuration'] != _lastSyncedHospitalData!['customHealingDuration'] ||
              freshHospital['hasEfficientDoctors'] != _lastSyncedHospitalData!['hasEfficientDoctors'] ||
              freshHospital['efficientDoctorsResearchEndTime'] != _lastSyncedHospitalData!['efficientDoctorsResearchEndTime'];

          if (shouldSync) {
            _lastSyncedHospitalData = Map<String, dynamic>.from(freshHospital);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _syncFromHospitalData(freshHospital);
                });
              }
            });
          }

          return Column(
            children: [
              // ==================== 2x2 SWITCHES ====================
ValueListenableBuilder<Map<String, dynamic>>(
  valueListenable: SocketService().statsNotifier,
  builder: (context, stats, _) {
    final int balance = (stats['balance'] ?? 0).toInt();
    final bool canAffordMaintenance = balance >= 10;
    final bool isInjuryHealingCurrentlyOn = freshHospital['offerInjuryHealing'] ?? false;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 6,
          childAspectRatio: 2.8,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildSwitch(
              "Injury healing",
              isInjuryHealingCurrentlyOn,
              (v) {
                setState(() => offerInjuryHealing = v);
                _saveSwitchState('offerInjuryHealing', v);
              },
              enabled: isInjuryHealingCurrentlyOn || canAffordMaintenance,
            ),
            _buildSwitch("Orthopedic services", offerOrthopedicServices, (v) {
              setState(() => offerOrthopedicServices = v);
              _saveSwitchState('offerOrthopedicServices', v);
            }),
            _buildSwitch("Performance enhancing", offerPerformanceTherapy, (v) {
              setState(() => offerPerformanceTherapy = v);
              _saveSwitchState('offerPerformanceTherapy', v);
            }),
            _buildSwitch("Disease therapy", offerDiseaseTherapy, (v) {
              setState(() => offerDiseaseTherapy = v);
              _saveSwitchState('offerDiseaseTherapy', v);
            }),
          ],
        ),
      ),
    );
  },
),

              const Divider(height: 1),

              // ==================== DYNAMIC BOTTOM SECTION ====================
              Expanded(
                child: _buildBottomSection(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitch(
    String label, 
    bool value, 
    Function(bool) onChanged, {
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? Colors.grey[100] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: enabled ? Colors.black : Colors.grey[600],
          ),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
