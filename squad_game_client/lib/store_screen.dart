import 'package:flutter/material.dart';
import 'armor_page.dart';
import 'vehicles_page.dart'; // NEW: Import VehiclesPage
import 'weapons_page.dart'; // NEW: Import WeaponsPage

class StoreScreen extends StatelessWidget {
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final String currentLocation;

  const StoreScreen({
    super.key,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.currentLocation,
  });

  @override
  Widget build(BuildContext context) {
    final categories = [
      {'title': 'Weapons', 'onTap': () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WeaponsPage(
              currentBalance: currentBalance,
              currentHealth: currentHealth,
              currentTime: currentTime,
              currentLocation: currentLocation,
            ),
          ),
        );
      }},
      {'title': 'Armor', 'onTap': () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArmorPage(
              currentBalance: currentBalance,
              currentHealth: currentHealth,
              currentTime: currentTime,
              currentLocation: currentLocation,
            ),
          ),
        );
      }},
      {'title': 'Vehicles, aircrafts and artillery', 'onTap': () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VehiclesPage(
              currentBalance: currentBalance,
              currentHealth: currentHealth,
              currentTime: currentTime,
              currentLocation: currentLocation,
            ),
          ),
        );
      }},
      {'title': 'Courses', 'onTap': () { /* TODO */ }},
    ];

    return Scaffold(
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 3 / 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: categories[index]['onTap'] as VoidCallback,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blueGrey,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  categories[index]['title'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}