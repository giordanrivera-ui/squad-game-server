import 'package:flutter/material.dart';
import 'dart:math';

class RankUpCelebrationOverlay extends StatefulWidget {
  final String oldRank;
  final String newRank;
  final VoidCallback onDismiss;

  const RankUpCelebrationOverlay({
    super.key,
    required this.oldRank,
    required this.newRank,
    required this.onDismiss,
  });

  @override
  State<RankUpCelebrationOverlay> createState() => _RankUpCelebrationOverlayState();
}

class _RankUpCelebrationOverlayState extends State<RankUpCelebrationOverlay>
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
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();

    // Create militaristic particles (chevrons + stars)
    for (int i = 0; i < 50; i++) {
      _particles.add(Particle());
    }

    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _showTapHint = true);
    });

    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Dark military backdrop
            Container(color: Colors.black.withOpacity(0.88)),

            Center(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2A22), // Dark olive green
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF8B9E6E), width: 5), // Olive accent
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B9E6E).withOpacity(0.6),
                          blurRadius: 50,
                          spreadRadius: 15,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.military_tech, size: 100, color: Color(0xFFD4AF37)), // Gold chevron icon
                        const SizedBox(height: 20),
                        const Text(
                          'RANK UP!',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD4AF37),
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${widget.oldRank} → ${widget.newRank}',
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 30),
                        const Text(
                          'Well done, soldier.',
                          style: TextStyle(fontSize: 18, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Flying military particles
            ..._particles.map((p) => AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Positioned(
                      left: p.x,
                      top: p.y - (_controller.value * 420),
                      child: Opacity(
                        opacity: (1 - _controller.value * 1.1).clamp(0.0, 1.0),
                        child: Transform.rotate(
                          angle: _controller.value * p.rotation,
                          child: const Icon(Icons.star_rounded, color: Color(0xFFD4AF37), size: 20),
                        ),
                      ),
                    );
                  },
                )),

            // Tap hint
            if (_showTapHint)
              Positioned(
                bottom: 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Tap anywhere to continue',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.75),
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
  final double x = Random().nextDouble() * 500 - 100;
  final double y = Random().nextDouble() * 700 + 100;
  final double rotation = Random().nextDouble() * 25 - 12;
}