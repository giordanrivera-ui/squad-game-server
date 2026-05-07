import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';
import 'dart:async';

class PublicHospitalScreen extends StatefulWidget {
  const PublicHospitalScreen({super.key});

  @override
  State<PublicHospitalScreen> createState() => _PublicHospitalScreenState();
}

class _PublicHospitalScreenState extends State<PublicHospitalScreen> {
  Timer? _countdownTimer;
  static const int healCost = 50;
  static const int boneHealCost = 110;

  @override
  void initState() {
    super.initState();
    // Refresh UI every second while healing is active
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        final String location = stats['location'] ?? 'Unknown';
        final int balance = (stats['balance'] ?? 0).toInt();
        final int health = stats['health'] ?? 100;
        final int? healingEndTime = stats['healingEndTime'] as int?;
        final bool hasBrokenBone = stats['hasBrokenBone'] == true;

        final bool isHealing = healingEndTime != null && healingEndTime > SocketService().currentServerTime;
        final int remainingSeconds = isHealing 
            ? ((healingEndTime! - SocketService().currentServerTime) / 1000).ceil().clamp(0, 120)
            : 0;

        final bool canStartHealing = !isHealing && health < 100 && balance >= 50;
        final bool canHealBone = hasBrokenBone && balance >= boneHealCost && location == "Lónghǎi";

        return Scaffold(
          appBar: StatusAppBar(
            title: 'Public Hospital',
            statsNotifier: SocketService().statsNotifier,
            time: 'Live',
            onMenuPressed: () => Navigator.pop(context),
          ),
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

                      // Heal Button (now properly reacts to healing state)
                      SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: ElevatedButton(
                            onPressed: canStartHealing
                                ? () => SocketService().startHealing()
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canStartHealing ? Colors.green : Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: Text(
                              isHealing
                                  ? 'HEALING... ${remainingSeconds ~/ 60}:${(remainingSeconds % 60).toString().padLeft(2, '0')}'
                                  : '🏥 HEAL NOW (2 minutes) 🏥',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

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

                      if (isHealing)
                        const Text('Healing in progress...', style: TextStyle(color: Colors.orange, fontSize: 16))
                      else if (health == 100)
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