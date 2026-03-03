import 'package:flutter/material.dart';
import 'dart:async';
import 'socket_service.dart';

class PrisonScreen extends StatefulWidget {
  final String currentDisplayName;
  final int initialViewerPrisonEndTime;

  const PrisonScreen({
    super.key,
    required this.currentDisplayName,
    required this.initialViewerPrisonEndTime,
  });

  @override
  State<PrisonScreen> createState() => _PrisonScreenState();
}

class _PrisonScreenState extends State<PrisonScreen> {
  Timer? _countdownTimer;
  int _viewerPrisonEndTime = 0;

  bool get _isViewerInPrison => _viewerPrisonEndTime > DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _viewerPrisonEndTime = widget.initialViewerPrisonEndTime;

    SocketService().requestPrisonList();   // force fresh data on open

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Live updates
    SocketService().imprisonedPlayersNotifier.addListener(_updateUI);

    // Listen for own prison status changes
    SocketService().socket?.on('update-stats', _handleViewerStats);
    // Listen for rescue result
    SocketService().socket?.on('rescue-result', _handleRescueResult);
  }

  void _updateUI() {
    if (mounted) setState(() {});
  }

  void _handleViewerStats(dynamic data) {
    if (data is Map && data.containsKey('prisonEndTime')) {
      setState(() => _viewerPrisonEndTime = data['prisonEndTime'] ?? 0);
    }
  }

  void _handleRescueResult(dynamic data) {
    if (data is Map && mounted) {
      final String msg = data['message'] ?? '';
      final bool success = data['success'] ?? false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: success ? Colors.green[700] : Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    SocketService().imprisonedPlayersNotifier.removeListener(_updateUI);
    SocketService().socket?.off('update-stats', _handleViewerStats);
    SocketService().socket?.off('rescue-result', _handleRescueResult);
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _getTimeLeft(int prisonEndTime) {
    final remaining = prisonEndTime - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return "0s"; // Should never happen because server removes them

    final seconds = (remaining / 1000).ceil();
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return minutes > 0 ? "${minutes}m ${secs}s" : "${secs}s";
  }

  void _attemptRescue(String targetName) {
    SocketService().attemptRescue(targetName);
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
                final endTime = player['prisonEndTime'] ?? 0;

                final bool isSelf = name == widget.currentDisplayName;
                final bool canSave = !_isViewerInPrison && !isSelf;

                return Card(
                  color: Colors.grey[850],
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.person_off, color: Colors.redAccent, size: 40),
                    title: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: Text(
                      _getTimeLeft(endTime),
                      style: const TextStyle(fontSize: 16, color: Colors.orangeAccent),
                    ),
                    trailing: canSave
                        ? TextButton(
                            onPressed: () => _attemptRescue(name),
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