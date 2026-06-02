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

  @override
  void initState() {
    super.initState();
    offerInjuryHealing = widget.hospital['offerInjuryHealing'] ?? false;
    offerOrthopedicServices = widget.hospital['offerOrthopedicServices'] ?? false;
    offerPerformanceTherapy = widget.hospital['offerPerformanceTherapy'] ?? false;
    offerDiseaseTherapy = widget.hospital['offerDiseaseTherapy'] ?? false;

    _healCost = widget.hospital['customHealCost'] ?? 50;
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
      body: Column(
        children: [
          // ==================== CUSTOM HEAL COST ====================
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text('Heal Cost: ', style: TextStyle(fontSize: 18)),
                    Expanded(
                      child: TextField(
                        controller: _costController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          prefixText: '\$',
                          border: OutlineInputBorder(),
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
              ),
            ),
          ),

          // ==================== 2x2 SWITCHES ====================
          SizedBox(
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
                  }),
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
          ),

          const Divider(height: 1),

          // Rest of your screen (Release button) remains the same
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_hospital, size: 120, color: Colors.purple[300]),
                    const SizedBox(height: 24),
                    Text(hospitalName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 60),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async { 
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
                         },
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), backgroundColor: Colors.red[700]),
                        child: const Text('Release Hospital', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, Function(bool) onChanged) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        value: value,
        onChanged: onChanged,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}