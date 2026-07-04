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

class _PeterSightingOverlayState extends State<PeterSightingOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Auto-dismiss after 20 seconds (matches server vicinity update cycle)
    _timer = Timer(const Duration(seconds: 20), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;

    // Responsive width: max 340px or 85% of screen (whichever is smaller)
    final cardWidth = screenWidth > 400 ? 340.0 : screenWidth * 0.85;

    return Positioned(
      bottom: bottomPadding + 10,
      right: 20,
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2416), // Warm dark brown (beggar / street vibe)
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
              // Header row with icon + title
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

              // The actual sighting message from server
              Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),

              // Subtle hint that it's a temporary sighting
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
    );
  }
}