import 'package:flutter/material.dart';
import 'public_hospital_screen.dart';
import 'private_hospital_heal_screen.dart';
import 'hospital_manager/hospital_manager_screen.dart';
import 'socket_service.dart';
import 'game_header.dart';
import 'hospital_manager/owned_hospitals_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class HospitalScreen extends StatelessWidget {
  final String time;
  final VoidCallback onMenuPressed;

  const HospitalScreen({
    super.key,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().hospitalOwnershipNotifier,
      builder: (context, ownership, child) {
        final ownsHospital = ownership.values.any((h) {
          final data = h as Map<String, dynamic>;
          return data['ownerEmail'] == currentUserEmail;
        });

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/hospital-background.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: Column(
              children: [
                // ==================== GAME HEADER (no title) ====================
                GameHeader(
                  statsNotifier: SocketService().statsNotifier,
                  time: time,
                  onMenuPressed: onMenuPressed,
                ),

                // ==================== TITLE + ACTION BUTTONS (with white semi-transparent background) ====================
Padding(
  padding: const EdgeInsets.fromLTRB(16, 26, 16, 2),
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.78),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        // Left spacer to help center the title
        const SizedBox(width: 36),

        // Centered Title
        Expanded(
          child: Center(
            child: Text(
              'Hospital Services',
              style: GoogleFonts.bebasNeue(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.4,
                color: const Color.fromARGB(220, 17, 15, 128),
                // shadows: [
                //   Shadow(
                //     offset: const Offset(0, 3),
                //     blurRadius: 6,
                //     color: Colors.black.withOpacity(0.3),
                //   ),
                //   Shadow(
                //     offset: const Offset(-1, -1),
                //     blurRadius: 3,
                //     color: const Color.fromARGB(255, 121, 121, 121).withOpacity(0.4),
                //   ),
                // ],
              ),
            ),
          ),
        ),

        // Settings Icon (only if player owns a hospital)
        if (ownsHospital)
          IconButton(
            icon: const Icon(Icons.settings, size: 26, color: Color.fromARGB(220, 17, 15, 128)),
            tooltip: 'Manage My Hospitals',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OwnedHospitalsScreen()),
              );
            },
          ),
      ],
    ),
  ),
),
                // ==================== HOSPITAL LIST ====================
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: Container(
                      color: Colors.white.withOpacity(0.05),
                      child: ValueListenableBuilder<Map<String, dynamic>>(
                        valueListenable: SocketService().statsNotifier,
                        builder: (context, stats, child) {
                          final String currentLocation = stats['location'] ?? 'Unknown';
                          final int numHospitals = SocketService().hospitalCounts[currentLocation] ?? 1;

                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: List.generate(numHospitals, (index) {
                              final hospitalIndex = index + 1;
                              final isPublic = hospitalIndex == 1;

                              final key = '$currentLocation-hospital-$hospitalIndex';
                              final hospitalData = ownership[key] as Map<String, dynamic>? ?? {};

                              final ownerEmail = hospitalData['ownerEmail'] as String?;
                              final ownerName = hospitalData['ownerDisplayName'] as String?;
                              final isOwnedByMe = ownerEmail == currentUserEmail;

                              // Active services
                              final List<String> activeServices = [];
                              if (hospitalData['offerInjuryHealing'] == true) activeServices.add('Injury Healing');
                              if (hospitalData['offerOrthopedicServices'] == true) activeServices.add('Orthopedic');
                              if (hospitalData['offerEnhancedStamina'] == true || hospitalData['offerEnhancedConstitution'] == true) {
                                activeServices.add('Performance');
                              }
                              if (hospitalData['offerDiseaseTherapy'] == true) activeServices.add('Disease Therapy');

                              return Card(
                                elevation: 6,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                margin: const EdgeInsets.only(bottom: 16),
                                child: isOwnedByMe && !isPublic
                                    // ==================== OWNER VIEW ====================
                                    ? IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              flex: 5,
                                              child: InkWell(
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(20),
                                                  bottomLeft: Radius.circular(20),
                                                ),
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => PrivateHospitalHealScreen(
                                                        hospital: {...hospitalData, 'docId': key},
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.all(20),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.business, size: 60, color: Colors.purple),
                                                      const SizedBox(width: 20),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Text(
                                                              'Private Hospital #$hospitalIndex',
                                                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                                            ),
                                                            const SizedBox(height: 6),
                                                            Text('Owned by You', style: const TextStyle(fontSize: 16, color: Colors.green)),
                                                            const SizedBox(height: 10),
                                                            if (activeServices.isNotEmpty)
                                                              Wrap(
                                                                spacing: 6,
                                                                children: activeServices.map((service) => Chip(
                                                                  label: Text(service, style: const TextStyle(fontSize: 12)),
                                                                  backgroundColor: Colors.purple[100],
                                                                )).toList(),
                                                              )
                                                            else
                                                              const Text('No services enabled', style: TextStyle(fontSize: 14, color: Colors.grey)),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                              borderRadius: const BorderRadius.only(
                                                topRight: Radius.circular(20),
                                                bottomRight: Radius.circular(20),
                                              ),
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => HospitalManagerScreen(
                                                      hospital: {...hospitalData, 'docId': key},
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Container(
                                                width: 78,
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    begin: Alignment.centerLeft,
                                                    end: Alignment.centerRight,
                                                    colors: [
                                                      Color.fromARGB(255, 67, 18, 128),
                                                      Color.fromARGB(255, 104, 26, 138),
                                                    ],
                                                  ),
                                                  borderRadius: const BorderRadius.only(
                                                    topRight: Radius.circular(20),
                                                    bottomRight: Radius.circular(20),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.3),
                                                      blurRadius: 4,
                                                      offset: const Offset(-2, 0),
                                                    ),
                                                  ],
                                                ),
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(Icons.settings, color: Colors.white, size: 22),
                                                    const SizedBox(height: 8),
                                                    const RotatedBox(
                                                      quarterTurns: 1,
                                                      child: Text(
                                                        'MANAGE',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 15,
                                                          letterSpacing: 1.6,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    // ==================== NON-OWNER VIEW ====================
                                    : InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () async {
                                          if (isPublic) {
                                            Navigator.push(context, MaterialPageRoute(builder: (_) => const PublicHospitalScreen()));
                                          } else if (ownerName == null) {
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
                                          } else {
                                            if (hospitalData['offerInjuryHealing'] == true) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => PrivateHospitalHealScreen(
                                                    hospital: {...hospitalData, 'docId': key},
                                                  ),
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text("This hospital currently has no services enabled.")),
                                              );
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
                                                      isPublic
                                                          ? '$currentLocation Public Hospital'
                                                          : 'Private Hospital #$hospitalIndex',
                                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    if (isPublic)
                                                      const Text('Standard healing • Orthopedic Surgeon', style: TextStyle(fontSize: 15, color: Colors.grey))
                                                    else if (ownerName != null)
                                                      Text('Owned by $ownerName', style: const TextStyle(fontSize: 16, color: Colors.green))
                                                    else
                                                      const Text('Unclaimed • Tap to claim', style: TextStyle(fontSize: 16, color: Colors.orange)),
                                                    const SizedBox(height: 10),
                                                    if (!isPublic && ownerName != null) ...[
                                                      const Text('Services Offered:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                                                      const SizedBox(height: 6),
                                                      if (activeServices.isEmpty)
                                                        const Text('No services enabled yet', style: TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic))
                                                      else
                                                        Wrap(
                                                          spacing: 6,
                                                          children: activeServices.map((service) => Chip(
                                                            label: Text(service, style: const TextStyle(fontSize: 12)),
                                                            backgroundColor: Colors.purple[100],
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
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}