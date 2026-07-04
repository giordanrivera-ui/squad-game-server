import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class GameHeader extends StatefulWidget {
  final String? title;
  final ValueNotifier<Map<String, dynamic>> statsNotifier;
  final String time;
  final VoidCallback onMenuPressed;

  const GameHeader({
    super.key,
    this.title,
    required this.statsNotifier,
    required this.time,
    required this.onMenuPressed,
  });

  @override
  State<GameHeader> createState() => _GameHeaderState();
}

class _GameHeaderState extends State<GameHeader> {
  bool _showSpecial = false;
  Timer? _cycleTimer;
  Timer? _liveUpdateTimer; // NEW: 1-second timer for live countdown

  bool _hasStamina = false;
  String _staminaTimeRemaining = '';

  bool _hasHealing = false;
  String _healingTimeRemaining = '';

  @override
  void initState() {
    super.initState();
    widget.statsNotifier.addListener(_updateStatuses);
    _updateStatuses();
  }

  void _updateStatuses() {
    final stats = widget.statsNotifier.value;

    // Enhanced Stamina
    final staminaEndTime = stats['enhancedStaminaEndTime'] as int?;
    _hasStamina = staminaEndTime != null && staminaEndTime > SocketService().currentServerTime;
    if (_hasStamina && staminaEndTime != null) {
      _updateStaminaTime(staminaEndTime);
    }

    // Healing
    final healingEndTime = stats['healingEndTime'] as int?;
    _hasHealing = healingEndTime != null && healingEndTime > SocketService().currentServerTime;
    if (_hasHealing && healingEndTime != null) {
      _updateHealingTime(healingEndTime);
    }

    final shouldHaveSpecial = _hasStamina || _hasHealing;

    if (shouldHaveSpecial) {
      if (_cycleTimer == null || !_cycleTimer!.isActive) {
        _startCycling();
      }
      if (_liveUpdateTimer == null || !_liveUpdateTimer!.isActive) {
        _startLiveUpdateTimer(); // NEW
      }
    } else {
      _cycleTimer?.cancel();
      _liveUpdateTimer?.cancel();
      if (mounted) setState(() => _showSpecial = false);
    }
  }

  void _updateStaminaTime(int endTime) {
    final remainingMs = endTime - SocketService().currentServerTime;
    if (remainingMs <= 0) {
      if (mounted) setState(() => _staminaTimeRemaining = '');
      return;
    }
    final totalSeconds = (remainingMs / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (mounted) {
      setState(() => _staminaTimeRemaining = '$minutes:${seconds.toString().padLeft(2, '0')}');
    }
  }

  void _updateHealingTime(int endTime) {
    final remainingMs = endTime - SocketService().currentServerTime;
    if (remainingMs <= 0) {
      if (mounted) setState(() => _healingTimeRemaining = '');
      return;
    }
    final totalSeconds = (remainingMs / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (mounted) {
      setState(() => _healingTimeRemaining = '$minutes:${seconds.toString().padLeft(2, '0')}');
    }
  }

  void _startCycling() {
    _cycleTimer?.cancel();
    _cycleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _showSpecial = !_showSpecial);
    });
  }

  // NEW: Live 1-second countdown while special status is visible
  void _startLiveUpdateTimer() {
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      final stats = widget.statsNotifier.value;

      if (_hasStamina) {
        final staminaEnd = stats['enhancedStaminaEndTime'] as int?;
        if (staminaEnd != null) _updateStaminaTime(staminaEnd);
      }
      if (_hasHealing) {
        final healingEnd = stats['healingEndTime'] as int?;
        if (healingEnd != null) _updateHealingTime(healingEnd);
      }
    });
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _liveUpdateTimer?.cancel();
    widget.statsNotifier.removeListener(_updateStatuses);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: widget.statsNotifier,
      builder: (context, stats, child) {
        final balance = stats['balance'] ?? 0;
        final health = stats['health'] ?? 100;
        final maxHealth = stats['maxHealth'] ?? 100;
        final bullets = stats['bullets'] ?? 0;

        final bool shouldShowSpecial = (_hasStamina || _hasHealing) && _showSpecial;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 25, 10, 8),
          decoration: BoxDecoration(
            image: const DecorationImage(
              image: AssetImage('assets/top-section-bg.jpg'),
              fit: BoxFit.cover,
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(25),
              bottomRight: Radius.circular(25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.68),
                blurRadius: 14,
                offset: const Offset(0, 12),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(25),
                    bottomRight: Radius.circular(25),
                  ),
                ),
              ),
              Row(
                children: [
                  _buildMenuButton(),
                  const SizedBox(width: 12),

                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      child: shouldShowSpecial
                          ? Align(
                              key: const ValueKey('special'),
                              alignment: Alignment.centerRight,
                              child: _buildSpecialStatusGroup(),
                            )
                          : Align(
                              key: const ValueKey('stats'),
                              alignment: Alignment.centerRight,
                              child: _buildStatsRow(balance, health, maxHealth, bullets),
                            ),
                    ),
                  ),

                  const SizedBox(width: 16),
                  Text(widget.time, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpecialStatusGroup() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasHealing) ...[
          _buildHealingDisplay(),
          if (_hasStamina) const SizedBox(width: 14),
        ],
        if (_hasStamina) _buildStaminaDisplay(),
      ],
    );
  }

  Widget _buildHealingDisplay() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.local_hospital, color: Colors.green, size: 20),
        const SizedBox(width: 6),
        Text(_healingTimeRemaining, style: const TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStaminaDisplay() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bolt, color: Colors.amber, size: 20),
        const SizedBox(width: 6),
        Text(_staminaTimeRemaining, style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatsRow(int balance, int health, int maxHealth, int bullets) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet, size: 18, color: Colors.green),
          const SizedBox(width: 4),
          Text('\$${NumberFormat('#,###').format(balance)}', style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(width: 16),
        Row(children: [
          _HealthIcon(health: health, maxHealth: maxHealth),
          const SizedBox(width: 4),
          Text('$health', style: const TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 0.5, fontWeight: FontWeight.w700)),
          Text('/$maxHealth', style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 0.5)),
        ]),
        const SizedBox(width: 16),
        Row(children: [
          const Icon(Icons.adjust, size: 18, color: Colors.orange),
          const SizedBox(width: 4),
          Text('$bullets', style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      ],
    );
  }

  Widget _buildMenuButton() {
    return Builder(
      builder: (context) => Stack(
        children: [
          IconButton(icon: const Icon(Icons.menu, color: Colors.white), onPressed: widget.onMenuPressed),
          ValueListenableBuilder<bool>(
            valueListenable: SocketService().hasUnreadMessages,
            builder: (context, hasUnread, child) {
              if (!hasUnread) return const SizedBox.shrink();
              return Positioned(
                right: 0, top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                  constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// _HealthIcon remains exactly the same as before
class _HealthIcon extends StatefulWidget {
  final int health;
  final int maxHealth;
  const _HealthIcon({required this.health, this.maxHealth = 100});

  @override
  State<_HealthIcon> createState() => _HealthIconState();
}

class _HealthIconState extends State<_HealthIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  bool get _isLowHealth => widget.health < ((widget.maxHealth > 0 ? widget.maxHealth : 100) * 0.3);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _HealthIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isLowHealth && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!_isLowHealth && _controller.isAnimating) {
      _controller.stop(); _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLowHealth) return const Icon(Icons.favorite, size: 20, color: Colors.red);
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.6), blurRadius: 12, spreadRadius: 2)]),
        child: const Icon(Icons.favorite, size: 20, color: Colors.red),
      ),
    );
  }
}