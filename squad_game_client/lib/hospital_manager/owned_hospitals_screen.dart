import 'package:flutter/material.dart';
import '../socket_service.dart';
import '../status_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'hospital_manager_screen.dart';

class OwnedHospitalsScreen extends StatelessWidget {
  const OwnedHospitalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String? myEmail = FirebaseAuth.instance.currentUser?.email;

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: SocketService().hospitalOwnershipNotifier,
      builder: (context, ownership, child) {
        final myHospitals = <Map<String, dynamic>>[];

        ownership.forEach((docId, data) {
          final hospitalData = data as Map<String, dynamic>;
          if (hospitalData['ownerEmail'] == myEmail) {
            myHospitals.add({
              'docId': docId,
              ...hospitalData,
            });
          }
        });

        return Scaffold(
          appBar: StatusAppBar(
            title: 'Owned Hospitals',
            statsNotifier: SocketService().statsNotifier,
            time: 'Live',
            onMenuPressed: () => Navigator.pop(context),
          ),
          body: myHospitals.isEmpty
              ? const Center(
                  child: Text(
                    'You currently own no hospitals.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: myHospitals.length,
                  itemBuilder: (context, index) {
                    final h = myHospitals[index];
                    final location = h['location'] ?? 'Unknown';
                    final indexNum = h['index'] ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.local_hospital, color: Colors.purple, size: 48),
                        title: Text('$location Hospital #$indexNum'),
                        subtitle: Text('Hospital ID: ${h['docId']}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HospitalManagerScreen(hospital: h),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}