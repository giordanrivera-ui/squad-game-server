import 'package:flutter/material.dart';
import 'dart:math';

class DeliverJusticeOverlay extends StatefulWidget {
  final bool isWinner;
  final int qualityScore;
  final String opponentName;
  final int witnessFinal;
  final int criminalFinal;
  final String witnessName;
  final String perpetratorName;
  final String? witnessArchetype;
  final String? criminalArchetype;
  final int? archetypeBonus;
  final int? dominanceBonus;
  final int? investmentBonus;
  final int? witnessRoll;
  final int? criminalRoll;

  final VoidCallback onDismiss;
  final bool? viewerIsWitness;

  const DeliverJusticeOverlay({
    super.key,
    required this.isWinner,
    required this.qualityScore,
    required this.opponentName,
    required this.witnessFinal,
    required this.criminalFinal,
    required this.witnessName,
    required this.perpetratorName,
    this.witnessArchetype,
    this.criminalArchetype,
    this.archetypeBonus,
    this.dominanceBonus,
    this.investmentBonus,
    this.witnessRoll,
    this.criminalRoll,
    
    required this.onDismiss,
    this.viewerIsWitness,
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
  bool _showDebug = true; // Debug open by default for testing

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 900), vsync: this);
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
  final bool isCriminal = widget.viewerIsWitness == false; // New field

  // Determine what text to show
  String title;
  String subtitle;

  if (won && !isCriminal) {
    // Witness won
    title = 'JUSTICE SERVED!';
    subtitle = 'You successfully delivered justice on ${widget.perpetratorName}!';
  } else if (won && isCriminal) {
    // Criminal won (escaped)
    title = 'You escaped justice!';
    subtitle = 'A player attempted to catch you but you escaped!';
  } else {
    // Lost
    title = 'JUSTICE FAILED';
    subtitle = isCriminal 
        ? '${widget.witnessName} failed to catch you.' 
        : '${widget.perpetratorName} got away from you.';
  }

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
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: won ? const Color(0xFF1B3A2F) : const Color(0xFF3D2A1F),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: won ? Colors.greenAccent : Colors.orangeAccent, 
                      width: 3
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (won ? Colors.greenAccent : Colors.orangeAccent).withOpacity(0.4),
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
                        size: 70, 
                        color: won ? Colors.greenAccent : Colors.orangeAccent
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 28, 
                          fontWeight: FontWeight.bold,
                          color: won ? Colors.greenAccent : Colors.orangeAccent
                        )
                      ),
                      const SizedBox(height: 12),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                        Text('Your Justice Score: ${widget.qualityScore}',
                            style: const TextStyle(fontSize: 15, color: Colors.white54)),

                        const SizedBox(height: 16),

                        // Debug Toggle
                        GestureDetector(
                          onTap: () => setState(() => _showDebug = !_showDebug),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bug_report, size: 16, color: Colors.white54),
                                const SizedBox(width: 6),
                                Text(_showDebug ? 'Hide Debug Breakdown' : 'Show Debug Breakdown',
                                    style: const TextStyle(fontSize: 13, color: Colors.white54)),
                              ],
                            ),
                          ),
                        ),

                        if (_showDebug) ...[
                          const SizedBox(height: 16),
                          _buildDebugBreakdown(),
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
                          child: Icon(
                            won ? Icons.stars_rounded : Icons.local_fire_department,
                            color: won ? Colors.greenAccent : Colors.orangeAccent,
                            size: 15,
                          ),
                        ),
                      ),
                    );
                  },
                )),

            if (_showTapHint)
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Text('Tap anywhere to continue',
                      style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.6), fontStyle: FontStyle.italic)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugBreakdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DEBUG BREAKDOWN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 12),

          // WITNESS
          Text('WITNESS (${widget.witnessName})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
          if (widget.witnessArchetype != null)
            Text('Archetype: ${widget.witnessArchetype}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          if (widget.archetypeBonus != null)
            Text('Archetype Bonus: +${widget.archetypeBonus}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          if (widget.dominanceBonus != null)
            Text('Dominance Bonus: +${widget.dominanceBonus}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          if (widget.investmentBonus != null)
            Text('Investment Bonus: +${widget.investmentBonus}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          if (widget.witnessRoll != null)
            Text('Roll: ${widget.witnessRoll}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          Text('Final Score: ${widget.witnessFinal}', style: const TextStyle(fontSize: 12, color: Colors.white70)),

          const SizedBox(height: 12),

          // CRIMINAL
          Text('CRIMINAL (${widget.perpetratorName})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
          if (widget.criminalArchetype != null)
            Text('Archetype: ${widget.criminalArchetype}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const Text('Loser Score: 20 (fixed)', style: TextStyle(fontSize: 12, color: Colors.white70)),
          if (widget.criminalRoll != null)
            Text('Roll: ${widget.criminalRoll}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          Text('Final Score: ${widget.criminalFinal}', style: const TextStyle(fontSize: 12, color: Colors.white70)),

          const SizedBox(height: 12),

          Text(
            widget.witnessFinal > widget.criminalFinal
                ? '→ WITNESS WINS THE CONFRONTATION'
                : '→ CRIMINAL WINS THE CONFRONTATION',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: widget.witnessFinal > widget.criminalFinal ? Colors.greenAccent : Colors.orangeAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class Particle {
  final double x = Random().nextDouble() * 500 - 80;
  final double y = Random().nextDouble() * 650 + 120;
  final double rotation = Random().nextDouble() * 18 - 9;
}