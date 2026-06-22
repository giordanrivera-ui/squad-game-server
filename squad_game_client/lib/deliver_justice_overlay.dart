import 'package:flutter/material.dart';
import 'dart:math';

class DeliverJusticeOverlay extends StatefulWidget {
  final bool isWinner;
  final int qualityScore;
  final String opponentName;
  final VoidCallback onDismiss;

  const DeliverJusticeOverlay({
    super.key,
    required this.isWinner,
    required this.qualityScore,
    required this.opponentName,
    required this.onDismiss,
  });

  @override
  State<DeliverJusticeOverlay> createState() => _DeliverJusticeOverlayState();
}

class _DeliverJusticeOverlayState extends State<DeliverJusticeOverlay>
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

    for (int i = 0; i < 40; i++) {
      _particles.add(Particle());
    }

    Future.delayed(const Duration(milliseconds: 1800), () {
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
    final bool won = widget.isWinner;

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
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: won ? const Color(0xFF1B3A2F) : const Color(0xFF3D2A1F),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: won ? Colors.greenAccent : Colors.orangeAccent,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (won ? Colors.greenAccent : Colors.orangeAccent)
                              .withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          won ? Icons.emoji_events_rounded : Icons.gavel_rounded,
                          size: 80,
                          color: won ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          won ? 'JUSTICE SERVED!' : 'JUSTICE FAILED',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: won ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          won
                              ? 'You successfully delivered justice on ${widget.opponentName}!'
                              : '${widget.opponentName} got away from you.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Your Justice Score: ${widget.qualityScore}',
                          style: const TextStyle(fontSize: 16, color: Colors.white54),
                        ),
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
                          child: Icon(
                            won ? Icons.stars_rounded : Icons.local_fire_department,
                            color: won ? Colors.greenAccent : Colors.orangeAccent,
                            size: 16,
                          ),
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