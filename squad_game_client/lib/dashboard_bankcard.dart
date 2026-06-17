import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'bonds_screen.dart';

class DashboardBankCard extends StatelessWidget {
  final int balance;
  final int netWorth;

  const DashboardBankCard({
    super.key,
    required this.balance,
    required this.netWorth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 140),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // Bank balance text (centered)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 16),
                  child: Text(
                    '\$${NumberFormat('#,###').format(balance)}',
                    style: const TextStyle(
                      fontSize: 28,
                      color: Colors.green,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.12,
                    ),
                  ),
                ),
              ],
            ),

            Positioned(
              bottom: 8,
              left: 4,
              child: Text(
                'Net Worth: \$${NumberFormat('#,###').format(netWorth)}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),

            // BONDS button (bottom-right)
            Positioned(
              bottom: 6,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PersonalBondsScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pie_chart, color: Colors.amber, size: 18),
                      SizedBox(width: 4),
                      Text(
                        'BONDS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}