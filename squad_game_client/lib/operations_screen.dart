import 'package:flutter/material.dart';
import 'socket_service.dart';

class OperationsScreen extends StatefulWidget {
  final String currentLocation;
  final int currentBalance;
  final int currentHealth;
  final String currentTime;

  const OperationsScreen({
    super.key,
    required this.currentLocation,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
  });

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  String? _selectedOperation;

  final List<String> _operations = [
    "Mug a passerby",
    "Loot a grocery store",
    "Rob a bank",
    "Loot weapons store",
    "Attack military barracks",
    "Storm a laboratory",
    "Strike an armory",
    "Raid a vehicle depot",
    "Assault an aircraft hangar",
    "Invade country",
  ];

  void _executeOperation() {
    if (_selectedOperation == null) return;

    if (_selectedOperation == "Rob a bank") {
      SocketService().robBank();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Executing: Rob a bank...')),
      );
    }
    // Other operations do nothing for now
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
              Text(widget.currentLocation, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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
                  items: _operations.map((op) {
                    return DropdownMenuItem<String>(
                      value: op,
                      child: Text(op),
                    );
                  }).toList(),
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
}