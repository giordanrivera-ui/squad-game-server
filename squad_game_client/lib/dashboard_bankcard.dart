import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'bonds_screen.dart';
import 'package:google_fonts/google_fonts.dart';

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
          borderRadius: BorderRadius.circular(20),
          image: const DecorationImage(
            image: AssetImage('assets/bank_card_bg.jpg'),
            fit: BoxFit.cover,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 8),
              spreadRadius: 2,
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.black.withOpacity(0.2),
          ),
          padding: const EdgeInsets.all(8),
          child: Stack(
            children: [
              // ==================== NEW: "05/31" TEXT ====================
              Positioned(
                top: 0,
                right: 12,
                child: Text(
                  '05/31',
                  style: GoogleFonts.robotoMono(
                    fontSize: 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.12,
                  ),
                ),
              ),
              // =========================================================

              // Bank balance text (top-right)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12, top: 28), // ← Increased top padding
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

              // Net Worth (bottom-left)
              Positioned(
                bottom: 8,
                left: 8,
                child: Text(
                  'Net Worth: \$${NumberFormat('#,###').format(netWorth)}',
                  style: GoogleFonts.robotoMono(
                    fontSize: 15,
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.1,
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
      ),
    );
  }
}