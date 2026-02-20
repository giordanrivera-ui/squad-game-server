import 'package:flutter/material.dart';
import 'socket_service.dart';  // NEW: Import to access the singleton

class StatusAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Map<String, dynamic> stats;
  final String time;
  final VoidCallback onMenuPressed;

  const StatusAppBar({
    super.key,
    required this.title,
    required this.stats,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    final balance = stats['balance'] ?? 0;
    final health = stats['health'] ?? 100;

    return AppBar(
      leading: Builder(
        builder: (context) => Stack(  // UPDATED: Wrap in Stack for red dot
          children: [
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: onMenuPressed,
            ),
            ValueListenableBuilder<bool>(
              valueListenable: SocketService().hasUnreadMessages,  // UPDATED: Listen to notifier
              builder: (context, hasUnread, child) {
                if (!hasUnread) return const SizedBox.shrink();
                return Positioned(
                  right: 11,
                  top: 11,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      title: Text(title),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet, size: 20, color: Colors.green),
              const SizedBox(width: 4),
              Text('\$$balance', style: const TextStyle(fontSize: 15)),

              const SizedBox(width: 16),

              const Icon(Icons.favorite, size: 20, color: Colors.red),
              const SizedBox(width: 4),
              Text('$health', style: const TextStyle(fontSize: 15)),

              const SizedBox(width: 16),

              Text(time, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}