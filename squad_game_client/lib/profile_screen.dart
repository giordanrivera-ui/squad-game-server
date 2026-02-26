import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'socket_service.dart';
import 'inventory_page.dart'; // NEW: Import for Inventory

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

        // Add a short delay to handle potential propagation issues in Firebase Storage
        await Future.delayed(const Duration(seconds: 2));

        final downloadUrl = await snapshot.ref.getDownloadURL();

        await user.updatePhotoURL(downloadUrl);
        await user.reload();

        await FirebaseFirestore.instance.collection('players').doc(user.email).update({'photoURL': downloadUrl});

        SocketService().updatePhotoURL(downloadUrl);

        setState(() {
          _photoURL = downloadUrl;
        });

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

  @override
  Widget build(BuildContext context) {
    final footwearEquipped = widget.stats['footwear'] ?? null;
    final footwearImage = footwearEquipped != null 
        ? 'assets/${footwearEquipped['name']}.jpg' 
        : 'assets/boots-empty.jpg';

    return Container(
      color: Colors.grey[800], // Dark grey background
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _uploadPhoto,
              child: CircleAvatar(
                radius: 60,
                backgroundImage: NetworkImage(_photoURL ?? 'https://via.placeholder.com/150'),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showInventoryMenu('headwear'),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset('assets/helmet-empty.jpg', width: 100, height: 100),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showInventoryMenu('armor'),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset('assets/armor-empty.jpg', width: 100, height: 100),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showInventoryMenu('footwear'),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(footwearImage, width: 100, height: 100),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Name: ${FirebaseAuth.instance.currentUser?.displayName ?? "Player"}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFEEEEEE)),
            ),
            const SizedBox(height: 20),
            Text('Experience: ${widget.stats['experience'] ?? 0}', style: const TextStyle(color: Color(0xFFEEEEEE))),
            Text('Intelligence: ${widget.stats['intelligence'] ?? 0}', style: const TextStyle(color: Color(0xFFEEEEEE))),
            Text('Skill: ${widget.stats['skill'] ?? 0}', style: const TextStyle(color: Color(0xFFEEEEEE))),
            Text('Marksmanship: ${widget.stats['marksmanship'] ?? 0}', style: const TextStyle(color: Color(0xFFEEEEEE))),
            Text('Stealth: ${widget.stats['stealth'] ?? 0}', style: const TextStyle(color: Color(0xFFEEEEEE))),
            Text('Defense: ${widget.stats['defense'] ?? 0}', style: const TextStyle(color: Color(0xFFEEEEEE))),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InventoryPage(inventory: widget.stats['inventory'] ?? []),
                  ),
                );
              },
              child: const Text('View Inventory'),
            ),
          ],
        ),
      ),
    );
  }
}