import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'game_header.dart';
import 'package:google_fonts/google_fonts.dart';

class FitnessCenterScreen extends StatefulWidget {
  final String time;
  final VoidCallback onMenuPressed;

  const FitnessCenterScreen({
    super.key,
    required this.time,
    required this.onMenuPressed,
  });

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
      child: Column(
        children: [
          // ==================== GAME HEADER (touches the top) ====================
          GameHeader(
            statsNotifier: SocketService().statsNotifier,
            time: widget.time,
            onMenuPressed: widget.onMenuPressed,
          ),

          // ==================== CONTENT AREA ====================
          Expanded(
            child: SafeArea(
              top: false,                    // ← Important: Don't add extra top padding
              child: Container(
                color: Colors.black.withOpacity(0.2),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ValueListenableBuilder<Map<String, dynamic>>(
                    valueListenable: SocketService().statsNotifier,
                    builder: (context, stats, child) {
                      final int currentStrength = stats['strength'] ?? 0;
                      final int currentStealth = stats['stealth'] ?? 0;
                      final String? selectedMartialArt = stats['martialArt'];

                      return Column(
                        children: [
                          // ==================== STRENGTH + STEALTH SECTION ====================
                          Expanded(
                            child: Row(
                              children: [
                                // LEFT SIDE
                                Expanded(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        alignment: Alignment.center,
                                        child: Center(
                                          child: RichText(
                                            textAlign: TextAlign.center,
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: 'Strength\n',
                                                  style: GoogleFonts.bebasNeue(
                                                    fontSize: 36,
                                                    fontWeight: FontWeight.bold,
                                                    color: const Color.fromARGB(220, 255, 255, 255),
                                                    letterSpacing: 0.7,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'TRAINING',
                                                  style: GoogleFonts.robotoCondensed(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w100,
                                                    color: const Color.fromARGB(220, 143, 143, 143),
                                                    height: 0.85,    
                                                    letterSpacing: 2.2,                // ← Controls vertical spacing
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Image.asset(_getStrengthImage(currentStrength), width: 110, height: 110),
                                      const SizedBox(height: 8),
                                      Text('Strength Level: $currentStrength',
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color.fromARGB(195, 255, 255, 255))),
                                      const SizedBox(height: 12),
                                      _buildTrainingButton(context, label: 'Calisthenics', onTap: () => _performTraining('calisthenics')),
                                      const SizedBox(height: 16),
                                      _buildTrainingButton(context, label: 'Olympic Weightlifting', onTap: () => _performTraining('olympic_weightlifting')),
                                    ],
                                  ),
                                ),

                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 30),
                                  child: VerticalDivider(color: Colors.white24, thickness: 1.5, width: 24),
                                ),

                                // RIGHT SIDE
                                Expanded(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        alignment: Alignment.center,
                                        child: Center(
                                          child: RichText(
                                            textAlign: TextAlign.center,
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: 'Stealth\n',
                                                  style: GoogleFonts.bebasNeue(
                                                    fontSize: 36,
                                                    fontWeight: FontWeight.bold,
                                                    color: const Color.fromARGB(220, 255, 255, 255),
                                                    letterSpacing: 1.2
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'TRAINING',
                                                  style: GoogleFonts.robotoCondensed(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w100,
                                                    color: const Color.fromARGB(220, 143, 143, 143),
                                                    height: 0.85,    
                                                    letterSpacing: 1.8,                // ← Controls vertical spacing
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Image.asset('assets/stealth.png', width: 110, height: 110),
                                      const SizedBox(height: 8),
                                      Text('Stealth Level: $currentStealth',
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color.fromARGB(195, 255, 255, 255))),
                                      const SizedBox(height: 12),
                                      _buildTrainingButton(context, label: 'Parkour Training', onTap: () => _performTraining('parkour')),
                                      const SizedBox(height: 16),
                                      _buildTrainingButton(context, label: 'Gymnastics', onTap: () => _performTraining('gymnastics')),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ==================== MARTIAL ARTS SECTION ====================
                          _buildMartialArtsSection(selectedMartialArt),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  // ==================== Martial Arts Section ====================
  Widget _buildMartialArtsSection(String? selectedMartialArt) {
    String backgroundImage = 'assets/martial-arts_blank.jpg';

    if (selectedMartialArt != null) {
      if (selectedMartialArt == 'Brazilian Jiu Jitsu') {
        backgroundImage = 'assets/martial-arts_brazilian jiu jitsu.jpg';
      } else if (selectedMartialArt == 'Judo') {
        backgroundImage = 'assets/martial-arts_judo.jpg';
      } else if (selectedMartialArt == 'Muay Thai') {
        backgroundImage = 'assets/martial-arts_muay thai.jpg';
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: DecorationImage(
          image: AssetImage(backgroundImage),
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
          borderRadius: BorderRadius.circular(16),
          color: Colors.black.withOpacity(0.55),
        ),
        padding: const EdgeInsets.all(16),
        child: selectedMartialArt == null
            ? _buildMartialArtSelection()
            : _buildSelectedMartialArt(selectedMartialArt),
      ),
    );
  }

  Widget _buildMartialArtSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Martial Arts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 8),
        const Text('Select a martial art to begin training.', style: TextStyle(fontSize: 14, color: Colors.white70)),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            children: [
              _buildMartialArtOption('Muay Thai', 'assets/button_muay thai.jpg'),
              const SizedBox(width: 12),
              _buildMartialArtOption('Judo', 'assets/button_judo.jpg'),
              const SizedBox(width: 12),
              _buildMartialArtOption('Brazilian Jiu Jitsu', 'assets/button_brazilian jiu jitsu.jpg'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedMartialArt(String martialArt) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            martialArt,
            style: GoogleFonts.bebasNeue(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: const Color.fromARGB(190, 255, 255, 255),
              letterSpacing: 1.5
            ),
          ),
          const Text(
            'Martial art selected',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Martial Arts Option Widget ====================
  Widget _buildMartialArtOption(String name, String imagePath) {
    return Expanded(
      child: InkWell(
        onTap: () {
          SocketService().socket?.emit('select-martial-art', {'martialArt': name});
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(image: AssetImage(imagePath), fit: BoxFit.cover),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4)),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.black.withOpacity(0.45),
            ),
            child: Center(
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black87)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Helper Methods ====================
  String _getStrengthImage(int strength) {
    if (strength >= 48) return 'assets/strength_48.png';
    if (strength >= 37) return 'assets/strength_37.png';
    if (strength >= 29) return 'assets/strength_29.png';
    if (strength >= 21) return 'assets/strength_21.png';
    if (strength >= 13) return 'assets/strength_13.png';
    if (strength >= 6) return 'assets/strength_6.png';
    return 'assets/strength_0.png';
  }

  Widget _buildTrainingButton(BuildContext context, {required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            image: DecorationImage(image: AssetImage(_getTrainingImage(label)), fit: BoxFit.cover),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 10, offset: const Offset(0, 6), spreadRadius: 1)],
          ),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.black.withOpacity(0.45)),
            child: Center(
              child: Text(
                label,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: const Color.fromARGB(255, 192, 190, 190).withOpacity(0.7)),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getTrainingImage(String label) {
    switch (label) {
      case 'Calisthenics': return 'assets/Calisthenics.jpg';
      case 'Olympic Weightlifting': return 'assets/Olympic Weightlifting.jpg';
      case 'Parkour Training': return 'assets/Parkour Training.jpg';
      case 'Gymnastics': return 'assets/Gymnastics.jpg';
      default: return 'assets/background.jpg';
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