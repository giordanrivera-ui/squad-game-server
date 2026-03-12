// view_profile.dart (Complete new file)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ViewProfileScreen extends StatefulWidget {
  final String displayName;
  final bool isDead;  // True if viewing a dead profile

  const ViewProfileScreen({
    super.key,
    required this.displayName,
    this.isDead = false,
  });

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      DocumentSnapshot doc;
      if (widget.isDead) {
        // Load from deadProfiles for dead characters
        doc = await FirebaseFirestore.instance
            .collection('deadProfiles')
            .doc(widget.displayName.toLowerCase())
            .get();
      } else {
        // Load from players for alive characters (find by displayName)
        final query = await FirebaseFirestore.instance
            .collection('players')
            .where('displayName', isEqualTo: widget.displayName)
            .limit(1)
            .get();
        if (query.docs.isEmpty) {
          // No profile found - show error
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile not found.')),
          );
          return;
        }
        doc = query.docs.first;
      }

      if (doc.exists) {
        setState(() => _profileData = doc.data() as Map<String, dynamic>?);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile not found.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
    }
  }

  // Helper: Get rank title based on experience (copied from profile_screen.dart)
  String _getRankTitle(int exp) {
    if (exp <= 499) return 'Thug';
    if (exp <= 1249) return 'Recruit';
    if (exp <= 2299) return 'Private';
    if (exp <= 3499) return 'Private First Class';
    if (exp <= 4999) return 'Corporal';
    if (exp <= 6849) return 'Sergeant';
    if (exp <= 8849) return 'Sergeant First Class';
    if (exp <= 10199) return 'Warrant Officer';
    if (exp <= 11449) return 'First Lieutenant';
    if (exp <= 14199) return 'Captain';
    if (exp <= 17399) return 'Major';
    if (exp <= 21349) return 'Lieutenant Colonel';
    if (exp <= 25849) return 'Colonel';
    if (exp <= 31499) return 'General';
    if (exp <= 38199) return 'General of the Army';
    return 'Supreme Commander';
  }

  // Helper: Get wealth title based on balance (copied from profile_screen.dart)
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

  // Helper: Get image for equipped slot (copied/adapted from profile_screen.dart)
  String _getEquippedImage(String slot, String emptyAsset) {
    final equipped = _profileData?[slot];
    if (equipped == null) return emptyAsset;

    final name = equipped['name'] as String;
    return 'assets/$name.jpg';
  }

  @override
  Widget build(BuildContext context) {
    if (_profileData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final exp = _profileData!['experience'] ?? 0;
    final balance = _profileData!['balance'] ?? 0;
    final rank = _getRankTitle(exp);
    final wealth = _getWealthTitle(balance);

    final headwearImage = _getEquippedImage('headwear', 'assets/helmet-empty.jpg');
    final armorImage = _getEquippedImage('armor', 'assets/armor-empty.jpg');
    final footwearImage = _getEquippedImage('footwear', 'assets/boots-empty.jpg');
    final weaponImage = _getEquippedImage('weapon', 'assets/weapon-empty.jpg');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_profileData!['displayName']}${widget.isDead ? ' (Deceased)' : ''}',
        ),
      ),
      backgroundColor: Colors.grey[800],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile Picture + Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundImage: NetworkImage(_profileData!['photoURL'] ?? 'https://via.placeholder.com/150'),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        _profileData!['displayName'],
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        rank,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.orangeAccent),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        wealth,
                        style: const TextStyle(fontSize: 18, color: Colors.white70),
                      ),
                      if (widget.isDead) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Deceased',
                          style: TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Weapon
            Container(
              width: 300,
              height: 107,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  weaponImage,
                  fit: BoxFit.cover,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Armor Items
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(headwearImage, width: 100, height: 100, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(armorImage, width: 100, height: 100, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(footwearImage, width: 100, height: 100, fit: BoxFit.cover),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Other Stats
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('Overall Power: ${_profileData!['overallPower'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  // Add more if needed (e.g., intelligence, but they're unused)
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}