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
  static const int healCost = 50;

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
    final hospital = widget.hospital;
    final ownerName = hospital['ownerDisplayName'] ?? 'Unknown Owner';
    final location = hospital['location'] ?? 'Unknown';

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().statsNotifier,
      builder: (context, stats, child) {
        final int balance = (stats['balance'] ?? 0).toInt();
        final int health = stats['health'] ?? 100;
        final int? healingEndTime = stats['healingEndTime'] as int?;
        final bool isHealing = healingEndTime != null && healingEndTime > SocketService().currentServerTime;
        final int remaining = isHealing ? ((healingEndTime! - SocketService().currentServerTime) / 1000).ceil().clamp(0, 120) : 0;

        final bool canHeal = !isHealing && health < 100 && balance >= healCost;

        return Scaffold(
          appBar: StatusAppBar(
            title: 'Private Hospital • $location',
            statsNotifier: SocketService().statsNotifier,
            time: 'Live',
            onMenuPressed: () => Navigator.pop(context),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("🏥 $ownerName's Private Hospital", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                Text("Healing Cost: \$$healCost → Paid to owner", style: const TextStyle(fontSize: 18, color: Colors.green)),
                const SizedBox(height: 40),

                SizedBox(
                  width: 300,
                  child: ElevatedButton(
                    onPressed: canHeal ? () {
                      SocketService().socket?.emit('start-private-healing', {
                        'hospitalDocId': hospital['docId'],
                        'ownerEmail': hospital['ownerEmail'],
                      });
                    } : null,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                    child: Text(
                      isHealing ? 'HEALING... $remaining seconds' : 'Heal for $healCost (2 minutes)',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                if (isHealing)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Text("You are healing... $remaining seconds left", style: const TextStyle(color: Colors.orange, fontSize: 18)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}