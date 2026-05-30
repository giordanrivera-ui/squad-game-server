import 'package:flutter/material.dart';
import 'public_hospital_screen.dart';
import 'hospital_manager_screen.dart';
import 'socket_service.dart';
import 'owned_hospitals_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HospitalScreen extends StatelessWidget {
  const HospitalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().hospitalOwnershipNotifier,
      builder: (context, ownership, child) {
        // Check if player owns at least one hospital
        final ownsHospital = ownership.values.any((h) {
          final data = h as Map<String, dynamic>;
          return data['ownerEmail'] == currentUserEmail;
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Hospital Services'),
            actions: [
              if (ownsHospital)
                IconButton(
                  icon: const Icon(Icons.settings, size: 28),
                  tooltip: 'Manage Hospitals',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnedHospitalsScreen()),
                    );
                  },
                ),
            ],
          ),
          body: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: SocketService().statsNotifier,
            builder: (context, stats, child) {
              final String currentLocation = stats['location'] ?? 'Unknown';
              final int numHospitals = SocketService().hospitalCounts[currentLocation] ?? 1;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(numHospitals, (index) {
                  final hospitalIndex = index + 1;
                  final isPublic = hospitalIndex == 1;

                  final key = '${currentLocation}-hospital-${hospitalIndex}';
                  final hospitalData = ownership[key] as Map<String, dynamic>? ?? {};

                  final ownerEmail = hospitalData['ownerEmail'] as String?;
                  final ownerName = hospitalData['ownerDisplayName'] as String?;
                  final isOwnedByMe = ownerEmail == currentUserEmail;

                  // Extract active services
                  final List<String> activeServices = [];
                  if (hospitalData['offerInjuryHealing'] == true) activeServices.add('Injury Healing');
                  if (hospitalData['offerOrthopedicServices'] == true) activeServices.add('Orthopedic');
                  if (hospitalData['offerPerformanceTherapy'] == true) activeServices.add('Performance');
                  if (hospitalData['offerDiseaseTherapy'] == true) activeServices.add('Disease Therapy');

                  return Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: isPublic
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const PublicHospitalScreen()),
                              );
                            }
                          : () async {
                              if (ownerName == null) {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Claim Private Hospital'),
                                    content: Text('Claim this private hospital in $currentLocation?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Claim')),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  SocketService().socket?.emit('claim-hospital', {
                                    'location': currentLocation,
                                    'index': hospitalIndex,
                                  });
                                }
                              } else if (isOwnedByMe) {
                                // Open manager screen if you own it
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => HospitalManagerScreen(hospital: {...hospitalData, 'docId': key}),
                                  ),
                                );
                              }
                            },
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(
                              isPublic ? Icons.local_hospital : Icons.business,
                              size: 60,
                              color: isPublic ? Colors.green : Colors.purple,
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isPublic 
                                        ? '$currentLocation Public Hospital'
                                        : 'Private Hospital #$hospitalIndex',
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),

                                  if (isPublic)
                                    const Text('Standard healing • Orthopedic Surgeon', style: TextStyle(fontSize: 16, color: Colors.grey))
                                  else if (ownerName != null)
                                    Text('Owned by $ownerName', style: const TextStyle(fontSize: 16, color: Colors.green))
                                  else
                                    const Text('Unclaimed • Tap to claim', style: TextStyle(fontSize: 16, color: Colors.orange)),

                                  const SizedBox(height: 10),

                                  // ==================== SERVICES DISPLAY ====================
                                  if (!isPublic && ownerName != null) ...[
                                    const Text('Services Offered:', style: TextStyle(fontSize: 15, color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    if (activeServices.isEmpty)
                                      const Text('No services enabled yet', style: TextStyle(fontSize: 15, color: Colors.grey, fontStyle: FontStyle.italic))
                                    else
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: activeServices.map((service) => Chip(
                                          label: Text(service, style: const TextStyle(fontSize: 13)),
                                          backgroundColor: Colors.purple[100],
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        )).toList(),
                                      ),
                                  ],
                                ],
                              ),
                            ),

                            if (!isPublic && ownerName == null)
                              const Icon(Icons.arrow_forward_ios, color: Colors.orange),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        );
      },
    );
  }
}