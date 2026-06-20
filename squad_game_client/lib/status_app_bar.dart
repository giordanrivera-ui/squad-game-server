import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:intl/intl.dart';

class StatusAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final ValueNotifier<Map<String, dynamic>> statsNotifier;
  final String time;
  final VoidCallback onMenuPressed;

  const StatusAppBar({
    super.key,
    required this.title,
    required this.statsNotifier,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: statsNotifier,
      builder: (context, currentStats, child) {
        final balance = currentStats['balance'] ?? 0;
        final health = currentStats['health'] ?? 100;
        final int currentHealth = currentStats['health'] ?? 100;
        final int maxHealth = currentStats['maxHealth'] ?? 100;

        return AppBar(
          leading: Builder(
            builder: (context) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: onMenuPressed,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: SocketService().hasUnreadMessages,
                  builder: (context, hasUnread, child) {
                    if (!hasUnread) return const SizedBox.shrink();
                    return Positioned(
                      right: 11,
                      top: 11,
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
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, size: 20, color: Colors.green),
                  const SizedBox(width: 4),
                  Text('\$${NumberFormat('#,###').format(balance)}', style: const TextStyle(fontSize: 15)),

                  const SizedBox(width: 16),

                  // ==================== PULSING HEART ====================
                  _HealthIcon(health: health, maxHealth: currentStats['maxHealth'] ?? 100,),
                  const SizedBox(width: 4),
                  Text('$currentHealth / $maxHealth', style: const TextStyle(fontSize: 15)),

                  const SizedBox(width: 16),

                  const Icon(Icons.adjust, size: 20, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text('${currentStats['bullets'] ?? 0}', style: const TextStyle(fontSize: 15)),

                  const SizedBox(width: 16),
                  Text(time, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ==================== PULSING HEART WIDGET ====================
class _HealthIcon extends StatefulWidget {
  final int health;
  final int maxHealth;

  const _HealthIcon({required this.health, this.maxHealth = 100,});

  @override
  State<_HealthIcon> createState() => _HealthIconState();
}

class _HealthIconState extends State<_HealthIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  bool get _isLowHealth {
    final max = widget.maxHealth > 0 ? widget.maxHealth : 100;
    return widget.health < (max * 0.3);   // Pulse when below 30%
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _HealthIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart or stop animation when health crosses the threshold
    if (_isLowHealth && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!_isLowHealth && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLowHealth) {
      return const Icon(Icons.favorite, size: 20, color: Colors.red);
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.6),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.favorite,
          size: 20,
          color: Colors.red,
        ),
      ),
    );
  }
}