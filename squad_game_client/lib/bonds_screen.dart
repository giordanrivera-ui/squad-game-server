import 'package:flutter/material.dart';
import 'dart:math';

// ==================== BOND MODEL CLASS ====================
class Bond {
  final String title;
  final double couponRate; // e.g. 1.5
  final int cost;

  Bond(this.title, this.couponRate, this.cost);
}

class PersonalBondsScreen extends StatefulWidget {
  const PersonalBondsScreen({super.key});

  @override
  State<PersonalBondsScreen> createState() => _PersonalBondsScreenState();
}

class _PersonalBondsScreenState extends State<PersonalBondsScreen> {
  List<Bond> bonds = [];

  @override
  void initState() {
    super.initState();
    _generateRandomBonds();
  }

  void _generateRandomBonds() {
    final random = Random();
    bonds.clear();

    for (int i = 1; i <= 15; i++) {
      // Coupon Rate: 1.0% to 1.9% (nearest 0.1)
      final couponRate = 1.0 + (random.nextInt(10) * 0.1);

      // Cost: $400 to $500,000 (nearest $100)
      final cost = 400 + (random.nextInt(4997) * 100); // 4 to 5000 × 100

      bonds.add(
        Bond(
          'Bond Series #$i', // Placeholder title (you can customize later)
          couponRate,
          cost,
        ),
      );
    }

    // Optional: sort by cost ascending
    bonds.sort((a, b) => a.cost.compareTo(b.cost));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Bonds'),
        backgroundColor: Colors.grey[900],
      ),
      backgroundColor: Colors.grey[850],
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bonds.length,
        itemBuilder: (context, index) {
          final bond = bonds[index];

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            color: Colors.grey[900],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    bond.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Coupon Rate
                  Row(
                    children: [
                      const Text(
                        'Coupon Rate: ',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                      Text(
                        '${bond.couponRate.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Cost
                  Row(
                    children: [
                      const Text(
                        'Cost: ',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                      Text(
                        '\$${bond.cost.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Buy button (ready for future server integration)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Buying ${bond.title} for \$${bond.cost}... (coming soon)'),
                            backgroundColor: Colors.amber,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'BUY BOND',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}