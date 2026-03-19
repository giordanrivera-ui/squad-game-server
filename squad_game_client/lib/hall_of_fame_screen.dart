import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HallOfFameScreen extends StatelessWidget {
  const HallOfFameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hall of Fame')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Richest Players of All-Time',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Live-updating table
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('players')
                    .where('displayName', isNotEqualTo: null) // only real players
                    .orderBy('balance', descending: true)
                    .limit(5)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return const Center(child: Text('Error loading leaderboard'));
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final List<String> topNames = docs
                      .map((doc) => (doc.data() as Map<String, dynamic>)['displayName'] as String? ?? '—')
                      .toList();

                  // Pad to exactly 5 rows if fewer than 5 players exist
                  while (topNames.length < 5) {
                    topNames.add('—');
                  }

                  return Card(
                    elevation: 4,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(Colors.orange.shade50),
                      columns: const [
                        DataColumn(
                          label: Text('Rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        DataColumn(
                          label: Text('Player', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ],
                      rows: List.generate(5, (index) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                '${index + 1}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataCell(
                              Text(
                                topNames[index],
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}