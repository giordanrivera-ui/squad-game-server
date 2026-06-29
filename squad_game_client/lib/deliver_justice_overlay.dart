import 'package:flutter/material.dart';
import 'dart:math';
import 'socket_service.dart';

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
  final int? witnessInvestmentBonus;
  final int? witnessRoll;
  final int? criminalRoll;
  final bool? viewerIsWitness;
  final String? rpsWinner;
  final int? criminalInvestmentBonus;
  final VoidCallback onDismiss;

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
    this.witnessInvestmentBonus,
    this.witnessRoll,
    this.criminalRoll,
    this.viewerIsWitness,
    this.rpsWinner,
    this.criminalInvestmentBonus,
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
  bool _showDebug = true;

  // New state for confirmation flow (only for winning witness)
  bool _showCloseConfirmation = false;

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

  // Helper to determine if this is the winning witness
  bool get _isWinningWitness {
    final bool won = widget.isWinner;
    final bool isCriminal = widget.viewerIsWitness == false;
    return won && !isCriminal;
  }

  void _handleBackgroundTap() {
    if (_isWinningWitness) {
      // Winning witness → show confirmation instead of closing
      setState(() {
        _showCloseConfirmation = true;
      });
    } else {
      // Everyone else can close normally
      widget.onDismiss();
    }
  }

  void _confirmClose() {
    widget.onDismiss();
  }

  void _cancelClose() {
    setState(() {
      _showCloseConfirmation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool won = widget.isWinner;
    final bool isCriminal = widget.viewerIsWitness == false;

    // ==================== DYNAMIC TITLE & SUBTITLE ====================
    String title;
    String subtitle;

    if (won && !isCriminal) {
      title = 'JUSTICE SERVED!';
      subtitle = 'You successfully delivered justice on ${widget.perpetratorName}!';
    } else if (won && isCriminal) {
      title = 'You escaped justice!';
      subtitle = 'A player attempted to catch you but you escaped!';
    } else if (!won && isCriminal) {
      title = 'YOU WERE CAUGHT!';
      subtitle = 'A witness to your crime has delivered justice on you.';
    } else {
      title = 'JUSTICE FAILED';
      subtitle = '${widget.perpetratorName} got away from you.';
    }

    final bool showLootButtons = won && !isCriminal && !_showCloseConfirmation;

    return GestureDetector(
      // Background tap behavior
      onTap: _handleBackgroundTap,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Container(color: Colors.black.withOpacity(0.88)),

            // Main content card
            Center(
              child: GestureDetector(
                // Absorb taps on the card so it doesn't trigger background tap
                onTap: () {},
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
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (won ? Colors.greenAccent : Colors.orangeAccent).withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: _showCloseConfirmation
                          ? _buildCloseConfirmation()
                          : _buildMainContent(title, subtitle, showLootButtons),
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
                            size: 15,
                          ),
                        ),
                      ),
                    );
                  },
                )),

            if (_showTapHint && !_showCloseConfirmation)
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Tap outside to continue',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.6),
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

  // ==================== MAIN CONTENT (Loot Buttons) ====================
  Widget _buildMainContent(String title, String subtitle, bool showLootButtons) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.isWinner ? Icons.emoji_events_rounded : Icons.gavel_rounded,
          size: 70,
          color: widget.isWinner ? Colors.greenAccent : Colors.orangeAccent,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: widget.isWinner ? Colors.greenAccent : Colors.orangeAccent,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Text(
          'Your Justice Score: ${widget.qualityScore}',
          style: const TextStyle(fontSize: 15, color: Colors.white54),
        ),

        if (showLootButtons) ...[
          const SizedBox(height: 24),
          const Text(
            'What do you want to do with the loot?',
            style: TextStyle(fontSize: 15, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    SocketService().decideLootFate(widget.perpetratorName, 'return');
                    widget.onDismiss();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Return Loot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    SocketService().decideLootFate(widget.perpetratorName, 'take');
                    widget.onDismiss();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Take Loot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],

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
                Text(
                  _showDebug ? 'Hide Debug Breakdown' : 'Show Debug Breakdown',
                  style: const TextStyle(fontSize: 13, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),

        if (_showDebug) ...[
          const SizedBox(height: 16),
          _buildDebugBreakdown(),
        ],
      ],
    );
  }

  // ==================== CONFIRMATION SCREEN ====================
  Widget _buildCloseConfirmation() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 60, color: Colors.orangeAccent),
        const SizedBox(height: 20),
        const Text(
          'Do you want to let the criminal go?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _cancelClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _confirmClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Yes, Let Them Go', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDebugBreakdown() {
  final bool isTie = widget.rpsWinner == 'tie';

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
        if (widget.dominanceBonus != null && !isTie)
          Text('Dominance Bonus: +${widget.dominanceBonus}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        if (widget.witnessInvestmentBonus != null)
          Text('Investment Bonus: +${widget.witnessInvestmentBonus}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        if (widget.witnessRoll != null)
          Text('Roll: ${widget.witnessRoll}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        Text('Final Score: ${widget.witnessFinal}', style: const TextStyle(fontSize: 12, color: Colors.white70)),

        const SizedBox(height: 16),

        // CRIMINAL
        Text('CRIMINAL (${widget.perpetratorName})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
        if (widget.criminalArchetype != null)
          Text('Archetype: ${widget.criminalArchetype}', style: const TextStyle(fontSize: 12, color: Colors.white70)),

        if (isTie) ...[
          const Text('Archetype Bonus: +10', style: TextStyle(fontSize: 12, color: Colors.white70)),
          if (widget.criminalInvestmentBonus != null)
            Text('Investment Bonus: +${widget.criminalInvestmentBonus}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ] else ...[
          const Text('Loser Score: 20 (fixed)', style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],

        if (widget.criminalRoll != null)
          Text('Roll: ${widget.criminalRoll}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        Text('Final Score: ${widget.criminalFinal}', style: const TextStyle(fontSize: 12, color: Colors.white70)),

        const SizedBox(height: 12),

        Text(
          isTie
              ? '→ TIE (Both receive bonuses)'
              : widget.witnessFinal > widget.criminalFinal
                  ? '→ WITNESS WINS THE CONFRONTATION'
                  : '→ CRIMINAL WINS THE CONFRONTATION',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isTie
                ? Colors.amberAccent
                : widget.witnessFinal > widget.criminalFinal
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
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