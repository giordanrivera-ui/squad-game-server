import 'package:flutter/material.dart';
import 'dart:math';

class RescueCelebrationOverlay extends StatefulWidget {
  final String rescuer;
  final VoidCallback onDismiss;

  const RescueCelebrationOverlay({
    super.key,
    required this.rescuer,
    required this.onDismiss,
  });

  @override
  State<RescueCelebrationOverlay> createState() => _RescueCelebrationOverlayState();
}

class _RescueCelebrationOverlayState extends State<RescueCelebrationOverlay>
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
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();

    // Create golden particles
    for (int i = 0; i < 45; i++) {
      _particles.add(Particle());
    }

    // Show "Tap anywhere" hint after 1.2 seconds
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showTapHint = true);
    });

    // Auto dismiss after 4.8 seconds as fallback
    Future.delayed(const Duration(milliseconds: 4800), () {
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
      onTap: widget.onDismiss,   // ← Tap anywhere to dismiss
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Dark backdrop
            Container(color: Colors.black.withOpacity(0.85)),

            // Main celebration card
            Center(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.amber.shade400, width: 5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.7),
                          blurRadius: 60,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_emotions_rounded, size: 100, color: Colors.amber),
                        const SizedBox(height: 20),
                        const Text(
                          'YOU HAVE BEEN RESCUED!',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'by ${widget.rescuer}',
                          style: TextStyle(
                            fontSize: 24,
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 30),
                        const Text(
                          'Welcome back to the streets, soldier!',
                          style: TextStyle(fontSize: 18, color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Flying golden particles
            ..._particles.map((p) => AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Positioned(
                      left: p.x,
                      top: p.y - (_controller.value * 400),
                      child: Opacity(
                        opacity: (1 - _controller.value * 1.2).clamp(0.0, 1.0),
                        child: Transform.rotate(
                          angle: _controller.value * p.rotation,
                          child: const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                        ),
                      ),
                    );
                  },
                )),

            // Tap to dismiss hint
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
  final double x = Random().nextDouble() * 500 - 100;
  final double y = Random().nextDouble() * 700 + 100;
  final double rotation = Random().nextDouble() * 20 - 10;
}