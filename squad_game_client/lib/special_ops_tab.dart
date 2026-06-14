import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class SpecialOpsTab extends StatefulWidget {
  const SpecialOpsTab({super.key});

  @override
  State<SpecialOpsTab> createState() => _SpecialOpsTabState();
}

class _SpecialOpsTabState extends State<SpecialOpsTab> {
  // ==================== ALL SPECIAL OPS STATE AND LOGIC GOES HERE ====================

  bool _isInitiating = false;
  String? _selectedSpecialOperation;
  Timer? _initiateTimer;

  bool get _isOperationInitiated =>
      (SocketService().statsNotifier.value['activeSpecialOperation'] ?? '').toString().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _syncSelectedSpecialOpFromServer();
    SocketService().statsNotifier.addListener(_syncSelectedSpecialOpFromServer);
    SocketService().socket?.on('special-op-initiated', _onSpecialOpInitiated);
  }

  void _syncSelectedSpecialOpFromServer() {
    if (!mounted) return;

    final String? activeOp = SocketService().statsNotifier.value['activeSpecialOperation'] as String?;

    setState(() {
      _selectedSpecialOperation = (activeOp != null && activeOp.isNotEmpty) ? activeOp : null;
    });
  }

  void _onSpecialOpInitiated(dynamic data) {
    if (data is! Map || !mounted) return;

    _initiateTimer?.cancel();                    // Stop the 10-second timeout
    setState(() => _isInitiating = false);       // Hide the spinner

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(data['message'] ?? 'Special Operation initiated!'),
        backgroundColor: (data['success'] == true) ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _initiateTimer?.cancel();
    SocketService().statsNotifier.removeListener(_syncSelectedSpecialOpFromServer);
    SocketService().socket?.off('special-op-initiated', _onSpecialOpInitiated);
    super.dispose();
  }

  // ==================== SPECIAL OPS METHODS ====================


  void _onSpecialOpChanged(String? value) {
    if (_isOperationInitiated) return;
    setState(() {
      _selectedSpecialOperation = value;
      _isInitiating = false;
    });
  }

  void _initiateSpecialOperation() {
    if (_selectedSpecialOperation == null || _isInitiating) return;

    setState(() => _isInitiating = true);

    _initiateTimer?.cancel();

    SocketService().socket?.emit('initiate-special-op', {
      'operation': _selectedSpecialOperation,
    });

    _initiateTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_isInitiating) return;

      setState(() => _isInitiating = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No response from server. Please try again.'),
          backgroundColor: Colors.red[700],
        ),
      );
    });
  }

  void _cancelSpecialOperation() {
    SocketService().socket?.emit('cancel-special-op');
    setState(() {
      _selectedSpecialOperation = null;
    });
  }

  void _leaveSpecialOperation() {
    SocketService().leaveSpecialOperation();
    setState(() {
      _selectedSpecialOperation = null;
    });
  }

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

  Widget _buildPartyLayout(Map<String, dynamic>? party, {required bool isLeader}) {
    if (party == null) return const SizedBox.shrink();

    final positions = party['positions'] as Map<String, dynamic>? ?? {};

    return Column(
      children: positions.entries.map((entry) {
        final title = entry.key;
        final occupant = entry.value as Map<String, dynamic>?;

        return Column(
          children: [
            _buildPositionCard(
              title: title,
              playerName: occupant?['displayName'] ?? (title == 'Operation Leader' ? 'You' : null),
              photoURL: occupant?['photoURL'],
              rank: occupant?['rank'],
              isFilled: occupant != null,
              isLeaderView: isLeader,
              weapon: occupant?['weapon'],
            ),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildPositionCard({
    required String title,
    String? playerName,
    String? photoURL,
    String? rank,
    required bool isFilled,
    required bool isLeaderView,
    Map<String, dynamic>? weapon,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
            GestureDetector(
              onTap: (_isOperationInitiated && isLeaderView)
                  ? () => _equipSpecialWeapon(title)
                  : null,
              child: Container(
                width: 115,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isOperationInitiated && isLeaderView
                        ? Colors.orange.withOpacity(0.6)
                        : Colors.grey.withOpacity(0.3),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(9.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: weapon != null
                      ? Image.asset(
                          'assets/${weapon['name']}.jpg',
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: SocketService().specialOpPartyNotifier,
      builder: (context, partyFromNotifier, child) {
        final party = partyFromNotifier ??
            SocketService().statsNotifier.value['activeSpecialOperationParty'] as Map<String, dynamic>?;

        final bool isLeader = (party?['leaderEmail'] as String?) == FirebaseAuth.instance.currentUser?.email;

        return Column(
          children: [
            const SizedBox(height: 20),

            if (!_isOperationInitiated)
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
              const SizedBox(height: 12),
              Text(
                _selectedSpecialOperation!,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              const SizedBox(height: 6),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bolt, color: Colors.amber, size: 26),
                  const SizedBox(width: 8),
                  const Text(
                    'Overall Power: ',
                    style: TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${party?['overallPower'] ?? 0}',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.amber),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (!_isOperationInitiated)
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ElevatedButton(
                      onPressed: _isInitiating ? null : _initiateSpecialOperation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isInitiating
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
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
                  child: Column(
                    children: [
                      if (party != null)
                        _buildPartyLayout(party, isLeader: isLeader)
                      else
                        const Text('Party data not available', style: TextStyle(color: Colors.grey)),

                      if (_isOperationInitiated) ...[
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: ElevatedButton(
                              onPressed: isLeader ? _cancelSpecialOperation : _leaveSpecialOperation,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isLeader ? Colors.red[700] : Colors.orange[600],
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                isLeader ? 'Cancel Operation' : 'Leave Operation',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text('(Select a Special Op above)', style: TextStyle(fontSize: 16, color: Colors.grey)),
              ),
          ],
        );
      },
    );
  }
}