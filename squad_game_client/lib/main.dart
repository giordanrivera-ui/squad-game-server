import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'socket_service.dart';
import 'constants.dart';
import 'dart:async';
import 'online_players_screen.dart';
import 'airport_screen.dart';
import 'messages_screen.dart';
import 'auth_screen.dart';
import 'status_app_bar.dart';
import 'hospital_screen.dart'; 
import 'operations_screen.dart';
import 'profile_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'store_screen.dart';
import 'properties_screen.dart';
import 'sidebar.dart';
import 'prison_screen.dart';
import 'rescue_celebration_overlay.dart';
import 'rank_up_celebration_overlay.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'kill_player_screen.dart';
import 'hall_of_fame_screen.dart';
import 'bonds_screen.dart';

// FIXED: Global plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// NEW: Background helper - runs when app is sleeping and gets a note
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Got a background note: ${message.messageId}'); // For testing
}



void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIXED: Initialize Firebase only if not already done (no options for mobile)
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();  // No options - uses google-services.json on Android
  }

    // NEW: Activate App Check with the updated syntax
  await FirebaseAppCheck.instance.activate(
    providerAndroid: const AndroidDebugProvider(),  // For testing/debug
    // providerWeb: ReCaptchaV3Provider('YOUR_RECAPTCHA_SITE_KEY'),  // If you have web support, add your key here
    // providerApple: AppleDebugProvider(),  // If you have iOS, add this
  );

  // FIXED: Initialize local notifications plugin
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('app_icon'); // Use your drawable icon
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // NEW: Set up the bell helper for sleeping app
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Hide status bar and navigation bar for immersive mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Squad Game',
      home: AuthWrapper(),
    );
  }
}

// ====================== AUTH WRAPPER ======================
class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user == null || !user.emailVerified) {
          return AuthScreen();
        }

        if (user.displayName == null || user.displayName!.isEmpty) {
          return SetDisplayNameScreen();
        }

        return GameScreen();
      },
    );
  }
}

// ====================== SET DISPLAY NAME (added unique check) ======================
class SetDisplayNameScreen extends StatefulWidget {
  @override
  _SetDisplayNameScreenState createState() => _SetDisplayNameScreenState();
}

class _SetDisplayNameScreenState extends State<SetDisplayNameScreen> {
  final _nameController = TextEditingController();
  bool isLoading = false;

  Future<void> saveDisplayName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => isLoading = true);

    try {
      // NEW: Check if name is unique in players AND usedNames
      final playersQuery = await FirebaseFirestore.instance.collection('players').where('displayName', isEqualTo: name).get();
      final usedNamesQuery = await FirebaseFirestore.instance.collection('usedNames').where('name', isEqualTo: name).get();  // Assuming 'name' field in usedNames

      if (playersQuery.docs.isNotEmpty || usedNamesQuery.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Oops! That name is taken forever. Pick a different one.')));
        setState(() => isLoading = false);
        return;
      }

      await FirebaseAuth.instance.currentUser!.updateDisplayName(name);
      await FirebaseAuth.instance.currentUser!.reload();

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GameScreen()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Your Display Name')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('What should other players call you?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Display Name', border: OutlineInputBorder()),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: isLoading ? null : saveDisplayName,
              child: Text(isLoading ? 'Saving...' : 'Save Display Name'),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================== GAME SCREEN ======================
class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final SocketService _socketService = SocketService();

  List<String> messages = [];
  List<String> onlinePlayers = [];
  TextEditingController _controller = TextEditingController();

  String time = 'Loading...';
  bool cooldown = false;
  Timer? cooldownTimer;
  Timer? _incomeTimer;
  Timer? _globalIncomeTimer;  // NEW: App-wide per-second checker

  int _currentScreen = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  OverlayEntry? _rescueOverlay;

  OverlayEntry? _rankUpOverlay;

  @override
  void initState() {
    super.initState();
    _incomeTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      SocketService().claimIncome();
    });
    WidgetsBinding.instance.addObserver(this);

    _connectToServer();

    _setupPushNotifications();

    _socketService.rescueNotifier.addListener(_showRescueAnimation);
    _socketService.rankUpNotifier.addListener(_showRankUpAnimation);
        _socketService.statsNotifier.addListener(() {
      setState(() {});  // Just refresh the UI when stats update
    });

        // NEW: Trust the server's balanceAfter completely and update the notifier directly
    _socketService.socket?.on('new-transaction', (data) {
      if (data is Map) {
        final amount = (data['amount'] as num?)?.toInt() ?? 0;
        final serverBalanceAfter = (data['balanceAfter'] as num?)?.toInt() ?? 0;

        final currentList = List<Map<String, dynamic>>.from(_socketService.transactionHistoryNotifier.value);

        currentList.insert(0, {
          'description': data['description'] ?? 'Unknown',
          'amount': amount,
          'balanceAfter': serverBalanceAfter,
        });

        if (currentList.length > 25) {
          currentList.removeLast();
        }

        _socketService.transactionHistoryNotifier.value = currentList;
      }
    });

    // NEW: Start global per-second income checker (only if owned props)
    _globalIncomeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final currentStats = _socketService.statsNotifier.value;  // NEW: Use the smart box
      if (currentStats['ownedProperties'] != null && (currentStats['ownedProperties'] as List).isNotEmpty) {
        _checkForDueIncome();
      }
    });

    // NEW: Listen for income claimed (show snackbar app-wide)
    _socketService.incomeClaimedNotifier.addListener(() {
      final amount = _socketService.incomeClaimedNotifier.value;
      if (amount != null && amount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Income received: +\$$amount!')),
        );
        _socketService.incomeClaimedNotifier.value = null;  // Reset
      }
    });

    _socketService.hitExpiredNotifier.addListener(() {
      final data = _socketService.hitExpiredNotifier.value;
      if (data != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bounty on ${data['target']} expired: +\$${data['reward']} refunded!')),
        );
        _socketService.hitExpiredNotifier.value = null;  // Reset
      }
    });
    _socketService.deathNotifier.addListener(() {
      if (mounted) setState(() {});
    });
  }

  // NEW: Set up the bell for notes
  void _setupPushNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showLocalNotification(message); // Show pop-up if app is open
      }
    });

    // NEW: When tap pop-up from sleeping app, open messages screen
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      setState(() => _currentScreen = 2); // Go to messages
    });

    // NEW: If app started from pop-up
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        setState(() => _currentScreen = 2);
      }
    });

    // NEW: Create notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // Matches manifest meta-data
      'High Importance Notifications',
      description: 'Used for important notifications.',
      importance: Importance.high,
    );
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // NEW: Show pop-up note when app is open
  Future<void> _showLocalNotification(RemoteMessage message) async {
    // FIXED: Dynamically set groupKey based on message type/sender
    String groupKey = 'default_group';
    if (message.data['type'] == 'private') {
      final from = message.data['from'] as String?;
      if (from != null) {
        groupKey = 'messages_from_${from.replaceAll(' ', '_')}';
      }
    } else if (message.data['type'] == 'announcement') {
      groupKey = 'mod_announcements';
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'squad_game_channel',
      'Squad Game Notifications',
      channelDescription: 'Notifications for new messages',
      importance: Importance.max,
      priority: Priority.high,
      groupKey: groupKey, // Use dynamic groupKey for bunching
    );

    final NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      message.messageId?.hashCode ?? 0,
      message.notification?.title,
      message.notification?.body,
      notificationDetails,
    );
  }

  void _connectToServer() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _socketService.connect(user.email!, user.displayName ?? 'Anonymous');

    // NEW: Get special key for push notes and save it
    FirebaseMessaging.instance.requestPermission();
    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) {
        FirebaseFirestore.instance.collection('players').doc(user.email).update({
          'fcmTokens': FieldValue.arrayUnion([token])
        });
      }
    });
    // NEW: Join the big announcement group
    FirebaseMessaging.instance.subscribeToTopic('announcements');

    // Listen to socket events
    _socketService.socket?.on(SocketEvents.time, (data) => setState(() => time = data));
    
    _socketService.socket?.on(SocketEvents.message, (data) {
      setState(() {
        messages.add(data);
        if (messages.length > GameConstants.maxChatMessages) {
          messages.removeAt(0);
        }
      });
    });
    _socketService.socket?.on(SocketEvents.onlinePlayers, (data) {
      setState(() => onlinePlayers = List<String>.from(data));
    });
  }

  void robBank() {
    final stats = _socketService.statsNotifier.value;
    if (cooldown || (stats['dead'] == true) || (stats['health'] ?? 100) <= 0) {
      return;
    }

    _socketService.robBank();
    setState(() => cooldown = true);
    cooldownTimer = Timer(const Duration(seconds: GameConstants.robCooldownSeconds), () {
      if (mounted) setState(() => cooldown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: _socketService.statsNotifier,
      builder: (context, stats, child) {
        final bool isPlayerDead = (stats['dead'] == true) || (stats['health'] ?? 100) <= 0 || (_socketService.deathNotifier.value == true);

        if (isPlayerDead) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('YOU ARE DEAD!', style: TextStyle(fontSize: 48, color: Colors.red, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: () async {
                      // FIX: Clear the old death state so the new life starts clean
                      _socketService.deathNotifier.value = false;

                      _socketService.respawn();
                      await FirebaseAuth.instance.currentUser?.updateDisplayName(null);
                      await FirebaseAuth.instance.currentUser?.reload();
                      await FirebaseAuth.instance.signOut();
                      _socketService.disconnect();
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AuthScreen()));
                    },
                    child: const Text('Logout & Start New Life'),
                  ),
                ],
              ),
            ),
          );
        }

        // ← Everything else (your normal Scaffold with drawer, body, etc.) stays exactly the same below this
        return Scaffold(
          key: _scaffoldKey,
          appBar: _currentScreen == 0 
          ? null  // REMOVE AppBar for dashboard
          : StatusAppBar(
              title: _currentScreen == 1 
                  ? 'Players Online' 
                  : _currentScreen == 2 
                      ? 'Messages' 
                      : _currentScreen == 3 
                          ? '✈️ Airport' 
                          : _currentScreen == 4 
                              ? '🏥 Hospital'
                              : _currentScreen == 5 
                                  ? 'Operations'
                                  : _currentScreen == 6 
                                      ? 'Profile'
                                      : _currentScreen == 7 
                                          ? 'Store'
                                          : 'Properties',
              statsNotifier: _socketService.statsNotifier,
              time: time,
              onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          drawer: Sidebar(
            currentScreen: _currentScreen,
            onScreenChanged: (screen) {
              setState(() => _currentScreen = screen);
            },
            stats: _socketService.statsNotifier.value,
            hasUnreadMessages: _socketService.hasUnreadMessages,
          ),
          
          body: _currentScreen == 0 
          ? _buildDashboard() 
          : _currentScreen == 1 
              ? OnlinePlayersScreen(onlinePlayers: onlinePlayers)
              : _currentScreen == 2 
                  ? MessagesScreen()
                  : _currentScreen == 3 
                      ? AirportScreen(
                          currentLocation: _socketService.statsNotifier.value['location'] ?? 'Unknown',
                          currentBalance: _socketService.statsNotifier.value['balance'] ?? 0,
                          currentHealth: _socketService.statsNotifier.value['health'] ?? 100,
                          currentTime: time,
                          prisonEndTime: _socketService.statsNotifier.value['prisonEndTime'] ?? 0,
                        )
                      : _currentScreen == 4 
                          ? HospitalScreen(
                              currentLocation: _socketService.statsNotifier.value['location'] ?? 'Unknown',
                              currentBalance: _socketService.statsNotifier.value['balance'] ?? 0,
                              currentHealth: _socketService.statsNotifier.value['health'] ?? 100,
                              currentTime: time,
                            )
                          : _currentScreen == 5 
                              ? OperationsScreen(
                                  currentLocation: _socketService.statsNotifier.value['location'] ?? 'Unknown',
                                  currentBalance: _socketService.statsNotifier.value['balance'] ?? 0,
                                  currentHealth: _socketService.statsNotifier.value['health'] ?? 100,
                                  currentTime: time,
                                  lastLowLevelOp: _socketService.statsNotifier.value['lastLowLevelOp'] ?? 0,
                                  prisonEndTime: _socketService.statsNotifier.value['prisonEndTime'] ?? 0,
                                  lastMidLevelOp: _socketService.statsNotifier.value['lastMidLevelOp'] ?? 0,
                                  lastHighLevelOp: _socketService.statsNotifier.value['lastHighLevelOp'] ?? 0,
                                  skill: _socketService.statsNotifier.value['skill'] ?? 0,
                                )
                              : _currentScreen == 6 
                                  ? ProfileScreen(stats: _socketService.statsNotifier.value)
                                  : _currentScreen == 7 
                                      ? StoreScreen(
                                        currentBalance: _socketService.statsNotifier.value['balance'] ?? 0,
                                        currentHealth: _socketService.statsNotifier.value['health'] ?? 100,
                                        currentTime: time,
                                        currentLocation: _socketService.statsNotifier.value['location'] ?? 'Unknown',
                                      )
                                      : _currentScreen == 8 
                                        ? PropertiesScreen(initialStats: _socketService.statsNotifier.value)  // Pass stats
                                        : _currentScreen == 9 
                                            ? PrisonScreen(
                                              currentDisplayName: FirebaseAuth.instance.currentUser?.displayName ?? '',
                                              initialViewerPrisonEndTime: _socketService.statsNotifier.value['prisonEndTime'] ?? 0,
                                            )
                                            : _currentScreen == 10  // NEW: Kill a Player
                                            ? const KillPlayerScreen()
                                            : _currentScreen == 11  // NEW: Hall of Fame
                                                ? const HallOfFameScreen()
                                                : PropertiesScreen(initialStats: _socketService.statsNotifier.value),  // Fallback

          floatingActionButton: _currentScreen == 2
          ? FloatingActionButton(
              onPressed: () => _showNewMessageDialog(context),
              child: const Icon(Icons.add_comment),
              tooltip: 'New Message',
            )
          : null,
        );
      },
    );
  }

Widget _buildDashboard() {
  return ValueListenableBuilder<Map<String, dynamic>>(
    valueListenable: _socketService.statsNotifier,
    builder: (context, stats, child) {
      return Column(
        children: [
          // Top section (unchanged until health)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey[800],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                children: [
                  // NEW: Menu button here (with unread dot)
                  Builder(
                    builder: (context) => Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.menu, color: Colors.white),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: _socketService.hasUnreadMessages,
                          builder: (context, hasUnread, child) {
                            if (!hasUnread) return const SizedBox.shrink();
                            return Positioned(
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
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),  // Space between button and time
                  Expanded(  // Let time take remaining space
                    child: Text(
                      time,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text('Location: ${stats['location'] ?? "Unknown"}', style: const TextStyle(fontSize: 16, color: Colors.white70)),
              const SizedBox(height: 8),
                // ==================== UPDATED HEALTH BAR WITH BROKEN BONE ICON ====================
                LinearProgressIndicator(value: (stats['health'] ?? 100) / 100.0, color: Colors.green,
                ),
                Row(
                  children: [
                    Text(
                      'Health: ${stats['health'] ?? 100}/100',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    if (stats['hasBrokenBone'] == true)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.personal_injury,
                          color: Colors.orangeAccent,
                          size: 24,
                        ),
                      ),
                  ],
                ),
                // ==================== END OF UPDATE ====================

                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.adjust, size: 20, color: Colors.orange),  // Bullet icon
                    const SizedBox(width: 4),
                    Text('${stats['bullets'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                    const SizedBox(width: 6),
                    const Icon(Icons.whatshot, size: 20, color: Colors.red),  // Skull or fire icon for kills
                    const SizedBox(width: 4),
                    Text('${stats['kills'] ?? 0}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  ],
                ),
              ],
            ),
          ),
        // Black rectangle ONLY for bank balance + BONDS button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 140),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(16),
            child: Stack(
              children: [
                // Bank balance text (centered)
                Center(
                  child: Text(
                    'Bank: \$${NumberFormat('#,###').format(stats['balance'] ?? 0)}',
                    style: const TextStyle(fontSize: 22, color: Colors.green, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),

                // BONDS button (semi-transparent square, bottom-right)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PersonalBondsScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pie_chart, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'BONDS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Replace the whole "Transaction History" Container with this:
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 140),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transaction History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: _socketService.transactionHistoryNotifier,
                    builder: (context, history, child) {
                      if (history.isEmpty) {
                        return const Center(child: Text('No transactions yet', style: TextStyle(color: Colors.grey)));
                      }
                      return ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (context, index) {
                          final tx = history[index];
                          final amount = tx['amount'] as int;
                          final isPositive = amount > 0;
                          final balanceAfter = tx['balanceAfter'] ?? 0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  isPositive ? '+$amount' : '$amount',
                                  style: TextStyle(color: isPositive ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(tx['description'] as String, style: const TextStyle(color: Colors.white70)),
                                ),
                                Text(
                                  '→ \$${NumberFormat("#,###").format(balanceAfter)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: messages.length,
            itemBuilder: (_, i) => ListTile(title: Text(messages[i])),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[850],
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    SocketService().addTestExp();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Test: +70 Experience')),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  child: const Text('EXP +70'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    SocketService().addTestMoney(200);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Test: +\$200')),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('MONEY +\$200'),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    SocketService().addTestMoney(500000);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Test: +\$500,000')),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('MONEY +\$500K'),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[850],
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    SocketService().addTestBullets(10000);  // NEW: Add test bullets button
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Test: +10,000 Bullets')),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('BULLETS +10K'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Type message...'))),
              ElevatedButton(
                onPressed: () {
                  _socketService.sendMessage(_controller.text);
                  _controller.clear();
                },
                child: const Text('Send'),
              ),
            ],
          ),
        ),
        ],
      );

    },
  );
}

  void _showNewMessageDialog(BuildContext context) {
    final toController = TextEditingController();
    final msgController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Private Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: toController,
              decoration: const InputDecoration(labelText: 'To (exact player name)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: msgController,
              decoration: const InputDecoration(labelText: 'Your message'),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final to = toController.text.trim();
              final msg = msgController.text.trim();
              if (to.isNotEmpty && msg.isNotEmpty) {
                SocketService().sendPrivateMessage(to, msg);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Message sent to $to!')),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showRescueAnimation() {
    final data = _socketService.rescueNotifier.value;
    if (data == null) return;

    _rescueOverlay?.remove();

    _rescueOverlay = OverlayEntry(
      builder: (context) => RescueCelebrationOverlay(
        rescuer: data['rescuer']!,
        onDismiss: () {
          _rescueOverlay?.remove();
          _rescueOverlay = null;
          _socketService.rescueNotifier.value = null;
        },
      ),
    );

    Overlay.of(context).insert(_rescueOverlay!);

    // Auto dismiss after 4.8 seconds
    Future.delayed(const Duration(milliseconds: 4800), () {
      if (_rescueOverlay != null) {
        _rescueOverlay!.remove();
        _rescueOverlay = null;
        _socketService.rescueNotifier.value = null;
      }
    });
  }

    // ==================== NEW: RANK UP ANIMATION ====================
  void _showRankUpAnimation() {
    final data = _socketService.rankUpNotifier.value;
    if (data == null) return;

    _rankUpOverlay?.remove();

    _rankUpOverlay = OverlayEntry(
      builder: (context) => RankUpCelebrationOverlay(
        oldRank: data['oldRank']!,
        newRank: data['newRank']!,
        onDismiss: () {
          _rankUpOverlay?.remove();
          _rankUpOverlay = null;
          _socketService.rankUpNotifier.value = null;
        },
      ),
    );

    Overlay.of(context).insert(_rankUpOverlay!);
  }

  // Check if any property is due and claim (using server sync)
  void _checkForDueIncome() {
    final currentStats = _socketService.statsNotifier.value;  // NEW: Use the smart box
    final claims = currentStats['propertyClaims'] as List<dynamic>? ?? [];
    final nowMs = _socketService.currentServerTime;

    bool isDue = false;
    for (final claim in claims) {
      final lastClaim = claim['lastClaim'] as int? ?? 0;
      final elapsedMs = nowMs - lastClaim;
      if (elapsedMs >= 120000) {  // Use 2 min ms (match server)
        isDue = true;
        break;
      }
    }

    if (isDue) {
      _socketService.claimIncome();  // Trigger if any due
    }
  }

  @override
  void dispose() {
    cooldownTimer?.cancel();
    // _socketService.disconnect();
    _socketService.rescueNotifier.removeListener(_showRescueAnimation);
    _socketService.rankUpNotifier.removeListener(_showRankUpAnimation);
    _rescueOverlay?.remove();
    _rankUpOverlay?.remove();
    WidgetsBinding.instance.removeObserver(this);
    _incomeTimer?.cancel();
    _globalIncomeTimer?.cancel();  // NEW: Cancel global timer
    _socketService.deathNotifier.removeListener(() {
      if (mounted) setState(() {});
    });
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      SocketService().claimIncome();  // Claim when app resumes
      if (!_socketService.isConnected.value) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          _socketService.connect(user.email!, user.displayName ?? 'Anonymous');  // NEW: Reconnect if needed
        }
      }
    } else if (state == AppLifecycleState.paused) {
      _socketService.socket?.disconnect();  // NEW: Force disconnect on background
    }
  }
}