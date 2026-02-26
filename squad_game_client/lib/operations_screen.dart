import 'package:flutter/material.dart';
import 'socket_service.dart';

class OperationsScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final int lastLowLevelOp;

  const OperationsScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.lastLowLevelOp,
  });

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  String? _selectedOperation;

  final List<Map<String, dynamic>> _operationGroups = [
    {
      'header': 'Low Level',
      'operations': [
        "Mug a passerby",
        "Loot a grocery store",
        "Rob a bank",
        "Loot weapons store",
      ]
    },
    {
      'header': 'Medium Level',
      'operations': [
        "Attack military barracks",
        "Storm a laboratory",
        "Attack central issue facility",
      ]
    },
    {
      'header': 'High Level',
      'operations': [
        "Strike an armory",
        "Raid a vehicle depot",
        "Assault an aircraft hangar",
        "Invade country",
      ]
    },
  ];

  bool get _isLowLevelCooldown {
    return DateTime.now().millisecondsSinceEpoch - widget.lastLowLevelOp < 60000;
  }

  void _executeOperation() {
    if (_selectedOperation == null) return;

    SocketService().executeOperation(_selectedOperation!);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Executing: $_selectedOperation...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: Colors.orange[50],
          child: Column(
            children: [
              const Text('Operations in', style: TextStyle(fontSize: 18)),
              Text(widget.currentLocation,
                   style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<String>(
                  hint: const Text('Select an operation'),
                  value: _selectedOperation,
                  onChanged: (value) {
                    setState(() => _selectedOperation = value);
                  },
                  items: _buildDropdownItems(),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton(
                      onPressed: _selectedOperation != null ? _executeOperation : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedOperation != null ? Colors.orange : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      child: const Text(
                        'Execute Operation',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<DropdownMenuItem<String>> _buildDropdownItems() {
    List<DropdownMenuItem<String>> items = [];
    for (var group in _operationGroups) {
      items.add(
        DropdownMenuItem<String>(
          value: null,
          enabled: false,
          child: Text(
            group['header'] as String,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
      );
      final isLowLevel = group['header'] == 'Low Level';
      for (var op in group['operations'] as List<String>) {
        items.add(
          DropdownMenuItem<String>(
            value: isLowLevel && _isLowLevelCooldown ? null : op,
            enabled: !(isLowLevel && _isLowLevelCooldown),
            child: Text(
              op,
              style: TextStyle(
                color: isLowLevel && _isLowLevelCooldown ? Colors.grey : Colors.black,
              ),
            ),
          ),
        );
      }
      items.add(
        const DropdownMenuItem<String>(
          value: null,
          enabled: false,
          child: Divider(),
        ),
      );
    }
    return items;
  }
}