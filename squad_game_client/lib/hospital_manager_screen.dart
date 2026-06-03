import 'package:flutter/material.dart';
import 'status_app_bar.dart';
import 'socket_service.dart';

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

  int _healingTimeInSeconds = 180;

  @override
  void initState() {
    super.initState();
    _syncFromHospitalData(widget.hospital);
  }

  // ==================== NEW: Sync local state from hospital data ====================
  void _syncFromHospitalData(Map<String, dynamic> hospitalData) {
    offerInjuryHealing = hospitalData['offerInjuryHealing'] ?? false;
    offerOrthopedicServices = hospitalData['offerOrthopedicServices'] ?? false;
    offerPerformanceTherapy = hospitalData['offerPerformanceTherapy'] ?? false;
    offerDiseaseTherapy = hospitalData['offerDiseaseTherapy'] ?? false;

    _healCost = (hospitalData['customHealCost'] as num?)?.toInt() ?? 50;
    _costController.text = _healCost.toString();
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

          // ==================== NEW: Healing Time Slider (only in Injury Healing tab) ====================
          if (serviceName == 'Injury Healing') ...[
            const SizedBox(height: 8),
            const Text(
              'Healing Duration',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Slider(
              value: _healingTimeInSeconds.toDouble(),
              min: 180,   // 3:00
              max: 240,   // 4:00
              divisions: 3,
              label: _formatTime(_healingTimeInSeconds),
              onChanged: (double value) {
                setState(() {
                  _healingTimeInSeconds = value.round();
                });
              },
            ),
            // Time labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('3:00', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('3:20', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('3:40', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('4:00', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Placeholder content for the service
          Expanded(
            child: Center(
              child: Text(
                '$serviceName settings will go here',
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ),
          ),

          // Release Hospital button at the bottom of every tab
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
          // Get the latest hospital data from the live notifier
          final String docId = widget.hospital['docId'] ?? '';
          final Map<String, dynamic> freshHospital = 
              (ownership[docId] as Map<String, dynamic>?) ?? widget.hospital;

          // Sync local state if server changed anything (especially auto-disable)
          if (freshHospital['offerInjuryHealing'] != offerInjuryHealing) {
            // Use addPostFrameCallback to avoid setState during build
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
                  final bool canAffordInjuryHealing = balance >= 10;

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
                          _buildSwitch("Injury healing", offerInjuryHealing, (v) {
                              setState(() => offerInjuryHealing = v);
                              _saveSwitchState('offerInjuryHealing', v);
                            }, enabled: canAffordInjuryHealing ),
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
    bool enabled = true,                    // ← NEW parameter
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? Colors.grey[100] : Colors.grey[200],   // Grey out background when disabled
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: enabled ? Colors.black : Colors.grey[600],   // Grey out text
          ),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,                    // ← Disable interaction
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
