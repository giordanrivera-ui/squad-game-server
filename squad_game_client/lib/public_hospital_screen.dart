import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';
import 'dart:async';
import 'ad_service.dart';

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
    AdService.loadRewardedAd();

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
        final int maxHealth = stats['maxHealth'] ?? 100;           // NEW
        final int? healingEndTime = stats['healingEndTime'] as int?;
        final bool hasBrokenBone = stats['hasBrokenBone'] == true;

        final bool isHealing = healingEndTime != null && healingEndTime > SocketService().currentServerTime;
        final int remainingSeconds = isHealing
            ? ((healingEndTime - SocketService().currentServerTime) / 1000).ceil().clamp(0, 360)
            : 0;

        final bool canStartHealing = !isHealing && health < maxHealth && balance >= 50; // UPDATED
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
                      Text('Health: $health/$maxHealth', style: const TextStyle(fontSize: 24)), // UPDATED
                      const SizedBox(height: 20),
                      Text('Balance: \$$balance', style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 40),

                      // ==================== HEALING SECTION ====================
                      if (isHealing)
                        Column(
                          children: [
                            Text(
                              'Healing in progress... $remainingSeconds seconds remaining',
                              style: const TextStyle(fontSize: 20, color: Colors.orange),
                            ),
                            const SizedBox(height: 20),

                            ValueListenableBuilder<bool>(
                              valueListenable: AdService.adReadyNotifier,
                              builder: (context, isAdReady, child) {
                                if (stats['usedAdForHealing'] == true) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.green.withOpacity(0.4)),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.check_circle, color: Colors.green, size: 22),
                                          SizedBox(width: 10),
                                          Text(
                                            '✅ Ad used — healing will finish faster!',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                if (isAdReady) {
                                  return SizedBox(
                                    width: double.infinity,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24),
                                      child: ElevatedButton(
                                        onPressed: () {
                                          AdService.showRewardedAd(
                                            context: context,
                                            onAdWatched: () {
                                              SocketService().socket?.emit('watch-ad-for-faster-healing');
                                            },
                                            onAdFailed: () {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Ad could not be shown. Please try again.')),
                                              );
                                            },
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.purple,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                        ),
                                        child: const Text(
                                          '🎬 Watch Ad to Heal in 3 Minutes',
                                          style: TextStyle(fontSize: 18),
                                        ),
                                      ),
                                    ),
                                  );
                                } else {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.withOpacity(0.4)),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'Loading Ad...',
                                          style: TextStyle(fontSize: 18, color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),

                            const SizedBox(height: 12),
                            const Text('You are healing...', style: TextStyle(color: Colors.grey)),
                          ],
                        )
                      else if (canStartHealing)
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: ElevatedButton(
                              onPressed: () => SocketService().startHealing(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                              ),
                              child: const Text(
                                '🏥 HEAL NOW (6 minutes) 🏥',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        )
                      else if (health >= maxHealth) // UPDATED
                        const Text(
                          'You are already at full health!',
                          style: TextStyle(color: Colors.green, fontSize: 18),
                        )
                      else if (balance < healCost)
                        const Text(
                          'Not enough money!',
                          style: TextStyle(color: Colors.red, fontSize: 18),
                        ),

                      const SizedBox(height: 30),

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