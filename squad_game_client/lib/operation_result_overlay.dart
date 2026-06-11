import 'package:flutter/material.dart';
import 'dart:math';

class OperationResultOverlay extends StatefulWidget {
  final String operation;
  final int money;
  final String message;
  final int actualDamage;
  final int totalDefense;
  final Map<String, dynamic>? stolenWeapon; // NEW
  final VoidCallback onDismiss;

  const OperationResultOverlay({
    super.key,
    required this.operation,
    required this.money,
    required this.message,
    required this.actualDamage,
    required this.totalDefense,
    this.stolenWeapon, // NEW
    required this.onDismiss,
  });

  @override
  State<OperationResultOverlay> createState() => _OperationResultOverlayState();
}

class _OperationResultOverlayState extends State<OperationResultOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  final List<Particle> _particles = [];
  bool _showTapHint = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 850),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();

    for (int i = 0; i < 40; i++) {
      _particles.add(Particle());
    }

    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showTapHint = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool tookDamage = widget.actualDamage > 0;
    final bool hasStolenWeapon = widget.stolenWeapon != null;

    return GestureDetector(
      onTap: widget.onDismiss,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Container(color: Colors.black.withOpacity(0.88)),

            Center(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2E1F),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF4CAF50), width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4CAF50).withOpacity(0.5),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 90, color: Color(0xFF4CAF50)),
                        const SizedBox(height: 16),
                        Text(
                          widget.operation,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '+ \$${widget.money}',
                          style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                        ),
                        const SizedBox(height: 20),

                        // Main message
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.message,
                            style: const TextStyle(fontSize: 17, color: Colors.white70, height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        if (widget.totalDefense > 0) ...[
                          const SizedBox(height: 16),
                          Text(
                            tookDamage
                                ? 'Your armor absorbed ${widget.totalDefense} damage!\nYou lost ${widget.actualDamage} health.'
                                : 'Your armor absorbed all damage!',
                            style: TextStyle(
                              fontSize: 15,
                              color: tookDamage ? Colors.orangeAccent : Colors.greenAccent,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        // ==================== NEW: STOLEN WEAPON SECTION ====================
                        if (hasStolenWeapon) ...[
                          const SizedBox(height: 24),
                          const Divider(color: Colors.white24, thickness: 1),
                          const SizedBox(height: 12),
                          const Text(
                            'Weapon Acquired',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/${widget.stolenWeapon!['name']}.jpg',
                              width: 120,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 120,
                                height: 80,
                                color: Colors.grey[800],
                                child: const Icon(Icons.image_not_supported, color: Colors.white54),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.stolenWeapon!['name'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Particles
            ..._particles.map((p) => AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Positioned(
                      left: p.x,
                      top: p.y - (_controller.value * 380),
                      child: Opacity(
                        opacity: (1 - _controller.value * 1.1).clamp(0.0, 1.0),
                        child: Transform.rotate(
                          angle: _controller.value * p.rotation,
                          child: const Icon(Icons.stars_rounded, color: Color(0xFF4CAF50), size: 18),
                        ),
                      ),
                    );
                  },
                )),

            if (_showTapHint)
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Tap anywhere to continue',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class Particle {
  final double x = Random().nextDouble() * 500 - 80;
  final double y = Random().nextDouble() * 650 + 120;
  final double rotation = Random().nextDouble() * 18 - 9;
}