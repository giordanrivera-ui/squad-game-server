// private_hospital_heal_screen.dart
import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';
import 'dart:async';

class PrivateHospitalHealScreen extends StatefulWidget {
  final Map<String, dynamic> hospital;

  const PrivateHospitalHealScreen({super.key, required this.hospital});

  @override
  State<PrivateHospitalHealScreen> createState() => _PrivateHospitalHealScreenState();
}

class _PrivateHospitalHealScreenState extends State<PrivateHospitalHealScreen> {
  Timer? _countdownTimer;
  bool _isHealingRequested = false;

  @override
  void initState() {
    super.initState();
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
    final String docId = widget.hospital['docId'] ?? '';

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().hospitalOwnershipNotifier,
      builder: (context, ownership, _) {
        // === LIVE hospital data lookup (fixes stale object issue) ===
        final freshHospital = (ownership[docId] as Map<String, dynamic>?) ?? widget.hospital;

        final ownerName = freshHospital['ownerDisplayName'] ?? 'Unknown Owner';
        final location = freshHospital['location'] ?? 'Unknown';
        final bool isOfferingHealing = freshHospital['offerInjuryHealing'] == true;

        // Use fresh customHealCost (or fallback to 50)
        final int healCost = (freshHospital['customHealCost'] as num?)?.toInt() ?? 50;

        return ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: SocketService().statsNotifier,
          builder: (context, stats, child) {
            final int balance = (stats['balance'] ?? 0).toInt();
            final int health = stats['health'] ?? 100;
            final int? healingEndTime = stats['healingEndTime'] as int?;
            final bool isDead = stats['dead'] ?? false;

            final bool isHealing = healingEndTime != null &&
                healingEndTime > SocketService().currentServerTime;

            final int remaining = isHealing
                ? ((healingEndTime - SocketService().currentServerTime) / 1000)
                    .ceil()
                    .clamp(0, 120)
                : 0;

            // === UPDATED canHeal logic with fresh service check ===
            final bool canHeal = !isHealing &&
                !isDead &&
                health < 100 &&
                balance >= healCost &&
                isOfferingHealing; // ← Important: service must still be active

            return Scaffold(
              appBar: StatusAppBar(
                title: 'Private Hospital • $location',
                statsNotifier: SocketService().statsNotifier,
                time: 'Live',
                onMenuPressed: () => Navigator.pop(context),
              ),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "🏥 $ownerName's Private Hospital",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      // === LIVE price display ===
                      Text(
                        "Healing Cost: \$$healCost → Paid to owner",
                        style: const TextStyle(fontSize: 18, color: Colors.green),
                      ),
                      const SizedBox(height: 12),

                      // Show warning if owner turned off the service
                      if (!isOfferingHealing)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Text(
                            "This hospital is no longer offering injury healing.",
                            style: TextStyle(color: Colors.red, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: 300,
                        child: ElevatedButton(
                          onPressed: (canHeal && !_isHealingRequested)
                              ? () {
                                  setState(() => _isHealingRequested = true);

                                  SocketService().socket?.emit('start-private-healing', {
                                    'hospitalDocId': docId,
                                    'ownerEmail': freshHospital['ownerEmail'],
                                  });

                                  // Safety net: re-enable button after 3 seconds
                                  Future.delayed(const Duration(seconds: 3), () {
                                    if (mounted) setState(() => _isHealingRequested = false);
                                  });
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            backgroundColor: canHeal ? Colors.green : Colors.grey,
                          ),
                          child: Text(
                            _isHealingRequested
                                ? 'Requesting healing...'
                                : isHealing
                                    ? 'HEALING... $remaining seconds'
                                    : 'Heal for \$$healCost (2 minutes)',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                      if (isHealing)
                        Padding(
                          padding: const EdgeInsets.only(top: 30),
                          child: Text(
                            "You are healing... $remaining seconds left",
                            style: const TextStyle(color: Colors.orange, fontSize: 18),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}