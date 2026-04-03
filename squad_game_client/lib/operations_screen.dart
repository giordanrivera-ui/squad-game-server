import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

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

class _OperationsScreenState extends State<OperationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int _prisonEndTime = 0;
  Timer? _countdownTimer;
  String? _selectedRegularOperation;
  String? _selectedSpecialOperation;

  bool _isOperationInitiated = false;
  bool _isInitiating = false;

  Timer? _initiateTimer;

  final Map<String, Map<String, dynamic>> _assignedWeapons = {};

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
    SocketService().socket?.on('special-op-initiated', _onSpecialOpInitiated);
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

    setState(() {
      _selectedRegularOperation = null;
      _selectedSpecialOperation = null;
      _assignedWeapons.clear(); // reset for next op
      _isOperationInitiated = false; // NEW: reset flag after any operation finishes
    });
  }

  @override
  void didUpdateWidget(covariant OperationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prisonEndTime != oldWidget.prisonEndTime) {
      setState(() => _prisonEndTime = widget.prisonEndTime);
    }
  }

  // NEW: Server confirmation handler
  void _onSpecialOpInitiated(dynamic data) {
    if (data is! Map || !mounted) return;

    _initiateTimer?.cancel();

    final bool success = data['success'] == true;
    final String serverMessage = data['message'] ?? '';

    setState(() {
      _isInitiating = false;                    // stop spinner in all cases

      if (success) {
        _isOperationInitiated = true;           // now show party layout + enable weapons
      } else {
        _isOperationInitiated = false;          // keep button visible
      }
    });

    // Show appropriate snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(serverMessage.isNotEmpty 
            ? serverMessage 
            : success 
                ? 'Special Operation initiated! You may now equip weapons.' 
                : 'Not enough money to initiate this operation.'),
        backgroundColor: success ? Colors.green : Colors.red[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _initiateTimer?.cancel();
    _countdownTimer?.cancel();
    _tabController.dispose();
    SocketService().socket?.off('operation-result', _onOperationResult);
    SocketService().socket?.off('special-op-initiated', _onSpecialOpInitiated);
    super.dispose();
  }

  void _executeOperation() {
    final String? op = _tabController.index == 0
        ? _selectedRegularOperation
        : _selectedSpecialOperation;

    if (op == null) return;

    SocketService().executeOperation(op);
  }

  void _onSpecialOpChanged(String? value) {
    setState(() {
      _selectedSpecialOperation = value;
      _isOperationInitiated = false; // Reset when changing op
      _isInitiating = false;
      _assignedWeapons.clear();
    });
  }

  // NEW: Initiate the special operation – now shows loading instead of optimistic UI
  void _initiateSpecialOperation() {
    if (_selectedSpecialOperation == null || _isInitiating) return;

    setState(() => _isInitiating = true);

    // Cancel any previous timer
    _initiateTimer?.cancel();

    SocketService().socket?.emit('initiate-special-op', {
      'operation': _selectedSpecialOperation,
    });

    // === TIMEOUT SAFETY NET ===
    _initiateTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_isInitiating) return;

      setState(() => _isInitiating = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No response from server. Please try again.'),
          backgroundColor: Colors.red[700],
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  // ==================== EQUIP SPECIAL-OP WEAPON ====================
  void _equipSpecialWeapon(String positionTitle) {
    final inventory = SocketService().statsNotifier.value['inventory'] as List<dynamic>? ?? [];
    final weapons = inventory.where((item) => (item['type'] as String?) == 'weapon').toList();

    if (weapons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have no weapons in your inventory.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Equip $positionTitle with weapon'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: weapons.length,
            itemBuilder: (context, index) {
              final weapon = weapons[index] as Map<String, dynamic>;
              return ListTile(
                leading: Image.asset(
                  'assets/${weapon['name']}.jpg',
                  width: 40,
                  height: 40,
                  errorBuilder: (_, __, ___) => const Icon(Icons.whatshot, size: 40),
                ),
                title: Text(weapon['name'] as String),
                subtitle: Text('Power: ${weapon['power'] ?? 0}'),
                onTap: () {
                  SocketService().socket?.emit('assign-special-weapon', {
                    'position': positionTitle,
                    'weapon': weapon,
                  });

                  setState(() {
                    _assignedWeapons[positionTitle] = weapon;
                  });
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                            // Regular Ops Tab (unchanged)
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

                            // ==================== SPECIAL OPS TAB ====================
                            Center(
                              child: Column(
                                children: [
                                  const SizedBox(height: 20),
                                  Container(
                                    width: 300,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: DropdownButton<String>(
                                      isExpanded: true,
                                      hint: const Text('Select Special Op'),
                                      value: _selectedSpecialOperation,
                                      items: const [
                                        DropdownMenuItem(value: 'Raid cartel supply line', child: Text('Raid cartel supply line')),
                                        DropdownMenuItem(value: 'Bank Heist', child: Text('Bank Heist')),
                                        DropdownMenuItem(value: 'Siege military base', child: Text('Siege military base')),
                                      ],
                                      onChanged: _onSpecialOpChanged,
                                    ),
                                  ),

                                  if (_selectedSpecialOperation != null) ...[
                                    const SizedBox(height: 24),
                                    Text(
                                      _selectedSpecialOperation!,
                                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.orange),
                                    ),
                                    const SizedBox(height: 24),

                                    // ==================== LOADING / BUTTON / PARTY TEXT ====================
                                    if (!_isOperationInitiated)
                                      SizedBox(
                                        width: double.infinity,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 24),
                                          child: ElevatedButton(
                                            onPressed: _isInitiating 
                                                ? null 
                                                : _initiateSpecialOperation,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red[700],
                                              padding: const EdgeInsets.symmetric(vertical: 18),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            child: _isInitiating
                                                ? const SizedBox(
                                                    height: 22,
                                                    width: 22,
                                                    child: CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                                  )
                                                : const Text(
                                                    'Initiate Special Operation',
                                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                  ),
                                          ),
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 24),
                                        child: Text(
                                          _getPartySizeText(),
                                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),

                                    const SizedBox(height: 32),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                                        child: _buildPartyLayout(),
                                      ),
                                    ),
                                  ] else
                                    const Padding(
                                      padding: EdgeInsets.only(top: 40),
                                      child: Text(
                                        '(Select a Special Op above)',
                                        style: TextStyle(fontSize: 16, color: Colors.grey),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ==================== DYNAMIC PARTY SIZE TEXT ====================
  String _getPartySizeText() {
    switch (_selectedSpecialOperation) {
      case 'Raid cartel supply line':
        return 'Assemble your crew (3/3 required)';
      case 'Bank Heist':
        return 'Assemble your crew (4/4 required)';
      case 'Siege military base':
        return 'Assemble your crew (5/5 required)';
      default:
        return '';
    }
  }

  // ==================== DYNAMIC PARTY LAYOUT ====================
  Widget _buildPartyLayout() {
    final currentPlayer = FirebaseAuth.instance.currentUser;
    final stats = SocketService().statsNotifier.value;

    List<String> positions;
    switch (_selectedSpecialOperation) {
      case 'Raid cartel supply line':
        positions = ['Operation Leader', 'Rifleman', 'Driver'];
        break;
      case 'Bank Heist':
        positions = ['Operation Leader', 'Gunner 1', 'Gunner 2', 'Driver'];
        break;
      case 'Siege military base':
        positions = ['Operation Leader', 'Gunner 1', 'Gunner 2', 'Driver', 'Artilleryman'];
        break;
      default:
        positions = [];
    }

    return Column(
      children: positions.map((title) {
        final bool isLeader = title == 'Operation Leader';
        return Column(
          children: [
            _buildPositionCard(
              title: title,
              playerName: isLeader ? (currentPlayer?.displayName ?? 'You') : null,
              photoURL: isLeader ? currentPlayer?.photoURL : null,
              rank: isLeader ? _getRankTitle(stats['experience'] ?? 0) : null,
              isFilled: isLeader,
            ),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  // ==================== UPDATED POSITION CARD WITH CLICKABLE WEAPON SLOT ====================
  Widget _buildPositionCard({
    required String title,
    String? playerName,
    String? photoURL,
    String? rank,
    required bool isFilled,
  }) {
    final assignedWeapon = _assignedWeapons[title];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Player info
            Row(
              children: [
                if (isFilled && photoURL != null)
                  CircleAvatar(radius: 28, backgroundImage: NetworkImage(photoURL))
                else if (isFilled)
                  const CircleAvatar(radius: 28, backgroundColor: Colors.grey, child: Icon(Icons.person, size: 32))
                else
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.person_add, size: 32, color: Colors.grey),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      if (isFilled)
                        Text(playerName ?? '', style: const TextStyle(fontSize: 16))
                      else
                        const Text('Vacant — Invite another player',
                            style: TextStyle(fontSize: 15, color: Colors.grey, fontStyle: FontStyle.italic)),
                      if (isFilled && rank != null)
                        Text(rank, style: const TextStyle(fontSize: 14, color: Colors.orangeAccent)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Weapon rectangle - DISABLED until operation is initiated
            GestureDetector(
              onTap: _isOperationInitiated ? () => _equipSpecialWeapon(title) : null,
              child: Container(
                width: 112,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isOperationInitiated ? Colors.orange.withOpacity(0.6) : Colors.grey.withOpacity(0.3),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: assignedWeapon != null
                      ? Image.asset(
                          'assets/${assignedWeapon['name']}.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset('assets/weapon-empty.jpg', fit: BoxFit.cover),
                        )
                      : Image.asset('assets/weapon-empty.jpg', fit: BoxFit.cover),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRankTitle(int exp) {
    if (exp <= 49) return 'Beggar';
    if (exp <= 514) return 'Thug';
    if (exp <= 1264) return 'Recruit';
    if (exp <= 2314) return 'Private';
    if (exp <= 3514) return 'Private First Class';
    if (exp <= 5014) return 'Corporal';
    if (exp <= 6864) return 'Sergeant';
    if (exp <= 8864) return 'Sergeant First Class';
    if (exp <= 10214) return 'Warrant Officer';
    if (exp <= 11464) return 'First Lieutenant';
    if (exp <= 14214) return 'Captain';
    if (exp <= 17414) return 'Major';
    if (exp <= 21364) return 'Lieutenant Colonel';
    if (exp <= 25864) return 'Colonel';
    if (exp <= 31514) return 'General';
    if (exp <= 38214) return 'General of the Army';
    return 'Supreme Commander';
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
        onSelected: (operation) {
          setState(() => _selectedRegularOperation = operation);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// _BottomSheetContent remains exactly the same as before
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
    final reduction = skill * 0.5;
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