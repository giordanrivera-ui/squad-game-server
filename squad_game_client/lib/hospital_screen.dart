import 'package:flutter/material.dart';
import 'public_hospital_screen.dart';
import 'socket_service.dart';

class HospitalScreen extends StatelessWidget {
  const HospitalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        final String currentLocation = stats['location'] ?? 'Unknown';
        final int numHospitals = SocketService().hospitalCounts[currentLocation] ?? 1;

        return Scaffold(
          appBar: AppBar(title: const Text('Hospital Services')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: List.generate(numHospitals, (index) {
              final hospitalIndex = index + 1;
              final isPublic = hospitalIndex == 1;

              // Ownership data
              final ownership = SocketService().hospitalOwnershipNotifier.value;
              final key = '${currentLocation}-hospital-${hospitalIndex}';
              final owner = ownership[key] ?? {};
              final ownerName = owner['ownerDisplayName'] ?? null;
              final isOwned = ownerName != null;

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
                          if (!isOwned) {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Claim Private Hospital'),
                                content: Text('Do you want to claim this private hospital in $currentLocation?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Claim'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              SocketService().socket?.emit('claim-hospital', {
                                'location': currentLocation,
                                'index': hospitalIndex,
                              });
                            }
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
                                isPublic ? 'Public Hospital' : 'Private Hospital',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              if (isPublic)
                                const Text('Standard healing • Orthopedic Surgeon', style: TextStyle(fontSize: 16, color: Colors.grey))
                              else if (isOwned)
                                Text('Owned by $ownerName', style: const TextStyle(fontSize: 16, color: Colors.green))
                              else
                                const Text('Unclaimed • Tap to claim', style: TextStyle(fontSize: 16, color: Colors.orange)),
                            ],
                          ),
                        ),
                        if (!isPublic && !isOwned)
                          const Icon(Icons.arrow_forward_ios, color: Colors.orange),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}