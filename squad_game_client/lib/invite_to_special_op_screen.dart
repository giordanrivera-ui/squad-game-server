import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InviteToSpecialOpScreen extends StatefulWidget {
  final String targetName;

  const InviteToSpecialOpScreen({super.key, required this.targetName});

  @override
  State<InviteToSpecialOpScreen> createState() => _InviteToSpecialOpScreenState();
}

class _InviteToSpecialOpScreenState extends State<InviteToSpecialOpScreen> {
  String? _selectedPosition;

  List<String> _getPositions() {
    final op = SocketService().statsNotifier.value['activeSpecialOperation']?.toString() ?? '';
    switch (op) {
      case 'Raid cartel supply line':
        return ['Operation Leader', 'Rifleman', 'Driver'];
      case 'Bank Heist':
        return ['Operation Leader', 'Gunner 1', 'Gunner 2', 'Driver'];
      case 'Siege military base':
        return ['Operation Leader', 'Gunner 1', 'Gunner 2', 'Driver', 'Artilleryman'];
      default:
        return ['Operation Leader'];
    }
  }

  String _getPartySizeText() {
    final positions = _getPositions();
    switch (positions.length) {
      case 3: return 'Raid cartel supply line (3/3)';
      case 4: return 'Bank Heist (4/4)';
      case 5: return 'Siege military base (5/5)';
      default: return 'Special Operation';
    }
  }

  void _sendInvitation() {
    if (_selectedPosition == null) return;

    final stats = SocketService().statsNotifier.value;
    final String leaderName = stats['displayName']?.toString() ?? 'A player';
    final String leaderEmail = FirebaseAuth.instance.currentUser?.email ?? ''; // safe
    final String operationName = stats['activeSpecialOperation']?.toString() ?? 'Special Operation';

    final inviteData = {
      'type': 'special_invite',
      'leader': leaderName,
      'leaderEmail': leaderEmail,           // ← NEW
      'position': _selectedPosition,
      'operation': operationName,
      'target': widget.targetName,
    };

    SocketService().sendPrivateMessage(widget.targetName, inviteData);

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invitation sent to ${widget.targetName} as $_selectedPosition!'), backgroundColor: Colors.orange),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positions = _getPositions();
    final currentOp = SocketService().statsNotifier.value['activeSpecialOperation']?.toString() ?? 'Unknown Op';

    return Scaffold(
      appBar: AppBar(title: Text('Invite ${widget.targetName}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Choose position for ${widget.targetName}', 
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), 
              textAlign: TextAlign.center,
            ),
          ),
          Text(currentOp, style: const TextStyle(fontSize: 18, color: Colors.orange)),
          const SizedBox(height: 8),
          Text(_getPartySizeText(), style: const TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 24),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: positions.map((title) {
                  final bool isLeader = title == 'Operation Leader';
                  final bool isSelected = _selectedPosition == title;

                  return Column(
                    children: [
                      GestureDetector(
                        onTap: isLeader 
                          ? null 
                          : () => setState(() => _selectedPosition = title),
                        child: Card(
                          elevation: isSelected ? 8 : 4,
                          color: isSelected ? Colors.orange[100] : null,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                if (isLeader)
                                  const CircleAvatar(
                                    radius: 28, 
                                    backgroundColor: Colors.grey, 
                                    child: Icon(Icons.person, size: 32),
                                    )
                                else
                                  Container(
                                    width: 56, 
                                    height: 56, 
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300], 
                                      borderRadius: BorderRadius.circular(12),
                                    ), 
                                    child: const Icon(Icons.person_add, size: 32, color: Colors.grey),
                                  ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      if (isLeader)
                                        const Text('You (filled)', style: TextStyle(color: Colors.orangeAccent))
                                      else if (isSelected)
                                        const Text('Selected for invitation', style: TextStyle(color: Colors.green))
                                      else
                                        const Text('Vacant — Tap to select', style: TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedPosition == null ? null : _sendInvitation,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(_selectedPosition == null ? 'Select a position' : 'Confirm Invitation — $_selectedPosition', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}