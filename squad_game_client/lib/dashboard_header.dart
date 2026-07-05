import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'inventory_page.dart';

class DashboardHeader extends StatelessWidget {
  final String time;
  final Map<String, dynamic> stats;
  final bool hasEnhancedStamina;
  final String? staminaRemainingText;
  final bool hasHealing;                    // NEW
  final String? healingRemainingText;       // NEW
  final VoidCallback onMenuPressed;
  final VoidCallback? onDeveloperOptionsPressed;

  const DashboardHeader({
    super.key,
    required this.time,
    required this.stats,
    required this.hasEnhancedStamina,
    this.staminaRemainingText,
    required this.hasHealing,
    this.healingRemainingText,
    required this.onMenuPressed,
    this.onDeveloperOptionsPressed,
  });

  @override
  Widget build(BuildContext context) {
    final int currentHealth = stats['health'] ?? 100;
    final int maxHealth = stats['maxHealth'] ?? 100;
    final double healthPercent = (currentHealth / maxHealth).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('assets/top-section-bg.jpg'),
          fit: BoxFit.cover,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.68),
            blurRadius: 14,
            offset: const Offset(0, 12),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row
              Row(
                children: [
                  Builder(
                    builder: (context) => Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.menu, color: Colors.white),
                          onPressed: onMenuPressed,
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: SocketService().hasUnreadMessages,
                          builder: (context, hasUnread, child) {
                            if (!hasUnread) return const SizedBox.shrink();
                            return Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      time,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // Inventory
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () {
                        final currentStats = SocketService().statsNotifier.value;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InventoryPage(
                              initialInventory: currentStats['inventory'] ?? [],
                              initialStats: currentStats,
                              initialTime: time,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Image.asset('assets/inventory.png', width: 42, height: 42),
                      ),
                    ),
                  ),

                  if (onDeveloperOptionsPressed != null)
                    IconButton(
                      icon: const Icon(Icons.bug_report, color: Colors.amber, size: 28),
                      tooltip: 'Developer Options',
                      onPressed: onDeveloperOptionsPressed,
                    ),
                ],
              ),

              const SizedBox(height: 2),

              // Location
              Text(
                'Location: ${stats['location'] ?? "Unknown"}',
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),

              const SizedBox(height: 8),

              LinearProgressIndicator(
                value: healthPercent,
                color: Colors.green,
                backgroundColor: Colors.grey[700],
              ),

              const SizedBox(height: 6),

              // Health + Status Indicators (Stamina + Healing)
              Row(
                children: [
                  Text(
                    'Health: $currentHealth/$maxHealth',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),

                  // Status indicators (Stamina + Healing)
                  if (stats['hasBrokenBone'] == true || hasEnhancedStamina || hasHealing)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (stats['hasBrokenBone'] == true)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Tooltip(
                                message: "You have a broken bone. All level operations will have a longer cooldown.",
                                waitDuration: Duration(milliseconds: 400),
                                child: Text('🦴', style: TextStyle(fontSize: 16)),
                              ),
                            ),

                          // Enhanced Stamina
                          if (hasEnhancedStamina)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: 'Enhanced Stamina active\nOperation cooldowns reduced by 3 seconds',
                                    waitDuration: const Duration(milliseconds: 400),
                                    child: const Icon(Icons.bolt, color: Colors.amber, size: 22),
                                  ),
                                  if (staminaRemainingText != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Text(
                                        staminaRemainingText!,
                                        style: const TextStyle(
                                          color: Colors.amber,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                          // Healing Timer (NEW)
                          if (hasHealing)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.local_hospital, color: Colors.green, size: 20),
                                  if (healingRemainingText != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Text(
                                        healingRemainingText!,
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Bullets + Kills
              Row(
                children: [
                  const Icon(Icons.adjust, size: 20, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text('${stats['bullets'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  const SizedBox(width: 6),
                  const Icon(Icons.whatshot, size: 20, color: Colors.red),
                  const SizedBox(width: 4),
                  Text('${stats['kills'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}