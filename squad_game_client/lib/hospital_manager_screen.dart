import 'package:flutter/material.dart';
import 'status_app_bar.dart';
import 'socket_service.dart';

class HospitalManagerScreen extends StatelessWidget {
  final Map<String, dynamic> hospital;

  const HospitalManagerScreen({super.key, required this.hospital});

  @override
  Widget build(BuildContext context) {
    final String location = hospital['location'] ?? 'Unknown';
    final int index = hospital['index'] ?? 0;
    final String hospitalName = '$location Hospital #$index';

    return Scaffold(
      appBar: StatusAppBar(
        title: hospitalName,
        statsNotifier: SocketService().statsNotifier,
        time: 'Live',
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_hospital, size: 120, color: Colors.purple[300]),
              const SizedBox(height: 24),
              Text(
                hospitalName,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Placeholder button (does nothing for now)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Future functionality will go here
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Hospital settings coming soon...')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text(
                    'Manage Hospital',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}