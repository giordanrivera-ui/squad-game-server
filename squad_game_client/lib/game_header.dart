import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:intl/intl.dart';

class GameHeader extends StatelessWidget {
  final String? title;
  final ValueNotifier<Map<String, dynamic>> statsNotifier;
  final String time;
  final VoidCallback onMenuPressed;

  const GameHeader({
    super.key,
    this.title,
    required this.statsNotifier,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: statsNotifier,
      builder: (context, stats, child) {
        final balance = stats['balance'] ?? 0;
        final health = stats['health'] ?? 100;
        final maxHealth = stats['maxHealth'] ?? 100;
        final bullets = stats['bullets'] ?? 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 25, 10, 8),
          decoration: BoxDecoration(
            image: const DecorationImage(
              image: AssetImage('assets/top-section-bg.jpg'),
              fit: BoxFit.cover,
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(25),
              bottomRight: Radius.circular(25),
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
                    bottomLeft: Radius.circular(25),
                    bottomRight: Radius.circular(25),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildMenuButton(),
                      const Spacer(),
                      // Balance
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet, size: 18, color: Colors.green),
                          const SizedBox(width: 4),
                          Text('\$${NumberFormat('#,###').format(balance)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 14,fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // ==================== HEALTH (with pulsing animation) ====================
                      _HealthIcon(
                        health: health,
                        maxHealth: maxHealth,
                      ),
                      const SizedBox(width: 4),
                      Text('$health', style: const TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 0.5, fontWeight: FontWeight.w700)),
                      Text('/$maxHealth', style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 0.5)),
                      const SizedBox(width: 16),
                      // Bullets
                      Row(
                        children: [
                          const Icon(Icons.adjust, size: 18, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text('$bullets', style: const TextStyle(color: Colors.white70, fontSize: 14,fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Text(time, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                  if (title != null && title!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(title!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuButton() {
    return Builder(
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
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                  constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
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