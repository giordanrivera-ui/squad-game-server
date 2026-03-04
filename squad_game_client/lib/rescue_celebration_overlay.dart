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

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();

    // Create flying particles
    for (int i = 0; i < 40; i++) {
      _particles.add(Particle());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dark overlay
          Container(color: Colors.black.withOpacity(0.75)),

          // Main celebration
          Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.amber, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.6),
                        blurRadius: 40,
                        spreadRadius: 15,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_emotions,
                        size: 90,
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'YOU HAVE BEEN RESCUED!',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'by ${widget.rescuer}',
                        style: const TextStyle(
                          fontSize: 22,
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Welcome back to the streets!',
                        style: TextStyle(fontSize: 18, color: Colors.white70),
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
                    top: p.y - (_controller.value * 300),
                    child: Opacity(
                      opacity: 1 - _controller.value,
                      child: Transform.rotate(
                        angle: _controller.value * p.rotationSpeed,
                        child: const Icon(Icons.star, color: Colors.amber, size: 18),
                      ),
                    ),
                  );
                },
              )),
        ],
      ),
    );
  }
}

// Simple particle class
class Particle {
  final double x = Random().nextDouble() * 400 - 100;
  final double y = Random().nextDouble() * 600 + 100;
  final double rotationSpeed = Random().nextDouble() * 12 - 6;
}