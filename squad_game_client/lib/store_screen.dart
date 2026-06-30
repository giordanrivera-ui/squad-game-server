import 'package:flutter/material.dart';
import 'armor_page.dart';
import 'vehicles_page.dart';
import 'weapons_page.dart';
import 'courses_page.dart';
import 'game_header.dart';
import 'socket_service.dart';
import 'package:google_fonts/google_fonts.dart';

class StoreScreen extends StatelessWidget {
  final int currentBalance;
  final int currentHealth;
  final String currentTime;
  final String currentLocation;

  // ==================== NEW PARAMETERS ====================
  final String time;
  final VoidCallback onMenuPressed;

  const StoreScreen({
    super.key,
    required this.currentBalance,
    required this.currentHealth,
    required this.currentTime,
    required this.currentLocation,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
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
                time: time,
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CoursesPage()),
          );
        },
      },
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            // ==================== GAME HEADER ====================
            GameHeader(
              statsNotifier: SocketService().statsNotifier,
              time: time,
              onMenuPressed: onMenuPressed,
            ),

            Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
  child: Center(
    child: Text(
      'GENERAL STORE',
      style: GoogleFonts.bebasNeue(
        fontSize: 40,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 2.2,
      ),
    ),
  ),
),

            // ==================== CONTENT ====================
            Expanded(
              child: SafeArea(
                top: false,
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 4 / 3,
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
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(
                                Colors.black.withOpacity(0.45),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}