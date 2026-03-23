import 'package:flutter/material.dart';
import 'dart:async';
import 'socket_service.dart';

class PersonalBondsScreen extends StatefulWidget {
  const PersonalBondsScreen({super.key});

  @override
  State<PersonalBondsScreen> createState() => _PersonalBondsScreenState();
}

class _PersonalBondsScreenState extends State<PersonalBondsScreen> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    SocketService().requestBondMarket();

    // Live countdown for progress bars
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Listen for buy result
    SocketService().socket?.on('bond-result', _handleBondResult);
  }

  void _handleBondResult(dynamic data) {
    if (data is Map && mounted) {
      final success = data['success'] ?? false;
      final message = data['message'] ?? 'Transaction complete.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    SocketService().socket?.off('bond-result', _handleBondResult);
    super.dispose();
  }

  String _getButtonText(int? cooldownEnd) {
    if (cooldownEnd == null || cooldownEnd <= DateTime.now().millisecondsSinceEpoch) {
      return 'Refresh Bond Market';
    }
    final remaining = (cooldownEnd - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return 'Refresh in $minutes:${seconds.toString().padLeft(2, '0')}';
  }

  bool _isOnCooldown(int? cooldownEnd) {
    return cooldownEnd != null && cooldownEnd > DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Personal Bonds'),
          backgroundColor: Colors.grey[900],
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Bond Offerings'),
              Tab(text: 'Owned Bonds'),
            ],
          ),
        ),
        backgroundColor: Colors.grey[850],
        body: TabBarView(
          children: [
            // ==================== BOND OFFERINGS (original beautiful version) ====================
            ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: SocketService().bondMarketNotifier,
              builder: (context, bonds, child) {
                final cooldownEnd = SocketService().bondMarketCooldownEndNotifier.value;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isOnCooldown(cooldownEnd) ? null : SocketService().refreshBondMarket,
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          label: Text(
                            _getButtonText(cooldownEnd),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isOnCooldown(cooldownEnd) ? Colors.grey : Colors.amber,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: bonds.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
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
                                        Text(
                                          bond['title'], 
                                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(children: [
                                          const Text('Coupon Rate: ', style: TextStyle(fontSize: 16, color: Colors.white70)),
                                          Text('${bond['couponRate'].toStringAsFixed(1)}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amber)),
                                        ]),
                                        const SizedBox(height: 8),
                                        Row(children: [
                                          const Text('Cost: ', style: TextStyle(fontSize: 16, color: Colors.white70)),
                                          Text('\$${bond['cost'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}', 
                                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                                        ]),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () => SocketService().buyBond(bond),
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

            // ==================== OWNED BONDS (with 8-minute progress bar) ====================
            ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: SocketService().statsNotifier,
              builder: (context, stats, child) {
                final ownedBonds = (stats['ownedBonds'] ?? []) as List<dynamic>;

                if (ownedBonds.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 90, color: Colors.white38),
                        SizedBox(height: 20),
                        Text('Owned Bonds', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                        SizedBox(height: 12),
                        Text('You don\'t own any bonds yet.\nBonds you purchase will appear here.', 
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.white60)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: ownedBonds.length,
                  itemBuilder: (context, index) {
                    final bond = ownedBonds[index] as Map<dynamic, dynamic>;
                    final maturityTime = bond['maturityTime'] as int? ?? 0;
                    final now = SocketService().currentServerTime;
                    final remainingMs = (maturityTime - now).clamp(0, 480000);
                    final progress = remainingMs / 480000.0;

                    final minutesLeft = (remainingMs ~/ 60000);
                    final secondsLeft = ((remainingMs % 60000) ~/ 1000).toString().padLeft(2, '0');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.grey[900],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.verified, color: Colors.amber, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(bond['title'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: progress,
                                  color: Colors.amber,
                                  backgroundColor: Colors.grey[700],
                                  minHeight: 10,
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  '$minutesLeft:$secondsLeft',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                            ],
                          ),
                            const SizedBox(height: 12),
                            Row(children: [
                              const Text('Coupon Rate: ', style: TextStyle(fontSize: 16, color: Colors.white70)),
                              Text('${(bond['couponRate'] as num).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amber)),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              const Text('Purchase Price: ', style: TextStyle(fontSize: 16, color: Colors.white70)),
                              Text('\$${(bond['cost'] as num).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}', 
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                            ]),
                            const SizedBox(height: 8),
                            Text('Purchased: ${DateTime.fromMillisecondsSinceEpoch(bond['purchaseTime'] ?? 0).toString().substring(0,16)}',
                                style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}