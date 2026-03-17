import 'package:flutter/material.dart';
import 'armor_page.dart';
import 'vehicles_page.dart';
import 'weapons_page.dart';

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
    // Map each category to its image and screen
    final categories = [
      {
        'title': 'Weapons',
        'image': 'assets/store_weapons.jpg',
        'onTap': () {
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
        },
      },
      {
        'title': 'Armor',
        'image': 'assets/store_armor.jpg',
        'onTap': () {
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
        },
      },
      {
        'title': 'Vehicles, aircrafts and artillery',
        'image': 'assets/store_vehicles.jpg',
        'onTap': () {
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
        },
      },
      {
        'title': 'Courses',
        'image': 'assets/store_courses.jpg',
        'onTap': () {
          // TODO: implement Courses page later
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Courses coming soon!')),
          );
        },
      },
    ];

    return Scaffold(
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 4 / 3,          // ← Changed: taller rectangles (was 3/2)
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];

          return GestureDetector(
            onTap: category['onTap'] as VoidCallback,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: AssetImage(category['image'] as String),
                  fit: BoxFit.cover,           // Fill the whole card
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.45), // ← Dark overlay for text readability
                    BlendMode.darken,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    category['title'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black,
                          offset: Offset(1, 1),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}