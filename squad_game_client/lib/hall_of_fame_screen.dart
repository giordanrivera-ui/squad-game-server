import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HallOfFameScreen extends StatefulWidget {
  const HallOfFameScreen({super.key});

  @override
  State<HallOfFameScreen> createState() => _HallOfFameScreenState();
}

class _HallOfFameScreenState extends State<HallOfFameScreen> {
  Future<List<Map<String, dynamic>>> _loadAllTimeRichest() async {
    final List<Map<String, dynamic>> allPlayers = [];

    // Live players
    final liveSnapshot = await FirebaseFirestore.instance
        .collection('players')
        .where('displayName', isNotEqualTo: null)
        .orderBy('balance', descending: true)
        .limit(10)
        .get();

    for (var doc in liveSnapshot.docs) {
      final data = doc.data();
      allPlayers.add({
        'name': data['displayName'] ?? 'Unknown',
        'balance': (data['balance'] as num?)?.toInt() ?? 0,
        'isDead': false,
      });
    }

    // Dead profiles (final wealth)
    final deadSnapshot = await FirebaseFirestore.instance
        .collection('deadProfiles')
        .orderBy('balance', descending: true)
        .limit(10)
        .get();

    for (var doc in deadSnapshot.docs) {
      final data = doc.data();
      allPlayers.add({
        'name': data['displayName'] ?? 'Unknown',
        'balance': (data['balance'] as num?)?.toInt() ?? 0,
        'isDead': true,
      });
    }

    // Sort by wealth (richest first)
    allPlayers.sort((a, b) => (b['balance'] as int).compareTo(a['balance'] as int));

    // Take top 5
    final top5 = allPlayers.take(5).toList();
    while (top5.length < 5) {
      top5.add({'name': '—', 'balance': 0, 'isDead': false});
    }

    return top5;
  }

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
            const SizedBox(height: 8),
            const Text(
              'Live players + deceased legends',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadAllTimeRichest(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          const Text(
                            'Hall of Fame requires a Firestore index',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Please click the link in the terminal and create the index.\nIt only takes 1–2 minutes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () => setState(() {}), // retry
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  final topPlayers = snapshot.data ?? [];

                  return Card(
                    elevation: 4,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(Colors.orange.shade50),
                      columns: const [
                        DataColumn(label: Text('Rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                        DataColumn(label: Text('Player', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      ],
                      rows: List.generate(5, (index) {
                        final player = topPlayers[index];
                        final name = player['name'] as String;
                        final isDead = player['isDead'] as bool;
                        final displayName = isDead ? '$name (Deceased)' : name;

                        return DataRow(
                          cells: [
                            DataCell(Text('${index + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                            DataCell(Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 18,
                                color: isDead ? Colors.red[700] : Colors.black,
                                fontStyle: isDead ? FontStyle.italic : FontStyle.normal,
                              ),
                            )),
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