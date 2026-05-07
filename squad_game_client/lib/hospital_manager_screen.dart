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
  // Switch states (you can later save these to Firestore)
  bool offerInjuryHealing = true;
  bool offerOrthopedicServices = true;
  bool offerPerformanceTherapy = false;
  bool offerDiseaseTherapy = false;

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
          // ==================== 2x2 SWITCHES (now ~28% height) ====================
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.2,   // ← Increased from 0.15
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 3,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildSwitch("Injury healing", offerInjuryHealing, (v) {
                    setState(() => offerInjuryHealing = v);
                  }),
                  _buildSwitch("Orthopedic services", offerOrthopedicServices, (v) {
                    setState(() => offerOrthopedicServices = v);
                  }),
                  _buildSwitch("Performance enhancing", offerPerformanceTherapy, (v) {
                    setState(() => offerPerformanceTherapy = v);
                  }),
                  _buildSwitch("Disease therapy", offerDiseaseTherapy, (v) {
                    setState(() => offerDiseaseTherapy = v);
                  }),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // ==================== MAIN CONTENT ====================
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_hospital, size: 120, color: Colors.purple[300]),
                    const SizedBox(height: 24),
                    Text(
                      hospitalName,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 60),

                    // Release Hospital Button
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, Function(bool) onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        value: value,
        onChanged: onChanged,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11),
      ),
    );
  }
}