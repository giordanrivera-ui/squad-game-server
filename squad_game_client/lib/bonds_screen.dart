import 'package:flutter/material.dart';
import 'socket_service.dart';

class PersonalBondsScreen extends StatefulWidget {
  const PersonalBondsScreen({super.key});

  @override
  State<PersonalBondsScreen> createState() => _PersonalBondsScreenState();
}

class _PersonalBondsScreenState extends State<PersonalBondsScreen> {
  @override
  void initState() {
    super.initState();
    SocketService().requestBondMarket(); // Ask server for current bonds
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Bonds'),
        backgroundColor: Colors.grey[900],
      ),
      backgroundColor: Colors.grey[850],
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: SocketService().bondMarketNotifier,
        builder: (context, bonds, child) {
          if (bonds.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Refresh Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      SocketService().refreshBondMarket();
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Refresh Bond Market',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),

              // Bond List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: bonds.length,
                  itemBuilder: (context, index) {
                    final bond = bonds[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.grey[900],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(bond['title'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 12),
                            Row(children: [
                              const Text('Coupon Rate: ', style: TextStyle(fontSize: 16, color: Colors.white70)),
                              Text('${bond['couponRate'].toStringAsFixed(1)}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amber)),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              const Text('Cost: ', style: TextStyle(fontSize: 16, color: Colors.white70)),
                              Text('\$${bond['cost'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                            ]),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Buying ${bond['title']}... (coming soon)'), backgroundColor: Colors.amber),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('BUY BOND', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}