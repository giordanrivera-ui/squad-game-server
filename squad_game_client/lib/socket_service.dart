import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;
  final ValueNotifier<bool> isConnected = ValueNotifier(false);

  final ValueNotifier<Map<String, dynamic>> statsNotifier = ValueNotifier({});

  // The permanent mailbox
  final ValueNotifier<List<Map<String, dynamic>>> inboxNotifier = ValueNotifier([]);

  // Track unread messages
  final ValueNotifier<bool> hasUnreadMessages = ValueNotifier(false);

  // Global live prison list (used by PrisonScreen)
  final ValueNotifier<List<Map<String, dynamic>>> imprisonedPlayersNotifier = ValueNotifier([]);

  // NEW: Rescue celebration trigger (for the nice animation)
  final ValueNotifier<Map<String, String>?> rescueNotifier = ValueNotifier(null);

    // NEW: Rank-up celebration trigger
  final ValueNotifier<Map<String, String>?> rankUpNotifier = ValueNotifier(null);

    // NEW: Notifier for income claimed (for optional snackbar/UI feedback)
  final ValueNotifier<int?> incomeClaimedNotifier = ValueNotifier(null);
  
  final ValueNotifier<bool> deathNotifier = ValueNotifier(false);

  final ValueNotifier<Map<String, dynamic>?> hitClaimedNotifier = ValueNotifier(null);

  final ValueNotifier<Map<String, dynamic>?> hitExpiredNotifier = ValueNotifier(null);

    final ValueNotifier<List<Map<String, dynamic>>> _bondMarketNotifier = ValueNotifier([]);
  List<Map<String, dynamic>> get bondMarket => _bondMarketNotifier.value;

  // Public getter so other files can listen to it
  ValueNotifier<List<Map<String, dynamic>>> get bondMarketNotifier => _bondMarketNotifier;

  final ValueNotifier<int?> bondMarketCooldownEndNotifier = ValueNotifier(null);

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

  String? _currentEmail;

  List<String> normalLocations = [];
  Map<String, int> travelCosts = {};
  List<Map<String, dynamic>> properties = [];

  int serverTimeOffset = 0;
  int get currentServerTime => DateTime.now().millisecondsSinceEpoch + serverTimeOffset;

  void connect(String email, String displayName) {
    if (socket != null && socket!.connected) return;

      _currentEmail = email;

      socket = IO.io(
        GameConstants.serverUrl,
        IO.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionAttempts(5)  // NEW: Try 5 times before giving up
          .setReconnectionDelay(1000)  // NEW: Start with 1 sec delay between tries
          .setReconnectionDelayMax(5000)  // NEW: Max 5 sec delay
          .setTimeout(20000)  // NEW: Ping timeout 20 sec (adjust if needed)
          .build(),
      );

      socket?.onConnect((_) {
        isConnected.value = true;
        print('✅ Connected to server!');
        socket?.emit(SocketEvents.register, {
          'email': email,
          'displayName': displayName,
        });
      });

      socket?.on(SocketEvents.init, (data) {
        if (data is Map) {
          normalLocations = List<String>.from(data['locations'] ?? []);
          travelCosts = Map<String, int>.from(data['travelCosts'] ?? {});
          properties = List<Map<String, dynamic>>.from(data['properties'] ?? []);
          statsNotifier.value = Map.from(data['player'] ?? {});
          deathNotifier.value = (data['player']?['dead'] == true);
          // NEW: Force death screen on every login/reconnect
          final bool isDeadNow = (data['player']?['dead'] == true) || (data['player']?['health'] ?? 100) <= 0;
          if (isDeadNow) {
            deathNotifier.value = true;
          }
          statsNotifier.value['bullets'] = statsNotifier.value['bullets'] ?? 0;
          statsNotifier.value['lastMidLevelOp'] = statsNotifier.value['lastMidLevelOp'] ?? 0;
          statsNotifier.value['overallPower'] = statsNotifier.value['overallPower'] ?? 0;
          statsNotifier.value['weapon'] = statsNotifier.value['weapon'] ?? null;

          loadMessages();
          loadTransactions();  // ← Loads saved history on every login
          if ((statsNotifier.value['health'] ?? 100) <= 0) deathNotifier.value = true;

          print('Got locations from server: $normalLocations');
        }
      });
      
      // NEW: Handle update-stats (update the notifier)
      socket?.on(SocketEvents.updateStats, (data) {
        if (data is Map<String, dynamic>) {
          final cleaned = <String, dynamic>{...data};

          const numericFields = [
            'balance', 'health', 'bullets', 'experience', 'overallPower',
            'kills', 'intelligence', 'skill', 'marksmanship', 'stealth', 'defense',
            'lastLowLevelOp', 'lastMidLevelOp', 'lastHighLevelOp',
            'prisonEndTime', 'sellBanEndTime', 'bonePenaltyEndTimeLow',
            'bonePenaltyEndTimeMid', 'bonePenaltyEndTimeHigh'
          ];

          for (var field in numericFields) {
            if (cleaned.containsKey(field) && cleaned[field] is num) {
              cleaned[field] = (cleaned[field] as num).toInt();   // ← This is the key fix
            }
          }

          // Capture old values BEFORE update
          final oldExp = statsNotifier.value['experience'] ?? 0;
          final oldRank = _getRankTitle(oldExp);  // Use helper below

          // Update notifier with clean integers
          statsNotifier.value = {...statsNotifier.value, ...cleaned};

          // Update notifier
          statsNotifier.value = {...statsNotifier.value, ...data};

          // NEW: Force death screen on every update
            final bool isDeadNow = (statsNotifier.value['dead'] == true) || (statsNotifier.value['health'] ?? 100) <= 0;
            if (isDeadNow) {
              deathNotifier.value = true;
            }

          // Set defaults (like old code)
          statsNotifier.value['bullets'] = statsNotifier.value['bullets'] ?? 0;
          statsNotifier.value['lastMidLevelOp'] = statsNotifier.value['lastMidLevelOp'] ?? 0;
          statsNotifier.value['overallPower'] = statsNotifier.value['overallPower'] ?? 0;
          statsNotifier.value['weapon'] = statsNotifier.value['weapon'] ?? null;
          statsNotifier.value['kills'] = statsNotifier.value['kills'] ?? 0;

          // Detect rank up
          final newExp = statsNotifier.value['experience'] ?? oldExp;
          final newRank = _getRankTitle(newExp);
          if (newRank != oldRank && newExp > oldExp) {
            rankUpNotifier.value = {
              'oldRank': oldRank,
              'newRank': newRank,
            };
          }

          // Check death
          if ((statsNotifier.value['health'] ?? 100) <= 0) {
            deathNotifier.value = true;
          }
        }
      });

      // Private message received
      socket?.on(SocketEvents.privateMessage, (data) {
        if (data is Map<String, dynamic>) {
          final normalized = Map<String, dynamic>.from(data);
          if (!normalized.containsKey('isFromMe')) normalized['isFromMe'] = false;
          if (!normalized.containsKey('id')) {
            normalized['id'] = DateTime.now().millisecondsSinceEpoch.toString();
          }

          // NEW: Check if already have this message (no duplicates)
          if (inboxNotifier.value.any((m) => m['data']?['id'] == normalized['id'])) return;

          final newItem = <String, dynamic>{
            'type': 'private',
            'data': normalized,
            'timestamp': DateTime.now().toIso8601String(),
            'isRead': false,
          };

          inboxNotifier.value = [newItem, ...inboxNotifier.value];
          _saveMessagesToFirestore();
          _updateUnreadStatus();
        }
      });

      // Announcement from mods
      socket?.on(SocketEvents.announcement, (data) {
        if (data is Map && data['text'] is String && data['text'].isNotEmpty && data['id'] is String) {
          // NEW: Check if already have this announcement
          if (inboxNotifier.value.any((m) => m['id'] == data['id'])) return;

          final newItem = <String, dynamic>{
            'type': 'announcement',
            'text': data['text'],
            'id': data['id'],
            'timestamp': DateTime.now().toIso8601String(),
            'isRead': false,
          };

          inboxNotifier.value = [newItem, ...inboxNotifier.value];
          _saveMessagesToFirestore();
          _updateUnreadStatus();
        }
      });

      // Bond market listener (now includes cooldown)
      socket?.on('bond-market-update', (data) {
        if (data is Map) {
          if (data['bonds'] is List) {
            _bondMarketNotifier.value = List<Map<String, dynamic>>.from(data['bonds']);
          }
          if (data['cooldownEndTime'] is num) {
            bondMarketCooldownEndNotifier.value = (data['cooldownEndTime'] as num).toInt();
          }
        }
      });

      // Prison list updates with server time sync (fixes clock drift)
      socket?.on('prison-list-update', (payload) {
        if (payload is Map<String, dynamic>) {
          final list = payload['list'] as List<dynamic>? ?? [];
          final serverTime = payload['serverTime'] as int? ?? DateTime.now().millisecondsSinceEpoch;

          final localNow = DateTime.now().millisecondsSinceEpoch;
          serverTimeOffset = serverTime - localNow;

          imprisonedPlayersNotifier.value = List<Map<String, dynamic>>.from(
            list.map((e) => Map<String, dynamic>.from(e as Map))
          );
        }
      });

      // NEW: Rescue celebration animation trigger
      socket?.on('player-rescued', (data) {
        if (data is Map<String, dynamic>) {
          rescueNotifier.value = {
            'rescuer': data['rescuer']?.toString() ?? 'Someone',
            'message': data['message']?.toString() ?? 'You have been rescued!'
          };
        }
      });

      socket?.on('income-claimed', (data) {
        if (data is Map && data['amount'] is int) {
          incomeClaimedNotifier.value = data['amount'];  // Trigger snackbar in main.dart
        }
      });

      

      socket?.on('player-died', (_) {
        deathNotifier.value = true;  // Trigger death UI
      });

      // NEW: Hitlist updates (screen will refresh automatically via StreamBuilder)
      socket?.on('hitlist-update', (data) {});

      // NEW: Hit claimed notification
      socket?.on('hit-claimed', (data) {
        if (data is Map<String, dynamic>) {
          hitClaimedNotifier.value = {
            'target': data['target'] ?? '',
            'reward': data['reward'] ?? 0
          };
        }
      });

      socket?.on('hit-expired', (data) {
        if (data is Map<String, dynamic>) {
          hitExpiredNotifier.value = {
            'target': data['target'] ?? '',
            'reward': data['reward'] ?? 0
          };
        }
      });

      socket?.onReconnect((_) {
        print('🔄 Reconnected to server!');
        // Re-register on reconnect to ensure online list updates
        socket?.emit(SocketEvents.register, {
          'email': email,
          'displayName': displayName,
        });
      });

      socket?.onDisconnect((_) {
        isConnected.value = false;
        print('❌ Disconnected from server');
      });
    }

  // Load old messages from your cloud box
  Future<void> loadMessages() async {
    if (_currentEmail == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(_currentEmail)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['messages'] != null) {
          final loaded = (data['messages'] as List<dynamic>)
              .map((m) => Map<String, dynamic>.from(m as Map<dynamic, dynamic>))
              .toList();

          loaded.sort((a, b) =>
              (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));

          inboxNotifier.value = loaded;
        }
      }

      // NEW: Load big announcements from special box
      final annSnap = await FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('timestamp', descending: true)
          .get();

      for (var annDoc in annSnap.docs) {
        var item = annDoc.data();
        final id = item['id'] ?? annDoc.id; // Use doc id if no id
        item['id'] = id;
        item['type'] = 'announcement';
        item['isRead'] = false; // New ones are unread

        if (!inboxNotifier.value.any((m) => m['id'] == id)) {
          inboxNotifier.value.add(item);
        }
      }

      // Sort all messages by time
      inboxNotifier.value.sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));
      _updateUnreadStatus();
    } catch (e) {
      print('Error loading messages: $e');
      inboxNotifier.value = [];
      _updateUnreadStatus();
    }
  }

  // Update unread status
  void _updateUnreadStatus() {
    hasUnreadMessages.value = inboxNotifier.value.any((msg) => !(msg['isRead'] ?? true));
  }

  // Mark messages as read
  void markAsRead({String? partner, bool announcements = false}) {
    bool changed = false;
    inboxNotifier.value = inboxNotifier.value.map((item) {
      if (announcements && item['type'] == 'announcement' && !(item['isRead'] ?? true)) {
        item['isRead'] = true;
        changed = true;
      } else if (partner != null && item['type'] == 'private') {
        final data = item['data'] as Map<String, dynamic>;
        final bool isFromMe = data['isFromMe'] ?? false;
        final String msgPartner = isFromMe ? (data['to'] ?? '') : (data['from'] ?? '');
        if (msgPartner == partner && !(item['isRead'] ?? true)) {
          item['isRead'] = true;
          changed = true;
        }
      }
      return item;
    }).toList();

    if (changed) {
      _saveMessagesToFirestore();
      _updateUnreadStatus();
    }
  }

  // Delete message
  Future<void> deleteMessage(String id) async {
    inboxNotifier.value = inboxNotifier.value
        .where((item) {
          if (item['type'] == 'announcement') {
            return item['id'] != id;
          } else {
            return (item['data'] as Map<String, dynamic>)['id'] != id;
          }
        })
        .toList();
    await _saveMessagesToFirestore();
    _updateUnreadStatus();
  }

  // Delete conversation
  Future<void> deleteConversation(String partner) async {
    inboxNotifier.value = inboxNotifier.value
        .where((item) {
          if (item['type'] != 'private') return true;
          final data = item['data'] as Map<String, dynamic>;
          final bool isFromMe = data['isFromMe'] ?? false;
          final String msgPartner = isFromMe ? (data['to'] ?? '') : (data['from'] ?? '');
          return msgPartner != partner;
        })
        .toList();
    await _saveMessagesToFirestore();
    _updateUnreadStatus();
  }

  Future<void> _saveMessagesToFirestore() async {
    if (_currentEmail == null) return;
    try {
      final fullList = inboxNotifier.value
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      await FirebaseFirestore.instance
          .collection('players')
          .doc(_currentEmail)
          .set({'messages': fullList}, SetOptions(merge: true));
    } catch (e) {
      print('Error saving messages: $e');
    }
  }

  void robBank() => socket?.emit(SocketEvents.robBank);
  void sendMessage(String msg) {
    if (msg.isNotEmpty) socket?.emit(SocketEvents.message, msg);
  }
  void travel(String destination) => socket?.emit(SocketEvents.travel, destination);

  void sendPrivateMessage(String to, String msg) {
    if (to.isNotEmpty && msg.isNotEmpty) {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      socket?.emit(SocketEvents.privateMessage, {
        'to': to,
        'msg': msg,
        'id': id
      });
    }
  }

  void sendAnnouncement(String text) {
    if (text.isNotEmpty) {
      socket?.emit(SocketEvents.announcement, text);
    }
  }

  void heal() => socket?.emit('heal');

  void healBrokenBone() => socket?.emit('heal-broken-bone');

  void updatePhotoURL(String url) => socket?.emit('update-profile', {'photoURL': url});

  void purchaseArmor(List<Map<String, dynamic>> items, int totalCost) {
    socket?.emit('purchase-armor', {
      'items': items,
      'totalCost': totalCost,
    });
  }

  void equipArmor(String slot, Map<String, dynamic> item) {
    socket?.emit('equip-armor', {
      'slot': slot,
      'item': item,
    });
  }

  void unequipArmor(String slot) {
    socket?.emit('unequip-armor', {
      'slot': slot,
    });
  }

  void sellItems(List<Map<String, dynamic>> items, int totalSellValue, int rate) {
    socket?.emit('sell-items', {
      'items': items,
      'totalSellValue': totalSellValue,
      'rate': rate,  // NEW: 60, 80, or 100
    });
  }

  void executeOperation(String operation) {
    socket?.emit('execute-operation', {
      'operation': operation,
    });
  }

  void assignToFleet(Map<String, dynamic> vehicle) {
    socket?.emit('assign-to-fleet', vehicle);
  }

  void removeFromFleet(List<Map<String, dynamic>> vehicles) {
    if (vehicles.isEmpty) return;
    
    // Wrap it — this forces Socket.io to transmit a clean array every time
    socket?.emit('remove-from-fleet', { 'vehicles': vehicles });
  }

  void scoutDrivers(int count) {
    if (count > 0 && socket != null) {
      socket!.emit('scout-drivers', count);
    }
  }

  void clearScoutedDrivers() {
    socket?.emit('clear-scouted-drivers');
  }

  // ==================== HIRE DRIVERS ====================
  void hireDrivers(List<dynamic> driversToHire) {
    if (driversToHire.isNotEmpty && socket != null) {
      socket!.emit('hire-drivers', driversToHire);
    }
  }

  // Add near the other hire/remove methods
  void hireDriversWrapped(List<dynamic> driversToHire) {
    if (driversToHire.isNotEmpty && socket != null) {
      // Wrap it exactly like remove-from-fleet
      socket!.emit('hire-drivers', { 'drivers': driversToHire });
    }
  }

  void assignDriverToVehicle(Map<String, dynamic> driver, Map<String, dynamic> vehicle) {
    socket?.emit('assign-driver-to-vehicle', {
      'driverName': driver['name'],
      'vehicle': {
        'name': vehicle['name'],
        'power': vehicle['power'],
        'health': vehicle['health'] ?? 100,
      },
    });
  }

  void unassignDriverFromVehicle(String driverName) {
    socket?.emit('unassign-driver-from-vehicle', {
      'driverName': driverName,
    });
  }

  void attemptRescue(String targetDisplayName) {
    socket?.emit('attempt-rescue', targetDisplayName);
  }

  void requestPrisonList() {
    socket?.emit('request-prison-list');
  }

  void updateVisibility(bool showArmor, bool showWeapon) {
    socket?.emit('update-visibility', {
      'showArmor': showArmor,
      'showWeapon': showWeapon,
    });
  }

  void buyProperty(String name) => socket?.emit('buy-property', name);

  void buyUpgrade(String propertyName, String upgradeName) {
    socket?.emit('buy-upgrade', {
      'propertyName': propertyName,
      'upgradeName': upgradeName,
    });
  }

  void allocateAttribute(String attribute) {
    if (!['intelligence', 'skill', 'marksmanship'].contains(attribute)) return;
    socket?.emit('allocate-attribute', { 'attribute': attribute });
  }
  
  void claimIncome() => socket?.emit('claim-income');

  void requestBondMarket() {
    socket?.emit('request-bond-market');
  }

  void refreshBondMarket() {
    socket?.emit('refresh-bond-market');
  }

  void buyBond(Map<String, dynamic> bond) {
    socket?.emit('buy-bond', bond);
  }

  void respawn() => socket?.emit('respawn');

    // Test buttons
  void addTestExp() => socket?.emit('add-test-exp', 70);
  void addTestMoney(int amount) => socket?.emit('add-test-money', amount);

  // Add this method in SocketService class (e.g., below addTestMoney)
  void addTestBullets(int amount) => socket?.emit('add-test-bullets', amount);
  
  void disconnect() {
    socket?.disconnect();
    isConnected.value = false;
  }

  // ← ADD THIS NEW METHOD HERE
  void placeHit(String target, int reward, int durationDays) {
    if (target.isNotEmpty && reward >= 1000) {
      socket?.emit('place-hit', {
        'target': target,
        'reward': reward,
        'durationDays': durationDays
      });
    }
  }

    // ==================== FULL TRANSACTION PERSISTENCE (survives restarts + works across devices) ====================
  final ValueNotifier<List<Map<String, dynamic>>> transactionHistoryNotifier = ValueNotifier([]);

  Future<void> loadTransactions() async {
    if (_currentEmail == null) {
      print('DEBUG: loadTransactions skipped — no email');
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('players')
          .doc(_currentEmail)
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .limit(25)
          .get();

      final loaded = snap.docs.map((doc) {
        final data = doc.data();
        return {
          'description': data['description'] ?? 'Unknown',
          'amount': (data['amount'] as num?)?.toInt() ?? 0,
          'balanceAfter': (data['balanceAfter'] as num?)?.toInt() ?? 0,
        };
      }).toList();

      transactionHistoryNotifier.value = loaded;

      print('DEBUG: Loaded ${loaded.length} transactions for $_currentEmail');
    } catch (e) {
      print('ERROR loading transactions: $e');
      // Optional: show a snackbar once
      // You can add a notifier for this if you want UI feedback
    }
  }

  Future<void> saveTransaction(Map<String, dynamic> tx) async {
    if (_currentEmail == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(_currentEmail)
          .collection('transactions')
          .add({
        'description': tx['description'],
        'amount': tx['amount'],
        'balanceAfter': tx['balanceAfter'],
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving transaction: $e');
    }
  }
}