import 'package:flutter/material.dart';
import 'dart:async';

class PeterSightingOverlay extends StatefulWidget {
  final String message;
  final int hunger;
  final VoidCallback onDismiss;

  const PeterSightingOverlay({
    super.key,
    required this.message,
    required this.hunger,
    required this.onDismiss,
  });

  @override
  State<PeterSightingOverlay> createState() => _PeterSightingOverlayState();
}

class _PeterSightingOverlayState extends State<PeterSightingOverlay>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  Timer? _restoreTimer;
  Timer? _undoTimer;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  bool _isDiminished = false;
  bool _isUserExpanded = false;
  bool _isSwipedAway = false;

  // Diminished state values
  static const double _diminishedScale = 0.85;
  static const double _diminishedOpacity = 0.78;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 550),
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

    // 25-second auto-dismiss
    _timer = Timer(const Duration(seconds: 25), () {
      if (mounted) widget.onDismiss();
    });

    // 17-second diminish trigger
    Future.delayed(const Duration(seconds: 17), () {
      if (mounted && !_isUserExpanded && !_isSwipedAway) {
        setState(() {
          _isDiminished = true;
        });
      }
    });
  }

  void _handleTap() {
    if (_isUserExpanded || _isSwipedAway) return;

    setState(() {
      _isUserExpanded = true;
    });

    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isUserExpanded = false;
        });
      }
    });
  }

  void _onSwipedAway(DismissDirection direction) {
    setState(() {
      _isSwipedAway = true;
    });

    // Cancel any pending restore or diminish timers
    _restoreTimer?.cancel();

    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        widget.onDismiss(); // Permanently dismiss after 4 seconds
      }
    });
  }

  void _undoSwipe() {
    _undoTimer?.cancel();
    setState(() {
      _isSwipedAway = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restoreTimer?.cancel();
    _undoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth > 400 ? 250.0 : screenWidth * 0.50;

    // If swiped away, show undo icon
    if (_isSwipedAway) {
      return Positioned(
        bottom: bottomPadding + 10,
        right: 20,
        child: GestureDetector(
          onTap: _undoSwipe,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.orangeAccent, width: 1.5),
            ),
            child: const Icon(
              Icons.undo_rounded,
              color: Colors.orangeAccent,
              size: 24,
            ),
          ),
        ),
      );
    }

    final double currentScale = _isUserExpanded
        ? 1.0
        : (_isDiminished ? _diminishedScale : 1.0);

    final double currentOpacity = _isUserExpanded
        ? 1.0
        : (_isDiminished ? _diminishedOpacity : 1.0);

    return Positioned(
      bottom: bottomPadding + 10,
      right: 20,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.bottomRight,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Dismissible(
            key: const ValueKey('peter_sighting_overlay'),
            direction: DismissDirection.startToEnd, // Swipe right to dismiss
            onDismissed: _onSwipedAway,
            child: GestureDetector(
              onTap: _handleTap,
              child: AnimatedScale(
                scale: currentScale,
                alignment: Alignment.centerRight,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  opacity: currentOpacity,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 12,
                    child: Container(
                      width: cardWidth,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2416),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.orangeAccent.withOpacity(0.65),
                          width: 1.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.55),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.person_outline_rounded,
                                  color: Colors.orangeAccent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Peter the Beggar',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Message
                          Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),

                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'He walks by...',
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}