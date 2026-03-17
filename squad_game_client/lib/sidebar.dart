import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'socket_service.dart';


class Sidebar extends StatelessWidget {
  final int currentScreen;
  final Function(int) onScreenChanged;
  final Map<String, dynamic> stats;
  final ValueNotifier<bool> hasUnreadMessages;

  const Sidebar({
    super.key,
    required this.currentScreen,
    required this.onScreenChanged,
    required this.stats,
    required this.hasUnreadMessages,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(_getRankBannerPath(stats['experience'] ?? 0)),
                fit: BoxFit.cover,
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    onScreenChanged(6); // Profile
                    Navigator.pop(context);
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage(
                      FirebaseAuth.instance.currentUser?.photoURL ?? 'https://via.placeholder.com/150',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      FirebaseAuth.instance.currentUser?.displayName ?? "Player",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _getRankTitle(stats['experience'] ?? 0),
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      stats['location'] ?? "Unknown",
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // NEW: Reordered tiles as specified
          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Dashboard'),
              selected: currentScreen == 0,
              onTap: () {
                onScreenChanged(0);
                Navigator.pop(context);
              },
            ),
          ),

          ValueListenableBuilder<bool>(
            valueListenable: hasUnreadMessages,
            builder: (context, hasUnread, child) {
              return SizedBox(
                height: 48,
                child: ListTile(
                  leading: Stack(
                    children: [
                      const Icon(Icons.mail),
                      if (hasUnread)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                          ),
                        ),
                    ],
                  ),
                  title: const Text('Messages'),
                  selected: currentScreen == 2,
                  onTap: () {
                    onScreenChanged(2);
                    Navigator.pop(context);
                  },
                ),
              );
            },
          ),

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Players Online'),
              selected: currentScreen == 1,
              onTap: () {
                onScreenChanged(1);
                Navigator.pop(context);
              },
            ),
          ),

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.emoji_events),
              title: const Text('Hall of Fame'),
              selected: currentScreen == 11,
              onTap: () {
                onScreenChanged(11);
                Navigator.pop(context);
              },
            ),
          ),

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.person_remove),
              title: const Text('Kill a Player'),
              selected: currentScreen == 10,
              onTap: () {
                onScreenChanged(10);
                Navigator.pop(context);
              },
            ),
          ),

          const Divider(thickness: 1),  // NEW: Thin divider after "Kill a Player"

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text('Operations'),
              selected: currentScreen == 5,
              onTap: () {
                onScreenChanged(5);
                Navigator.pop(context);
              },
            ),
          ),

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.gavel),
              title: const Text('Prison'),
              selected: currentScreen == 9,
              onTap: () {
                SocketService().requestPrisonList();
                onScreenChanged(9);
                Navigator.pop(context);
              },
            ),
          ),

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.local_hospital),
              title: const Text('Hospital'),
              selected: currentScreen == 4,
              onTap: () {
                onScreenChanged(4);
                Navigator.pop(context);
              },
            ),
          ),

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.store),
              title: const Text('Store'),
              selected: currentScreen == 7,
              onTap: () {
                onScreenChanged(7);
                Navigator.pop(context);
              },
            ),
          ),

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.apartment),
              title: const Text('Properties'),
              selected: currentScreen == 8,
              onTap: () {
                onScreenChanged(8);
                Navigator.pop(context);
              },
            ),
          ),

          SizedBox(
            height: 48,
            child: ListTile(
              leading: const Icon(Icons.airplanemode_active),
              title: const Text('Airport'),
              selected: currentScreen == 3,
              onTap: () {
                onScreenChanged(3);
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getRankTitle(int exp) {
    if (exp <= 49) return 'Beggar';
    if (exp <= 514) return 'Thug';
    if (exp <= 1264) return 'Recruit';
    if (exp <= 2314) return 'Private';
    if (exp <= 3514) return 'Private First Class';
    if (exp <= 5014) return 'Corporal';
    if (exp <= 6864) return 'Sergeant';
    if (exp <= 8864) return 'Sergeant First Class';
    if (exp <= 10214) return 'Warrant Officer';
    if (exp <= 11464) return 'First Lieutenant';
    if (exp <= 14214) return 'Captain';
    if (exp <= 17414) return 'Major';
    if (exp <= 21364) return 'Lieutenant Colonel';
    if (exp <= 25864) return 'Colonel';
    if (exp <= 31514) return 'General';
    if (exp <= 38214) return 'General of the Army';
    return 'Supreme Commander';
  }

  String _getRankBannerPath(int exp) {
    String rank = _getRankTitle(exp).toLowerCase().replaceAll(' ', '-');
    switch (rank) {
      case 'beggar':
        return 'assets/Beggar-banner.jpg';
      case 'thug':
        return 'assets/Thug-banner.jpg';
      case 'recruit':
        return 'assets/Recruit-banner.jpg';
      case 'private':
        return 'assets/Private-banner.jpg';
      case 'private-first-class':
        return 'assets/Private First Class-banner.jpg';
      case 'corporal':
        return 'assets/Corporal-banner.jpg';
      case 'sergeant':
        return 'assets/Sergeant-banner.jpg';
      case 'sergeant-first-class':
        return 'assets/Sergeant First Class-banner.jpg';
      default:
        return 'assets/Thug-banner.jpg';
    }
  }
}