import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'dart:async';
import 'operation_result_overlay.dart';
import 'package:flutter/services.dart';
import 'special_ops_tab.dart';
import 'game_header.dart';
import 'package:google_fonts/google_fonts.dart';

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
  final bool hasEnhancedStamina;
  final String time;
  final VoidCallback onMenuPressed;

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
    this.hasEnhancedStamina = false,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int _prisonEndTime = 0;
  Timer? _countdownTimer;
  String? _selectedRegularOperation;

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

    _tabController = TabController(length: 2, vsync: this);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    SocketService().socket?.on('operation-result', _onOperationResult);
  }

  OverlayEntry? _operationResultOverlay;

  void _onOperationResult(dynamic data) {
    if (data == null || !mounted) return;

    final bool success = data['isCaught'] != true;

    if (success) {
      _operationResultOverlay?.remove();

      _operationResultOverlay = OverlayEntry(
        builder: (context) => OperationResultOverlay(
          operation: data['operation'] ?? 'Operation',
          money: data['money'] ?? 0,
          message: data['message'] ?? 'Operation successful!',
          actualDamage: data['actualDamage'] ?? 0,
          totalDefense: data['totalDefense'] ?? 0,
          stolenWeapon: data['stolenWeapon'],
          epinephrine: data['epinephrine'],
          bulletsStolen: data['bulletsStolen'] ?? 0,
          onDismiss: () {
            _operationResultOverlay?.remove();
            _operationResultOverlay = null;
          },
        ),
      );

      Overlay.of(context).insert(_operationResultOverlay!);
      HapticFeedback.mediumImpact();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['message'] ?? 'Operation failed.'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 4),
        ),
      );
    }

    setState(() {
      _selectedRegularOperation = null;
    });
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
    _tabController.dispose();
    SocketService().socket?.off('operation-result', _onOperationResult);
    _operationResultOverlay?.remove();
    super.dispose();
  }

  void _executeOperation() {
    if (_selectedRegularOperation == null) return;
    SocketService().executeOperation(_selectedRegularOperation!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isInPrison ? Colors.grey[900] : null,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            // ==================== GAME HEADER ====================
            GameHeader(
              statsNotifier: SocketService().statsNotifier,
              time: widget.time,
              onMenuPressed: widget.onMenuPressed,
            ),

            // ==================== MAIN CONTENT ====================
            Expanded(
              child: SafeArea(
                top: false,
                child: _isInPrison
                    ? _buildPrisonView()
                    : _buildOperationsContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PRISON VIEW ====================
  Widget _buildPrisonView() {
    return Center(
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
    );
  }

  // ==================== MAIN OPERATIONS CONTENT ====================
  Widget _buildOperationsContent() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
          child: Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(text: 'Operations\n', style: GoogleFonts.bebasNeue(fontSize: 38, fontWeight: FontWeight.bold, color: const Color.fromARGB(211, 255, 255, 255), letterSpacing: 1.8)),
                  TextSpan(text: widget.currentLocation.toUpperCase(), style: GoogleFonts.robotoCondensed(fontSize: 24, color: const Color.fromARGB(255, 165, 165, 165), fontWeight: FontWeight.w200, height: 0.95, letterSpacing: 2)),
                ]
              )
            )
          )
        ),

        Expanded(
          child: Container(
            color: Colors.black.withOpacity(0.25),
            child: Column(
            children: [
              TabBar(
                controller: _tabController,
                labelColor: Colors.orange,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.orange,
                tabs: const [
                  Tab(text: 'Regular Ops'),
                  Tab(text: 'Special Ops'),
                ],
              ),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Regular Ops Tab
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _showRegularOperationBottomSheet,
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
                                    _selectedRegularOperation ?? 'Select an operation',
                                    style: const TextStyle(fontSize: 16, color:  Color.fromARGB(179, 255, 255, 255)),
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
                                onPressed: _selectedRegularOperation != null ? _executeOperation : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _selectedRegularOperation != null ? Colors.orange : Colors.grey,
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

                    // Special Ops Tab
                    Center(
                      child: SpecialOpsTab(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          )
        ),
      ],
    );
  }

  void _showRegularOperationBottomSheet() {
    if (_isInPrison) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _BottomSheetContent(
        lastLowLevelOp: widget.lastLowLevelOp,
        lastMidLevelOp: widget.lastMidLevelOp,
        lastHighLevelOp: widget.lastHighLevelOp,
        skill: widget.skill,
        hasEnhancedStamina: widget.hasEnhancedStamina,
        onSelected: (operation) {
          setState(() => _selectedRegularOperation = operation);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ==================== BOTTOM SHEET CONTENT (unchanged) ====================
class _BottomSheetContent extends StatefulWidget {
  final int lastLowLevelOp;
  final int lastMidLevelOp;
  final int lastHighLevelOp;
  final int skill;
  final bool hasEnhancedStamina;
  final Function(String) onSelected;

  const _BottomSheetContent({
    required this.lastLowLevelOp,
    required this.lastMidLevelOp,
    required this.lastHighLevelOp,
    required this.skill,
    this.hasEnhancedStamina = false,
    required this.onSelected,
  });

  @override
  State<_BottomSheetContent> createState() => _BottomSheetContentState();
}

class _BottomSheetContentState extends State<_BottomSheetContent> {
  double _lowRemaining = 0.0;
  double _midRemaining = 0.0;
  double _highRemaining = 0.0;

  double _boneLow = 0.0;
  double _boneMid = 0.0;
  double _boneHigh = 0.0;

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
    double reduction = skill * 0.5;

    if (widget.hasEnhancedStamina) {
      reduction += 3.0;
    }

    final stats = SocketService().statsNotifier.value;

    _boneLow = (stats['bonePenaltyEndTimeLow'] ?? 0) > now
        ? (((stats['bonePenaltyEndTimeLow'] ?? 0) - now) / 1000).clamp(0.0, 10.0)
        : 0.0;
    _boneMid = (stats['bonePenaltyEndTimeMid'] ?? 0) > now
        ? (((stats['bonePenaltyEndTimeMid'] ?? 0) - now) / 1000).clamp(0.0, 10.0)
        : 0.0;
    _boneHigh = (stats['bonePenaltyEndTimeHigh'] ?? 0) > now
        ? (((stats['bonePenaltyEndTimeHigh'] ?? 0) - now) / 1000).clamp(0.0, 10.0)
        : 0.0;

    if (_boneLow > 0.1) {
      _lowRemaining = (60 - reduction).clamp(0.0, 60.0);
    } else {
      _lowRemaining = ((60000 - (now - widget.lastLowLevelOp)) / 1000 - reduction).clamp(0.0, 60.0);
    }

    if (_boneMid > 0.1) {
      _midRemaining = (72 - reduction).clamp(0.0, 72.0);
    } else {
      _midRemaining = ((72000 - (now - widget.lastMidLevelOp)) / 1000 - reduction).clamp(0.0, 72.0);
    }

    if (_boneHigh > 0.1) {
      _highRemaining = (80 - reduction).clamp(0.0, 80.0);
    } else {
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
          const Text('Select Operation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildGroup('Low Level', lowLevelOps, _lowRemaining, _boneLow),
          _buildGroup('Medium Level', midLevelOps, _midRemaining, _boneMid),
          _buildGroup('High Level', highLevelOps, _highRemaining, _boneHigh),
        ],
      ),
    );
  }

  Widget _buildGroup(String title, List<String> ops, double remaining, double boneRemaining) {
    final bool isOnCooldown = remaining > 0.1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              if (boneRemaining > 0.1)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '🦴 ${boneRemaining.toStringAsFixed(1)} s',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
            ],
          ),
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