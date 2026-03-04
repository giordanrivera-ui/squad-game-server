import 'package:flutter/material.dart';
import 'dart:async';
import 'socket_service.dart';

class PrisonScreen extends StatefulWidget {
  final String currentDisplayName;

  const PrisonScreen({
    super.key,
    required this.currentDisplayName,
  });

  @override
  State<PrisonScreen> createState() => _PrisonScreenState();
}

class _PrisonScreenState extends State<PrisonScreen> {
  Timer? _countdownTimer;
  int _myRemainingSeconds = 0;   // ← Instant self-status

  bool get _isViewerInPrison => _myRemainingSeconds > 0;

  @override
  void initState() {
    super.initState();

    SocketService().requestPrisonList();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    SocketService().imprisonedPlayersNotifier.addListener(_updateUI);

    // Listen for rescue results
    SocketService().socket?.on('rescue-result', _handleRescueResult);

    // Listen for own prison status changes (instant feedback)
    SocketService().socket?.on('update-stats', _handleMyStats);
  }

  void _updateUI() => mounted ? setState(() {}) : null;

  void _handleRescueResult(dynamic data) {
    if (data is Map && mounted) {
      final String msg = data['message'] ?? '';
      final bool success = data['success'] ?? false;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: success ? Colors.green[700] : Colors.red[700],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _handleMyStats(dynamic data) {
    if (data is Map) {
      setState(() {
        _myRemainingSeconds = data['remainingSeconds'] ?? 0;
      });
    }
  }

  @override
  void dispose() {
    SocketService().imprisonedPlayersNotifier.removeListener(_updateUI);
    SocketService().socket?.off('rescue-result', _handleRescueResult);
    SocketService().socket?.off('update-stats', _handleMyStats);
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imprisonedPlayers = SocketService().imprisonedPlayersNotifier.value;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Prison'),
        backgroundColor: Colors.red[900],
        centerTitle: true,
      ),
      body: imprisonedPlayers.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gavel, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text('The prison is currently empty.',
                       style: TextStyle(fontSize: 20, color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: imprisonedPlayers.length,
              itemBuilder: (context, index) {
                final player = imprisonedPlayers[index];
                final name = player['displayName'] ?? 'Unknown';
                final remaining = player['remainingSeconds'] ?? 0;

                final bool isSelf = name == widget.currentDisplayName;
                final bool canSave = !_isViewerInPrison && !isSelf && remaining > 0;

                return Card(
                  color: Colors.grey[850],
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.person_off, color: Colors.redAccent, size: 40),
                    title: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: Text(
                      '${remaining}s',
                      style: const TextStyle(fontSize: 16, color: Colors.orangeAccent),
                    ),
                    trailing: canSave
                        ? TextButton(
                            onPressed: () => SocketService().attemptRescue(name),
                            style: TextButton.styleFrom(foregroundColor: Colors.green),
                            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }
}