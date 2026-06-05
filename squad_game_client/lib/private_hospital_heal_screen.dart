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
    SocketService().socket?.on('enhanced-stamina-purchased', (data) {
      if (data is Map && mounted) {
        final success = data['success'] ?? false;
        final message = data['message'] ?? '';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    SocketService().socket?.off('enhanced-stamina-purchased');
    super.dispose();
  }

  String _formatDuration(int durationMs) {
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (seconds == 0) {
      return '$minutes minutes';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // Helper to show "Coming Soon" message
  void _showComingSoon(String serviceName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$serviceName is coming soon!'),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String docId = widget.hospital['docId'] ?? '';

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().hospitalOwnershipNotifier,
      builder: (context, ownership, _) {
        final freshHospital = (ownership[docId] as Map<String, dynamic>?) ?? widget.hospital;

        final ownerName = freshHospital['ownerDisplayName'] ?? 'Unknown Owner';
        final location = freshHospital['location'] ?? 'Unknown';
        final bool isOfferingHealing = freshHospital['offerInjuryHealing'] == true;

        final int healCost = (freshHospital['customHealCost'] as num?)?.toInt() ?? 50;
        final int healingDurationMs = (freshHospital['customHealingDuration'] as num?)?.toInt() ?? 240000;
        final String formattedDuration = _formatDuration(healingDurationMs);

        // ==================== NEW: Dynamic costs for performance services ====================
        final bool offersEnhancedStamina = freshHospital['offerEnhancedStamina'] == true;
        final bool offersEnhancedConstitution = freshHospital['offerEnhancedConstitution'] == true;

        final int staminaCost = (freshHospital['customStaminaCost'] as num?)?.toInt() ?? 150;
        final int constitutionCost = (freshHospital['customConstitutionCost'] as num?)?.toInt() ?? 150;

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
                    .clamp(0, 750)
                : 0;

            final bool canHeal = !isHealing &&
                !isDead &&
                health < 100 &&
                balance >= healCost &&
                isOfferingHealing;

            return Scaffold(
              appBar: StatusAppBar(
                title: 'Private Hospital • $location',
                statsNotifier: SocketService().statsNotifier,
                time: 'Live',
                onMenuPressed: () => Navigator.pop(context),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Hospital Header
                    Text(
                      "🏥 $ownerName's Private Hospital",
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),

                    // ==================== INJURY HEALING CARD ====================
                    if (!isHealing) ...[
                      if (!isOfferingHealing)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Text(
                            "This hospital is no longer offering injury healing.",
                            style: TextStyle(color: Colors.red, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      _buildServiceCard(
                        icon: Icons.healing,
                        iconColor: Colors.green,
                        title: 'Injury Healing',
                        subtitle: 'Fully restore your health',
                        costText: '\$$healCost  •  Paid to owner',
                        durationText: 'Healing Time: $formattedDuration',
                        buttonText: _isHealingRequested ? 'Requesting...' : 'Start Healing for \$$healCost',
                        buttonColor: canHeal ? Colors.green : Colors.grey,
                        onTap: (canHeal && !_isHealingRequested)
                            ? () {
                                setState(() => _isHealingRequested = true);

                                SocketService().socket?.emit('start-private-healing', {
                                  'hospitalDocId': docId,
                                  'ownerEmail': freshHospital['ownerEmail'],
                                });

                                Future.delayed(const Duration(seconds: 3), () {
                                  if (mounted) setState(() => _isHealingRequested = false);
                                });
                              }
                            : null,
                      ),
                    ],

                    // ==================== ENHANCED STAMINA CARD ====================
                    if (offersEnhancedStamina)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _buildServiceCard(
                          icon: Icons.bolt,
                          iconColor: Colors.amber,
                          title: 'Enhanced Stamina',
                          subtitle: 'Reduces all operation cooldowns by 3 seconds',
                          costText: '\$$staminaCost  •  Paid to owner',
                          durationText: 'Duration: 5 minutes',
                          buttonText: 'Purchase Enhanced Stamina',
                          buttonColor: Colors.amber,
                          onTap: () {
                            SocketService().socket?.emit('purchase-enhanced-stamina', {
                              'hospitalDocId': docId,
                              'ownerEmail': freshHospital['ownerEmail'],
                            });
                          },
                        ),
                      ),

                    // ==================== ENHANCED CONSTITUTION CARD ====================
                    if (offersEnhancedConstitution)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _buildServiceCard(
                          icon: Icons.shield,
                          iconColor: Colors.blue,
                          title: 'Enhanced Constitution',
                          subtitle: 'Improved health & resilience',
                          costText: '\$$constitutionCost  •  Paid to owner',
                          durationText: null,
                          buttonText: 'Purchase (Coming Soon)',
                          buttonColor: Colors.blue,
                          onTap: () => _showComingSoon('Enhanced Constitution'),
                        ),
                      ),

                    // ==================== ALREADY HEALING STATE ====================
                    if (isHealing)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Column(
                          children: [
                            const Icon(Icons.healing, color: Colors.orange, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              "You are currently healing...",
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "$remaining seconds remaining",
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==================== Reusable Service Card Widget ====================
  Widget _buildServiceCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String costText,
    String? durationText,
    required String buttonText,
    required Color buttonColor,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              ),
              const SizedBox(height: 20),

              if (costText.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.attach_money, color: Colors.green, size: 20),
                    const SizedBox(width: 6),
                    Text(costText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),

              if (durationText != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.blue, size: 20),
                    const SizedBox(width: 6),
                    Text(durationText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: buttonColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}