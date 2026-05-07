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
              const SizedBox(height: 60),

              // Release Hospital Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Release Hospital'),
                        content: const Text(
                          'Are you sure you want to release this hospital?\n\n'
                          'It will no longer belong to you and can be claimed by any other player.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Release Hospital'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      SocketService().socket?.emit('release-hospital', {
                        'docId': hospital['docId'],
                      });

                      Navigator.pop(context); // Close manager screen
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Hospital released successfully.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: Colors.red[700],
                  ),
                  child: const Text(
                    'Release Hospital',
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