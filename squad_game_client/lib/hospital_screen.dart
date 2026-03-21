import 'package:flutter/material.dart';
import 'socket_service.dart';

class HospitalScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;
  final int currentHealth;
  final String currentTime;

  const HospitalScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
  });

  @override
  State<HospitalScreen> createState() => _HospitalScreenState();
}

class _HospitalScreenState extends State<HospitalScreen> {
  static const int healCost = 50;
  static const int boneHealCost = 110;

  bool get canHeal => widget.currentHealth < 100 && widget.currentBalance >= healCost;

  void _heal() {
    if (!canHeal) return;
    SocketService().heal();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Healing... You feel better!')),
    );
  }

  // NEW: Orthopedic Surgeon logic
  void _seeOrthopedicSurgeon() {
    final stats = SocketService().statsNotifier.value;
    final hasBrokenBone = stats['hasBrokenBone'] == true;
    final balance = stats['balance'] ?? 0;

    if (!hasBrokenBone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have a broken bone.')),
      );
      return;
    }
    if (balance < boneHealCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not enough money (\$$boneHealCost required).')),
      );
      return;
    }

    SocketService().healBrokenBone();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: Colors.green[50],
          child: Column(
            children: [
              const Text('You are at the Hospital in', style: TextStyle(fontSize: 18)),
              Text(widget.currentLocation, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Health: ${widget.currentHealth}/100', style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 20),
                Text('Balance: \$${widget.currentBalance}', style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 30),
                Text('Heal to full health for $healCost?', style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 20),

                // Normal heal button
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton(
                      onPressed: canHeal ? _heal : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canHeal ? Colors.green : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      child: const Text(
                        '🏥 HEAL NOW 🏥',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Orthopedic Surgeon button - ONLY in Lónghǎi (already filtered by widget)
                if (widget.currentLocation == "Lónghǎi")
                  ValueListenableBuilder<Map<String, dynamic>>(
                    valueListenable: SocketService().statsNotifier,
                    builder: (context, stats, child) {
                      final hasBrokenBone = stats['hasBrokenBone'] == true;
                      final balance = stats['balance'] ?? 0;
                      final canHealBone = hasBrokenBone && balance >= boneHealCost;

                      return SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ElevatedButton(
                            onPressed: canHealBone ? _seeOrthopedicSurgeon : null,
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
                      );
                    },
                  ),

                const SizedBox(height: 12),

                if (widget.currentHealth == 100)
                  const Text('You are already at full health!', style: TextStyle(color: Colors.green, fontSize: 16))
                else if (widget.currentBalance < healCost)
                  const Text('Not enough money!', style: TextStyle(color: Colors.red, fontSize: 16))
                else
                  const Text('Ready to heal!', style: TextStyle(color: Colors.green, fontSize: 16)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}