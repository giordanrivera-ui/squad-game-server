import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';   // ← ADD THIS IMPORT

class PublicHospitalScreen extends StatefulWidget {
  const PublicHospitalScreen({super.key});

  @override
  State<PublicHospitalScreen> createState() => _PublicHospitalScreenState();
}

class _PublicHospitalScreenState extends State<PublicHospitalScreen> {
  static const int healCost = 50;
  static const int boneHealCost = 110;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        final String location = stats['location'] ?? 'Unknown';
        final int balance = (stats['balance'] ?? 0).toInt();
        final int health = stats['health'] ?? 100;
        final bool hasBrokenBone = stats['hasBrokenBone'] == true;

        final bool canHeal = health < 100 && balance >= healCost;
        final bool canHealBone = hasBrokenBone && balance >= boneHealCost && location == "Lónghǎi";

        return Scaffold(
          // ==================== STATUS APP BAR (now added) ====================
          appBar: StatusAppBar(
            title: 'Public Hospital',
            statsNotifier: SocketService().statsNotifier,
            time: 'Live',                    // You can change this to real time if you want
            onMenuPressed: () => Navigator.pop(context),
          ),
          // ==================================================================

          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                color: Colors.green[50],
                child: Column(
                  children: [
                    const Text('You are at the Public Hospital in', style: TextStyle(fontSize: 18)),
                    Text(location, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Health: $health/100', style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 20),
                      Text('Balance: \$$balance', style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 40),

                      // Normal heal button
                      SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: ElevatedButton(
                            onPressed: canHeal
                                ? () => SocketService().heal()
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canHeal ? Colors.green : Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: const Text(
                              '🏥 HEAL NOW (2 minutes) 🏥',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Orthopedic Surgeon (only in Lónghǎi)
                      if (location == "Lónghǎi")
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: ElevatedButton(
                              onPressed: canHealBone
                                  ? () => SocketService().healBrokenBone()
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canHealBone ? Colors.blueGrey[700] : Colors.grey,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                              ),
                              child: Text(
                                hasBrokenBone
                                    ? '🦴 See Orthopedic Surgeon (\$$boneHealCost)'
                                    : '🦴 See Orthopedic Surgeon',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 30),

                      if (health == 100)
                        const Text('You are already at full health!', style: TextStyle(color: Colors.green, fontSize: 16))
                      else if (balance < healCost)
                        const Text('Not enough money!', style: TextStyle(color: Colors.red, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}