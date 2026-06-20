import 'package:flutter/material.dart';
import 'dart:math';

class OperationResultOverlay extends StatefulWidget {
  final String operation;
  final int money;
  final String message;
  final int actualDamage;
  final int totalDefense;
  final Map<String, dynamic>? stolenWeapon;
  final Map<String, dynamic>? epinephrine;   // NEW
  final int bulletsStolen;                   // NEW
  final VoidCallback onDismiss;

  const OperationResultOverlay({
    super.key,
    required this.operation,
    required this.money,
    required this.message,
    required this.actualDamage,
    required this.totalDefense,
    this.stolenWeapon,
    this.epinephrine,      // NEW
    this.bulletsStolen = 0, // NEW
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
    final bool hasStolenWeapon = widget.stolenWeapon != null;
    final bool hasEpinephrine = widget.epinephrine != null;
    final bool hasBullets = widget.bulletsStolen > 0;

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

                        if (widget.actualDamage > 0) ...[
  const SizedBox(height: 16),
  Text(
    widget.totalDefense > 0
        ? 'Your armor absorbed ${widget.totalDefense} damage!\nYou lost ${widget.actualDamage} health.'
        : 'You lost ${widget.actualDamage} health.',
    style: const TextStyle(
      fontSize: 15,
      color: Colors.orangeAccent,
      height: 1.3,
    ),
    textAlign: TextAlign.center,
  ),
] else if (widget.totalDefense > 0) ...[
  const SizedBox(height: 16),
  Text(
    'Your armor absorbed all damage!',
    style: const TextStyle(
      fontSize: 15,
      color: Colors.greenAccent,
    ),
    textAlign: TextAlign.center,
  ),
],

                        // ==================== ADAPTIVE LOOT SECTION ====================
if (hasStolenWeapon || hasEpinephrine || hasBullets) ...[
  const SizedBox(height: 24),
  const Divider(color: Colors.white24, thickness: 1),
  const SizedBox(height: 12),

  // ==================== DYNAMIC HEADER ====================
  Builder(
    builder: (context) {
      String headerText;

      if (hasStolenWeapon && hasBullets) {
        final weaponName = widget.stolenWeapon!['name'] as String;
        final bulletWord = widget.bulletsStolen > 1 ? 'Bullets' : 'Bullet';
        headerText = '$weaponName and $bulletWord Acquired';
      } 
      else if (hasEpinephrine && hasBullets) {
        final quality = widget.epinephrine!['quality'];
        final bulletWord = widget.bulletsStolen > 1 ? 'Bullets' : 'Bullet';
        headerText = 'Epinephrine (Quality $quality) and $bulletWord Acquired';
      } 
      else if (hasStolenWeapon) {
        headerText = 'Weapon Acquired';
      } 
      else if (hasEpinephrine) {
        final quality = widget.epinephrine!['quality'];
        headerText = 'Epinephrine Quality $quality Acquired';
      } 
      else {
        final bulletWord = widget.bulletsStolen > 1 ? 'Bullets' : 'Bullet';
        headerText = '$bulletWord Acquired';
      }

      return Text(
        headerText,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.amber,
        ),
        textAlign: TextAlign.center,
      );
    },
  ),

  const SizedBox(height: 16),

  // ==================== IMAGES LAYOUT ====================
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // Weapon Image
if (hasStolenWeapon) ...[
  Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/${widget.stolenWeapon!['name']}.jpg',
          width: 165,
          height: 75,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 165,
            height: 75,
            color: Colors.grey[800],
            child: const Icon(Icons.image_not_supported, color: Colors.white54),
          ),
        ),
      ),
      const SizedBox(height: 8),

      // Only show weapon name if it's NOT weapon + bullets
      // (because the name already appears in the header in that case)
      if (!(hasStolenWeapon && hasBullets))
        Text(
          widget.stolenWeapon!['name'] as String,
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
    ],
  ),
],

      // === SPACING LOGIC ===
    if (hasStolenWeapon && hasBullets)
      const SizedBox(width: 0),

    if (hasEpinephrine && hasBullets)
      const SizedBox(width: 32),

      // Epinephrine Image
      if (hasEpinephrine) ...[
        Column(
          children: [
            Image.asset(
              'assets/epinephrine_${widget.epinephrine!['quality']}.png',
              width: 80,
              height: 80,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.science, size: 70, color: Colors.purpleAccent),
            ),
            const SizedBox(height: 8),
            Text(
              'Quality ${widget.epinephrine!['quality']}',
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
          ],
        ),
      ],

      // Bullets with Badge
if (hasBullets) ...[
  if (hasStolenWeapon || hasEpinephrine) const SizedBox(width: 32),
  Stack(
    alignment: Alignment.center,
    children: [
      // Wrap the image with ClipRRect for rounded corners
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/bullet.jpg',
          width: 74,
          height: 74,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.circle, size: 70, color: Colors.orange),
        ),
      ),

      // Badge stays on top
      Positioned(
        bottom: 6,
        right: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'x${widget.bulletsStolen}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ],
  ),
],
    ],
  ),
],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Particles...
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