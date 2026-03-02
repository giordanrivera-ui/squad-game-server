import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'dart:async';

class PrisonScreen extends StatefulWidget {
  const PrisonScreen({super.key});

  @override
  State<PrisonScreen> createState() => _PrisonScreenState();
}

class _PrisonScreenState extends State<PrisonScreen> {
  List<Map<String, dynamic>> _imprisonedPlayers = [];
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();

    // Listen for live prison list updates from server
    SocketService().socket?.on('prison-list-update', (data) {
      if (data is List) {
        setState(() {
          _imprisonedPlayers = List<Map<String, dynamic>>.from(data);
        });
      }
    });

    // Initial fetch (in case someone is already in prison)
    _requestPrisonList();

    // Live countdown refresh every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {}); // Rebuild to update timers
    });
  }

  void _requestPrisonList() {
    SocketService().socket?.emit('request-prison-list');
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _getTimeLeft(int prisonEndTime) {
    final remaining = prisonEndTime - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return "Free";

    final seconds = (remaining / 1000).ceil();
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;

    return minutes > 0 ? "${minutes}m ${secs}s" : "${secs}s";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Prison'),
        backgroundColor: Colors.red[900],
        centerTitle: true,
      ),
      body: _imprisonedPlayers.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gavel, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    'The prison is empty.',
                    style: TextStyle(fontSize: 20, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _imprisonedPlayers.length,
              itemBuilder: (context, index) {
                final player = _imprisonedPlayers[index];
                final name = player['displayName'] ?? 'Unknown';
                final endTime = player['prisonEndTime'] ?? 0;

                return Card(
                  color: Colors.grey[850],
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.person_off, color: Colors.redAccent, size: 40),
                    title: Text(
                      name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    subtitle: Text(
                      _getTimeLeft(endTime),
                      style: const TextStyle(fontSize: 16, color: Colors.orangeAccent),
                    ),
                    trailing: const Icon(Icons.timer, color: Colors.grey),
                  ),
                );
              },
            ),
    );
  }
}