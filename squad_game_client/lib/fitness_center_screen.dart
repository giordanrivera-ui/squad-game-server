import 'package:flutter/material.dart';
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
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.2),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: SocketService().statsNotifier,
              builder: (context, stats, child) {
                final int currentStrength = stats['strength'] ?? 0;
                final int currentStealth = stats['stealth'] ?? 0;

                return Row(
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

                          const SizedBox(height: 12),
                          Image.asset('assets/strength.png', width: 110, height: 110),
                          const SizedBox(height: 8),

                          // ==================== STRENGTH LEVEL (Dynamic) ====================
                          Text(
                            'Strength Level: $currentStrength',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Calisthenics Button
                          _buildTrainingButton(
                            context,
                            label: 'Calisthenics',
                            onTap: () => _performTraining('calisthenics'),
                          ),
                          const SizedBox(height: 16),

                          // Olympic Weightlifting Button
                          _buildTrainingButton(
                            context,
                            label: 'Olympic Weightlifting',
                            onTap: () => _performTraining('olympic_weightlifting'),
                          ),
                        ],
                      ),
                    ),

                    // ==================== VERTICAL DIVIDER ====================
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: VerticalDivider(
                        color: Colors.white24,
                        thickness: 1.5,
                        width: 24,
                      ),
                    ),

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
                                'Stealth\n Training',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                          Image.asset('assets/stealth.png', width: 110, height: 110),
                          const SizedBox(height: 8),

                          // ==================== STEALTH LEVEL (Dynamic) ====================
                          Text(
                            'Stealth Level: $currentStealth',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Parkour Training Button
                          _buildTrainingButton(
                            context,
                            label: 'Parkour Training',
                            onTap: () => _performTraining('parkour'),
                          ),
                          const SizedBox(height: 16),

                          // Gymnastics Button
                          _buildTrainingButton(
                            context,
                            label: 'Gymnastics',
                            onTap: () => _performTraining('gymnastics'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrainingButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            image: DecorationImage(
              image: AssetImage(_getTrainingImage(label)),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black.withOpacity(0.45),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
        ),
      ),
    );
  }

  String _getTrainingImage(String label) {
    switch (label) {
      case 'Calisthenics':
        return 'assets/Calisthenics.jpg';
      case 'Olympic Weightlifting':
        return 'assets/Olympic Weightlifting.jpg';
      case 'Parkour Training':
        return 'assets/Parkour Training.jpg';
      case 'Gymnastics':
        return 'assets/Gymnastics.jpg';
      default:
        return 'assets/background.jpg';
    }
  }

  void _performTraining(String type) {
    SocketService().socket?.emit('perform-training', {'type': type});

    SocketService().socket?.once('training-result', (data) {
      if (data is Map && mounted) {
        final success = data['success'] ?? false;
        final message = data['message'] ?? 'Training completed!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green[700] : Colors.red[700],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }
}