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
  final int lastMidLevelOp;
  final int lastHighLevelOp;
  final int skill;

  const OperationsScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.lastLowLevelOp,
    required this.prisonEndTime,
    required this.lastMidLevelOp,
    required this.lastHighLevelOp, 
    required this.skill,
  });

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  int _prisonEndTime = 0;
  Timer? _countdownTimer;
  String? _selectedOperation;

  bool get _isInPrison => _prisonEndTime > SocketService().currentServerTime;

  int get _remainingSeconds {
    if (!_isInPrison) return 0;
    return ((_prisonEndTime - SocketService().currentServerTime) / 1000)
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
        lastMidLevelOp: widget.lastMidLevelOp,
        lastHighLevelOp: widget.lastHighLevelOp,
        skill: widget.skill,
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
  final int lastMidLevelOp;
  final int lastHighLevelOp;
  final int skill;
  final Function(String) onSelected;

  const _BottomSheetContent({
    required this.lastLowLevelOp,
    required this.lastMidLevelOp,
    required this.lastHighLevelOp,
    required this.skill,
    required this.onSelected,
    });

  @override
  State<_BottomSheetContent> createState() => _BottomSheetContentState();
}

class _BottomSheetContentState extends State<_BottomSheetContent> {
  double _lowRemaining = 0.0;
  double _midRemaining = 0.0;
  double _highRemaining = 0.0;
  double _boneRemaining = 0.0;   // NEW: separate broken bone timer

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _updateAllTimers();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(_updateAllTimers);
    });
  }

  void _updateAllTimers() {
    final now = SocketService().currentServerTime;
    final skill = widget.skill;
    final reduction = skill * 0.5;

    // NEW: Broken bone penalty timer (fixed 10s, no skill reduction)
    final boneEnd = SocketService().statsNotifier.value['bonePenaltyEndTime'] ?? 0;
    _boneRemaining = boneEnd > now ? ((boneEnd - now) / 1000).clamp(0.0, 10.0) : 0.0;

    if (_boneRemaining > 0.1) {
      // Normal timers are frozen at the skill-reduced value while bone penalty is active
      _lowRemaining = (60 - reduction).clamp(0.0, 60.0);
      _midRemaining = (72 - reduction).clamp(0.0, 72.0);
      _highRemaining = (80 - reduction).clamp(0.0, 80.0);
    } else {
      // Normal countdown (Skill reduction already applied)
      _lowRemaining = ((60000 - (now - widget.lastLowLevelOp)) / 1000 - reduction).clamp(0.0, 60.0);
      _midRemaining = ((72000 - (now - widget.lastMidLevelOp)) / 1000 - reduction).clamp(0.0, 72.0);
      _highRemaining = ((80000 - (now - widget.lastHighLevelOp)) / 1000 - reduction).clamp(0.0, 80.0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lowLevelOps = ["Mug a passerby", "Loot a grocery store", "Rob a bank", "Loot weapons store"];
    final midLevelOps = ["Attack military barracks", "Storm a laboratory", "Attack central issue facility"];
    final highLevelOps = ["Strike an armory", "Raid a vehicle depot", "Assault an aircraft hangar", "Invade country"];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NEW: Prominent broken bone recovery banner
          if (_boneRemaining > 0.1)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '🦴 Broken Bone Recovery: ${_boneRemaining.toStringAsFixed(1)} s\nNormal cooldown is frozen until this ends.',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),

          const Text('Select Operation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildGroup('Low Level', lowLevelOps, _lowRemaining),
          _buildGroup('Medium Level', midLevelOps, _midRemaining),
          _buildGroup('High Level', highLevelOps, _highRemaining),
        ],
      ),
    );
  }

  Widget _buildGroup(String title, List<String> ops, double remaining) {
    final bool isOnCooldown = remaining > 0.1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        ...ops.map((op) {
          String displayText = op;
          if (isOnCooldown) {
            displayText = '$op (${remaining.toStringAsFixed(1)} s)';
          }
          return ListTile(
            title: Text(displayText),
            enabled: !isOnCooldown,
            onTap: isOnCooldown ? null : () => widget.onSelected(op),
          );
        }),
        const Divider(),
      ],
    );
  }
}