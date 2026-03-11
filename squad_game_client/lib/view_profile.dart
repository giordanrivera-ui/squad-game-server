import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ViewProfileScreen extends StatefulWidget {
  final String displayName;

  const ViewProfileScreen({super.key, required this.displayName});

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  Map<String, dynamic>? _playerData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPlayerData();
  }

  Future<void> _fetchPlayerData() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('players')
          .where('displayName', isEqualTo: widget.displayName)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        setState(() {
          _playerData = query.docs.first.data();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Player not found.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error fetching profile: $e';
        _isLoading = false;
      });
    }
  }

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

  String _getEquippedImage(String slot, String emptyAsset) {
    final equipped = _playerData?[slot];
    if (equipped == null) return emptyAsset;

    final name = equipped['name'] as String;
    return 'assets/$name.jpg';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text("${widget.displayName}'s Profile")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text("${widget.displayName}'s Profile")),
        body: Center(child: Text(_error!)),
      );
    }

    final photoURL = _playerData?['photoURL'] ?? 'https://via.placeholder.com/150';
    final exp = _playerData?['experience'] ?? 0;
    final balance = _playerData?['balance'] ?? 0;
    final rank = _getRankTitle(exp);
    final wealthTitle = _getWealthTitle(balance);

    // NEW: Respect visibility for armor/weapon (show empty if hidden)
    final showArmor = _playerData?['showArmor'] ?? true;
    final showWeapon = _playerData?['showWeapon'] ?? true;

    final weaponImage = showWeapon && _playerData?['weapon'] != null 
        ? _getEquippedImage('weapon', 'assets/weapon-empty.jpg') 
        : 'assets/weapon-empty.jpg';

    final headwearImage = showArmor && _playerData?['headwear'] != null 
        ? _getEquippedImage('headwear', 'assets/helmet-empty.jpg') 
        : 'assets/helmet-empty.jpg';

    final armorImage = showArmor && _playerData?['armor'] != null 
        ? _getEquippedImage('armor', 'assets/armor-empty.jpg') 
        : 'assets/armor-empty.jpg';

    final footwearImage = showArmor && _playerData?['footwear'] != null 
        ? _getEquippedImage('footwear', 'assets/boots-empty.jpg') 
        : 'assets/boots-empty.jpg';

    return Scaffold(
      appBar: AppBar(title: Text("${widget.displayName}'s Profile")),
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
                  backgroundImage: NetworkImage(photoURL),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        widget.displayName,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        rank,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.orangeAccent),
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
            // Weapon image
            Container(
              width: 300,
              height: 107,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(weaponImage, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            // Armor images
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
          ],
        ),
      ),
    );
  }
}