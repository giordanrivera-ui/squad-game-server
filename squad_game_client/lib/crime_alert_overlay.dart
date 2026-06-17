import 'package:flutter/material.dart';
import 'dart:async';

class CrimeAlertOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onIgnore;
  final VoidCallback onDeliverJustice;

  const CrimeAlertOverlay({
    super.key,
    required this.message,
    required this.onIgnore,
    required this.onDeliverJustice,
  });

  @override
  State<CrimeAlertOverlay> createState() => _CrimeAlertOverlayState();
}

class _CrimeAlertOverlayState extends State<CrimeAlertOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Keep the 6-second auto-dismiss as a fallback
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        widget.onIgnore();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF3D1F1F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent.withOpacity(0.7), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ==================== TWO BUTTONS ====================
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onIgnore,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Ignore the crime'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.onDeliverJustice,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Deliver justice',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}