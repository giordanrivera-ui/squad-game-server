import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'dart:async';

class OperationsScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final int lastLowLevelOp;
  final int prisonEndTime;

  const OperationsScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.lastLowLevelOp,
    required this.prisonEndTime,
  });

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  int _prisonEndTime = 0;
  Timer? _countdownTimer;
  String? _selectedOperation;

  bool get _isInPrison => _prisonEndTime > DateTime.now().millisecondsSinceEpoch;

  int get _remainingSeconds {
    if (!_isInPrison) return 0;
    return ((_prisonEndTime - DateTime.now().millisecondsSinceEpoch) / 1000)
        .ceil()
        .clamp(0, 60);
  }

  @override
  void initState() {
    super.initState();
    _prisonEndTime = widget.prisonEndTime;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // ←←← FIXED: Attach listener ONLY ONCE here (stable context)
    SocketService().socket?.on('operation-result', _onOperationResult);
  }

  void _onOperationResult(dynamic data) {
    if (data == null || !mounted) return;

    final String message = data['message'] ?? 'Operation completed.';
    final int rawDamage = data['rawDamage'] ?? 0;
    final int actualDamage = data['actualDamage'] ?? 0;
    final int totalDefense = data['totalDefense'] ?? 0;

    String finalMessage = message;
    if (totalDefense > 0 && rawDamage > 0) {
      finalMessage += '\nYour armor absorbed $totalDefense damage!';
      if (actualDamage > 0) {
        finalMessage += '\nYou only lost $actualDamage health.';
      } else {
        finalMessage += '\nYou took no damage!';
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(finalMessage),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() => _selectedOperation = null);
  }

  @override
  void didUpdateWidget(covariant OperationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prisonEndTime != oldWidget.prisonEndTime) {
      setState(() => _prisonEndTime = widget.prisonEndTime);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    SocketService().socket?.off('operation-result', _onOperationResult);
    super.dispose();
  }

  // ==================== PRISON OVERLAY + NORMAL UI (always inside Scaffold) ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ← Conditional background: dark only when in prison, otherwise normal app background
      backgroundColor: _isInPrison ? Colors.grey[900] : null,
      body: _isInPrison
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.gavel, size: 100, color: Colors.redAccent),
                  const SizedBox(height: 30),
                  const Text(
                    'YOU ARE IN PRISON',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Time left: $_remainingSeconds seconds',
                    style: const TextStyle(fontSize: 20, color: Colors.orangeAccent),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    'You cannot perform operations\nor travel while in prison.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : Column(
            
            
            // Normal operations UI (now on light/normal background again)
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: Colors.orange[50],
                  child: Column(
                    children: [
                      const Text('Operations in', style: TextStyle(fontSize: 18)),
                      Text(widget.currentLocation, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _showOperationBottomSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _selectedOperation ?? 'Select an operation',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ElevatedButton(
                              onPressed: _selectedOperation != null ? _executeOperation : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selectedOperation != null ? Colors.orange : Colors.grey,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                              ),
                              child: const Text(
                                'Execute Operation',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
  void _showOperationBottomSheet() {
    if (_isInPrison) return;
    // ... your existing _BottomSheetContent code (unchanged)
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _BottomSheetContent(
        lastLowLevelOp: widget.lastLowLevelOp,
        onSelected: (operation) {
          setState(() => _selectedOperation = operation);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _executeOperation() {
    if (_selectedOperation == null) return;
    SocketService().executeOperation(_selectedOperation!);
  }
}

// ==================== _BottomSheetContent (unchanged) ====================
class _BottomSheetContent extends StatefulWidget {
  final int lastLowLevelOp;
  final Function(String) onSelected;

  const _BottomSheetContent({
    required this.lastLowLevelOp,
    required this.onSelected,
    });

  @override
  State<_BottomSheetContent> createState() => _BottomSheetContentState();
}

class _BottomSheetContentState extends State<_BottomSheetContent> {
  Timer? _timer;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _startLiveCountdown();
  }

  void _startLiveCountdown() {
    final elapsed = DateTime.now().millisecondsSinceEpoch - widget.lastLowLevelOp;
    _remaining = ((60000 - elapsed) / 1000).ceil().clamp(0, 60);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remaining = (_remaining - 1).clamp(0, 60);
        if (_remaining <= 0) timer.cancel();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lowLevelOps = ["Mug a passerby", "Loot a grocery store", "Rob a bank", "Loot weapons store"];
    final isCooldown = _remaining > 0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select Operation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildGroup('Low Level', lowLevelOps, isCooldown),
          _buildGroup('Medium Level', ["Attack military barracks", "Storm a laboratory", "Attack central issue facility"], false),
          _buildGroup('High Level', ["Strike an armory", "Raid a vehicle depot", "Assault an aircraft hangar", "Invade country"], false),
        ],
      ),
    );
  }

  Widget _buildGroup(String title, List<String> ops, bool isCooldown) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        ...ops.map((op) {
          final displayText = isCooldown ? '$op ($_remaining s)' : op;
          return ListTile(
            title: Text(displayText),
            enabled: !isCooldown,
            onTap: isCooldown ? null : () => widget.onSelected(op),
          );
        }),
        const Divider(),
      ],
    );
  }
}