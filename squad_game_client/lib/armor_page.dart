import 'package:flutter/material.dart';
import 'socket_service.dart';

class Armor {
  final String name;
  final int cost;
  final int defense;
  final String description;
  final int durability;

  Armor({
    required this.name,
    required this.cost,
    required this.defense,
    required this.description,
    this.durability = 100,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'cost': cost,
      'defense': defense,
      'description': description,
      'durability': durability,
    };
  }
}

class ArmorPage extends StatefulWidget {
  final int currentBalance;

  const ArmorPage({super.key, required this.currentBalance});

  @override
  State<ArmorPage> createState() => _ArmorPageState();
}

class _ArmorPageState extends State<ArmorPage> {
  final Map<String, bool> _checked = {};
  final Map<String, int> _quantities = {};
  int _totalCost = 0;

  final List<Armor> _footWear = [
    Armor(
      name: 'Generic Aramid Boots',
      cost: 120,
      defense: 2,
      description: 'Basic protective footwear made from aramid fibers, offering moderate abrasion resistance and flame retardancy for entry-level tactical use. They provide essential foot protection against cuts, scrapes, and minor impacts but lack advanced durability for prolonged heavy-duty operations.'
    ),
    Armor(
      name: 'Kevlar Assault boots',
      cost: 240,
      defense: 4,
      description: 'Mid-range combat boots reinforced with Kevlar for improved puncture resistance and strength, suitable for mine-infested areas or assault operations. They offer better protection than basic aramids, with flame resistance and enhanced durability for military personnel.'
    ),
    Armor(
      name: 'Garmont T8 Bifida',
      cost: 500,
      defense: 8,
      description: 'Reliable multi-terrain tactical boots with a suede leather and nylon upper for breathability, comfort, and stability. Designed for heavy loads and demanding field conditions, they feature EVA midsoles for cushioning and Vibram outsoles for superior grip on varied surfaces.'
    ),
    Armor(
      name: 'Salomon Quest 4D',
      cost: 1200,
      defense: 10,
      description: 'Premium all-terrain military boots with advanced 4D chassis for stability, GORE-TEX waterproofing, and Contagrip outsoles for exceptional grip. Ideal for rugged environments, they provide superior comfort, flexibility, and protection in wet or amphibious conditions, reducing fatigue during extended missions.'
    ),
  ];

  final List<Armor> _bodyArmor = [
    Armor(
      name: 'Flak Jacket',
      cost: 120,
      defense: 2,
      description: 'Entry-level protective vest designed primarily to shield against shrapnel and fragments from explosions, using layered nylon or ballistic nylon. It offers limited ballistic resistance and is not intended for direct bullet impacts, making it suitable for basic fragmentation defense.'
    ),
    Armor(
      name: 'Generic Aramid Armor',
      cost: 300,
      defense: 4,
      description: 'Fundamental heat-resistant body armor made from aramid fibers, providing moderate strength and protection against cuts, abrasions, and flames. It serves as a lightweight alternative to heavier materials but offers limited ballistic resistance compared to specialized variants.'
    ),
    Armor(
      name: 'Full Kevlar Armor',
      cost: 750,
      defense: 6,
      description: 'Sturdy ballistic-resistant vest using multiple layers of Kevlar fabric, offering high tensile strength (up to five times that of steel by weight) and protection against bullets and fragments. It absorbs impact energy effectively but may require additional plates for higher threats.'
    ),
    Armor(
      name: 'SAPI Armor',
      cost: 2200,
      defense: 8,
      description: 'Ceramic composite plates inserted into vests for enhanced small arms protection, capable of stopping up to 7.62mm rounds. They provide multi-hit capability when backed by soft armor, focusing on vital organ defense with a balance of weight and durability.'
    ),
    Armor(
      name: 'ESAPI Armor',
      cost: 5000,
      defense: 12,
      description: 'Upgraded ceramic plates offering superior defense against armor-piercing rounds (e.g., .30-06 AP), meeting NIJ Level IV standards. Lighter than traditional materials, they provide multi-hit resistance for high-threat environments, ideal for military operations.'
    ),
    Armor(
      name: 'XSAPI Armor',
      cost: 12000,
      defense: 15,
      description: 'Experimental advanced plates with added layers like Spectra for superior tungsten-core AP protection, capable of withstanding multiple high-velocity hits. Designed for extreme threats, they incorporate silicon-enhanced boron carbide for maximum strength and reduced weight.'
    ),
    Armor(
      name: 'Hybrid Plate RF-3 Armor',
      cost: 0, // Assuming 0 as not specified
      defense: 20,
      description: 'Cutting-edge composite plates combining silicon carbide, polyethylene, and advanced ceramics for RF3/Level IV protection against extreme ballistic threats. Lightweight with full edge-to-edge coverage, they offer unmatched multi-hit resistance and environmental durability.'
    ),
  ];

  final List<Armor> _headWear = [
    Armor(
      name: 'Ballistic goggles',
      cost: 150,
      defense: 4,
      description: 'Basic protective eyewear designed to shield against fragments, shrapnel, and small projectiles. They meet military standards for impact resistance and integrate with helmets for essential eye safety in combat environments.'
    ),
    Armor(
      name: 'Tactical Helmet',
      cost: 400,
      defense: 8,
      description: 'Mid-level headgear providing ballistic protection against fragments and low-velocity impacts, with features like anti-fog lenses and modular accessories. It offers full coverage for improved defense in military and law enforcement operations.'
    ),
    Armor(
      name: 'Ops-Core RF1 Helmet',
      cost: 1000,
      defense: 12,
      description: 'Advanced high-cut ballistic helmet with hybrid composite shell for protection against 7.62mm rifle rounds and fragments. Lightweight (around 3.5 lbs) with EPP liner for comfort, it\'s designed for extreme conditions and accessory integration.'
    ),
  ];

  void _updateTotal() {
    int total = 0;
    void addIfChecked(List<Armor> items) {
      for (var item in items) {
        final key = item.name;
        if (_checked[key] == true) {
          total += (_quantities[key] ?? 0) * item.cost;
        }
      }
    }
    addIfChecked(_footWear);
    addIfChecked(_bodyArmor);
    addIfChecked(_headWear);
    setState(() => _totalCost = total);
  }

  void _purchaseItems() {
    List<Map<String, dynamic>> purchased = [];
    void addPurchased(List<Armor> items) {
      for (var item in items) {
        final key = item.name;
        final qty = _quantities[key] ?? 0;
        if (_checked[key] == true && qty > 0) {
          for (int i = 0; i < qty; i++) {
            purchased.add(item.toMap());
          }
        }
      }
    }
    addPurchased(_footWear);
    addPurchased(_bodyArmor);
    addPurchased(_headWear);

    // Emit to server
    SocketService().socket?.emit('purchase-armor', {
      'items': purchased,
      'totalCost': _totalCost,
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Items purchased!')));
  }

  Widget _buildSection(String title, List<Armor> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        ...items.map((item) {
          final key = item.name;
          final checked = _checked[key] ?? false;
          final quantity = _quantities[key] ?? 1;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: checked,
                    onChanged: (v) {
                      setState(() {
                        _checked[key] = v!;
                        if (!v) _quantities[key] = 0;
                        else _quantities[key] = 1;
                      });
                      _updateTotal();
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Cost: ${item.cost}'),
                        const SizedBox(height: 4),
                        Text(item.description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  if (checked)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: quantity > 1
                              ? () {
                                  setState(() => _quantities[key] = quantity - 1);
                                  _updateTotal();
                                }
                              : null,
                        ),
                        Text('$quantity'),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setState(() => _quantities[key] = quantity + 1);
                            _updateTotal();
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPurchase = _totalCost > 0 && widget.currentBalance >= _totalCost;

    return Scaffold(
      appBar: AppBar(title: const Text('Armor')),
      body: ListView(
        padding: const EdgeInsets.all(16).copyWith(bottom: 80), // Add padding to avoid overlap with bottom bar
        children: [
          _buildSection('Foot wear', _footWear),
          _buildSection('Body Armor', _bodyArmor),
          _buildSection('Head wear', _headWear),
        ],
      ),
      bottomSheet: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total Cost: $_totalCost', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: canPurchase ? _purchaseItems : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canPurchase ? Colors.green : Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Purchase items', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}