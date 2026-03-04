import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'socket_service.dart';
import 'inventory_page.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> stats;

  const ProfileScreen({super.key, required this.stats});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _photoURL;

  @override
  void initState() {
    super.initState();
    _photoURL = FirebaseAuth.instance.currentUser?.photoURL;
  }

    // ==================== RANK PROGRESS HELPER ====================
  Map<String, dynamic> _getRankProgress(int currentExp) {
    const rankList = [
      {'exp': 0, 'title': 'Thug'},
      {'exp': 500, 'title': 'Recruit'},
      {'exp': 1250, 'title': 'Private'},
      {'exp': 2300, 'title': 'Private First Class'},
      {'exp': 3500, 'title': 'Corporal'},
      {'exp': 5000, 'title': 'Sergeant'},
      {'exp': 6850, 'title': 'Sergeant First Class'},
      {'exp': 8850, 'title': 'Warrant Officer'},
      {'exp': 10200, 'title': 'First Lieutenant'},
      {'exp': 11450, 'title': 'Captain'},
      {'exp': 14200, 'title': 'Major'},
      {'exp': 17400, 'title': 'Lieutenant Colonel'},
      {'exp': 21350, 'title': 'Colonel'},
      {'exp': 25850, 'title': 'General'},
      {'exp': 31500, 'title': 'General of the Army'},
      {'exp': 38200, 'title': 'Supreme Commander'},
    ];

    for (int i = 0; i < rankList.length - 1; i++) {
      final currentRankExp = rankList[i]['exp'] as int;
      final nextRankExp = rankList[i + 1]['exp'] as int;

      if (currentExp < nextRankExp) {
        final progress = (currentExp - currentRankExp) / (nextRankExp - currentRankExp);

        return {
          'currentRank': rankList[i]['title'],
          'nextRank': rankList[i + 1]['title'],
          'currentExp': currentExp,
          'nextExp': nextRankExp,
          'progress': progress.clamp(0.0, 1.0),
        };
      }
    }

    // Max rank reached
    return {
      'currentRank': 'Supreme Commander',
      'nextRank': 'Max Rank',
      'currentExp': currentExp,
      'nextExp': currentExp,
      'progress': 1.0,
    };
  }

  Future<void> _uploadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final storageRef = FirebaseStorage.instance.ref().child('profile_pics/${user.uid}.jpg');

      try {
        final uploadTask = storageRef.putFile(file);
        final snapshot = await uploadTask.whenComplete(() {});

        await Future.delayed(const Duration(seconds: 2));

        final downloadUrl = await snapshot.ref.getDownloadURL();

        await user.updatePhotoURL(downloadUrl);
        await user.reload();

        await FirebaseFirestore.instance.collection('players').doc(user.email).update({'photoURL': downloadUrl});

        SocketService().updatePhotoURL(downloadUrl);

        setState(() => _photoURL = downloadUrl);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading photo: $e')));
      }
    }
  }

  void _showInventoryMenu(String type) {
    final inventory = widget.stats['inventory'] ?? [];
    final filtered = inventory.where((item) => (item['type'] as String?) == type).toList();

    final currentEquipped = widget.stats[type] ?? null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$type Items'),
        content: filtered.isEmpty
            ? const Text('No items of this type.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return ListTile(
                      title: Text(item['name'] as String),
                      subtitle: Text('Durability: ${item['durability']}'),
                      onTap: () {
                        SocketService().equipArmor(type, item);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
        actions: [
          if (currentEquipped != null)
            TextButton(
              onPressed: () {
                SocketService().unequipArmor(type);
                Navigator.pop(ctx);
              },
              child: const Text('Unequip Current'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getEquippedImage(String slot, String emptyAsset) {
    final equipped = widget.stats[slot];
    if (equipped == null) return emptyAsset;

    final name = equipped['name'] as String;
    return 'assets/$name.jpg';
  }

  String _getWealthTitle(int balance) {
    if (balance <= 800) return 'Destitute';
    if (balance <= 1600) return 'Skint';
    if (balance <= 4500) return 'Poor';
    if (balance <= 12000) return 'Modest';
    if (balance <= 25000) return 'Middle Class';
    if (balance <= 50000) return 'Upper Class';
    if (balance <= 120000) return 'Affluent';
    if (balance <= 250000) return 'Wealthy';
    if (balance <= 500000) return 'Rich';
    if (balance <= 999999) return 'Elite';
    if (balance <= 1999999) return 'Millionaire';
    if (balance <= 999999999) return 'Multi-Millionaire';
    if (balance <= 1999999999) return 'Billionaire';
    if (balance <= 10000000000) return 'Multi-Billionaire';
    return 'Lord';
  }

  @override
  Widget build(BuildContext context) {
    final headwearImage = _getEquippedImage('headwear', 'assets/helmet-empty.jpg');
    final armorImage = _getEquippedImage('armor', 'assets/armor-empty.jpg');
    final footwearImage = _getEquippedImage('footwear', 'assets/boots-empty.jpg');

    final balance = widget.stats['balance'] ?? 0;
    final exp = widget.stats['experience'] ?? 0;
    final wealthTitle = _getWealthTitle(balance);

    final rankProgress = _getRankProgress(exp);

    return Scaffold(
      backgroundColor: Colors.grey[800],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile Picture + Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _uploadPhoto,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundImage: NetworkImage(_photoURL ?? 'https://via.placeholder.com/150'),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        FirebaseAuth.instance.currentUser?.displayName ?? "Player",
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        rankProgress['currentRank'],
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.orangeAccent),
                      ),
                      const SizedBox(height: 4),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: rankProgress['progress'],
                              minHeight: 16,                    // Slightly taller for nice text fit
                              backgroundColor: Colors.grey[700],
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ),
                          // Text overlaid directly on the bar
                          Text(
                            '${rankProgress['currentExp']} / ${rankProgress['nextExp']} → ${rankProgress['nextRank']}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  offset: Offset(1, 1),
                                  blurRadius: 3,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        wealthTitle,
                        style: const TextStyle(fontSize: 18, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Equipped Gear (unchanged)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showInventoryMenu('headwear'),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(headwearImage, width: 100, height: 100, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _showInventoryMenu('armor'),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(armorImage, width: 100, height: 100, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _showInventoryMenu('footwear'),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(footwearImage, width: 100, height: 100, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Rest of stats (optional: you can keep or remove raw Experience number)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('Intelligence: ${widget.stats['intelligence'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  Text('Skill: ${widget.stats['skill'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  Text('Marksmanship: ${widget.stats['marksmanship'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  Text('Stealth: ${widget.stats['stealth'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  Text('Defense: ${widget.stats['defense'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                ],
              ),
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InventoryPage(inventory: widget.stats['inventory'] ?? []),
                  ),
                );
              },
              child: const Text('View Full Inventory'),
            ),
          ],
        ),
      ),
    );
  }
}