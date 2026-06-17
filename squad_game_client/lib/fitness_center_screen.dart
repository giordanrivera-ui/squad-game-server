import 'package:flutter/material.dart';
import 'status_app_bar.dart';
import 'socket_service.dart';

class FitnessCenterScreen extends StatefulWidget {
  const FitnessCenterScreen({super.key});

  @override
  State<FitnessCenterScreen> createState() => _FitnessCenterScreenState();
}

class _FitnessCenterScreenState extends State<FitnessCenterScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StatusAppBar(
        title: 'Fitness Center',
        statsNotifier: SocketService().statsNotifier,
        time: 'Live',
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // ==================== LEFT SIDE: STRENGTH TRAINING ====================
            Expanded(
              child: Column(
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.red[700],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Strength Training',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Calisthenics Button
                  _buildTrainingButton(
                    context,
                    label: 'Calisthenics',
                    icon: Icons.accessibility_new,
                    color: Colors.redAccent,
                    onTap: () => _performTraining('calisthenics'),
                  ),
                  const SizedBox(height: 16),

                  // Olympic Weightlifting Button
                  _buildTrainingButton(
                    context,
                    label: 'Olympic Weightlifting',
                    icon: Icons.fitness_center,
                    color: Colors.deepOrange,
                    onTap: () => _performTraining('olympic_weightlifting'),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // ==================== RIGHT SIDE: STEALTH TRAINING ====================
            Expanded(
              child: Column(
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.teal[700],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Stealth Training',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Parkour Training Button
                  _buildTrainingButton(
                    context,
                    label: 'Parkour Training',
                    icon: Icons.directions_run,
                    color: Colors.tealAccent,
                    onTap: () => _performTraining('parkour'),
                  ),
                  const SizedBox(height: 16),

                  // Gymnastics Button
                  _buildTrainingButton(
                    context,
                    label: 'Gymnastics',
                    icon: Icons.sports_gymnastics,
                    color: Colors.cyan,
                    onTap: () => _performTraining('gymnastics'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainingButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 6,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _performTraining(String type) {
    SocketService().socket?.emit('perform-training', {'type': type});

    // Listen for confirmation from server
    SocketService().socket?.once('training-result', (data) {
      if (data is Map && mounted) {
        final message = data['message'] ?? 'Training completed!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }
}