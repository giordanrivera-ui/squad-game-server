import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'socket_service.dart';
import 'constants.dart';
import 'dart:async';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'rescue_celebration_overlay.dart';
import 'rank_up_celebration_overlay.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'screens.dart';
import 'crime_alert_overlay.dart';
import 'deliver_justice_overlay.dart';
import 'audio_service.dart';

// Global plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// Background helper - runs when app is sleeping and gets a note
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Got a background note: ${message.messageId}'); // For testing
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase only if not already done (no options for mobile)
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();  // No options - uses google-services.json on Android
  }

  AudioService().playBackgroundMusic();

  await MobileAds.instance.initialize();

  await MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
      testDeviceIds: ['8DE8D97F76EDF7B3E4F54A8BE17AE570'],
      // This helps prevent Firebase auto-integration issues
      tagForChildDirectedTreatment: TagForChildDirectedTreatment.unspecified,
    ),
  );

    // Activate App Check with the updated syntax
  await FirebaseAppCheck.instance.activate(
    providerAndroid: const AndroidDebugProvider(),  // For testing/debug
    // providerWeb: ReCaptchaV3Provider('YOUR_RECAPTCHA_SITE_KEY'),  // If you have web support, add your key here
    // providerApple: AppleDebugProvider(),  // If you have iOS, add this
  );

  // Initialize local notifications plugin
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('app_icon'); // Use your drawable icon
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Set up the bell helper for sleeping app
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
      debugShowCheckedModeBanner: false,
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

// ====================== SET DISPLAY NAME (with live input filtering) ======================
class SetDisplayNameScreen extends StatefulWidget {
  @override
  _SetDisplayNameScreenState createState() => _SetDisplayNameScreenState();
}

class _SetDisplayNameScreenState extends State<SetDisplayNameScreen> {
  final _nameController = TextEditingController();
  bool isLoading = false;

  String? _validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty';
    if (trimmed.length > 22) return 'Maximum 22 characters allowed';
    if (['.', '/', '\\'].contains(trimmed[0])) {
      return 'Name cannot start with ".", "/", or "\\"';
    }
    return null; // valid
  }

  Future<void> saveDisplayName() async {
    final name = _nameController.text.trim();
    final error = _validateName(name);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final playersQuery = await FirebaseFirestore.instance
          .collection('players')
          .where('displayName', isEqualTo: name)
          .get();
      final usedNamesQuery = await FirebaseFirestore.instance
          .collection('usedNames')
          .where('name', isEqualTo: name)
          .get();

      if (playersQuery.docs.isNotEmpty || usedNamesQuery.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oops! That name is taken forever.')),
        );
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
            const Text(
              'What should other players call you?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
                helperText: 'Max 22 characters • Cannot start with . / \\',
              ),
              textAlign: TextAlign.center,
              maxLength: 22,                    // visual counter
              maxLengthEnforcement: MaxLengthEnforcement.enforced,

              // ==================== LIVE INPUT FILTERING ====================
              inputFormatters: [
                LengthLimitingTextInputFormatter(22),           // hard limit 22 chars
                FilteringTextInputFormatter.deny(RegExp(r'^[./\\]')), // block starting . / \
              ],
              // =============================================================
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
  Timer? _globalIncomeTimer;  // App-wide per-second checker
  Timer? _dashboardTimer;

  bool _isTxHistoryMinimized = false;   // Controls minimize state

  int _currentScreen = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  OverlayEntry? _rescueOverlay;
  OverlayEntry? _rankUpOverlay;
  OverlayEntry? _crimeAlertOverlay;
  OverlayEntry? _deliverJusticeOverlay;

  @override
  void initState() {
    super.initState();
    _incomeTimer = Timer.periodic(const Duration(minutes: 2), (_) {SocketService().claimIncome();});
    _dashboardTimer = Timer.periodic(const Duration(seconds: 1), (_) {if (mounted) setState(() {});});
    WidgetsBinding.instance.addObserver(this);

    _connectToServer();
    _setupPushNotifications();
    SocketService().startGlobalCourseCompletionWatcher();
    SocketService().startGlobalHealingClaimer();
    _socketService.crimeAlertNotifier.addListener(_showCrimeAlert);
    _socketService.rescueNotifier.addListener(_showRescueAnimation);
    _socketService.rankUpNotifier.addListener(_showRankUpAnimation);

        _socketService.statsNotifier.addListener(() {
      setState(() {});  // Just refresh the UI when stats update
    });

        // Trust the server's balanceAfter completely and update the notifier directly
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

    // Start global per-second income checker (only if owned props)
    _globalIncomeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final currentStats = _socketService.statsNotifier.value;  // NEW: Use the smart box
      if (currentStats['ownedProperties'] != null && (currentStats['ownedProperties'] as List).isNotEmpty) {
        _checkForDueIncome();
      }
    });

    // Listen for income claimed (show snackbar app-wide)
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

  // Set up the bell for notes
  void _setupPushNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showLocalNotification(message); // Show pop-up if app is open
      }
    });

    // When tap pop-up from sleeping app, open messages screen
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      setState(() => _currentScreen = 2); // Go to messages
    });

    // If app started from pop-up
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        setState(() => _currentScreen = 2);
      }
    });

    // Create notification channel
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

  // Show pop-up note when app is open
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

    // Get special key for push notes and save it
    FirebaseMessaging.instance.requestPermission();
    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) {
        FirebaseFirestore.instance.collection('players').doc(user.email).update({
          'fcmTokens': FieldValue.arrayUnion([token])
        });
      }
    });
    // Join the big announcement group
    FirebaseMessaging.instance.subscribeToTopic('announcements');

    // Listen to socket events
    _socketService.socket?.on(SocketEvents.time, (data) {
      if (data is String) {
        setState(() => time = data);
      } else if (data is Map && data['formatted'] is String) {
        // New format from server (when we add serverTime)
        setState(() => time = data['formatted']);
      }
    });
    
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

      // ==================== MAIN APP WITH BACK NAVIGATION HANDLING ====================
      return PopScope(
        canPop: _currentScreen == 0,                    // Only allow closing app when on Dashboard
        onPopInvoked: (didPop) {
          if (!didPop && _currentScreen != 0) {
            // User pressed back on any other screen → return to Dashboard
            setState(() => _currentScreen = 0);
          }
        },
        child: Scaffold(
          key: _scaffoldKey,
          appBar: _currentScreen == 0 
              ? null 
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
                                              : _currentScreen == 12 
        ? 'Businesses'
        : _currentScreen == 13
            ? 'Fitness Center'
            : 'Businesses',
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
                              currentBalance: (_socketService.statsNotifier.value['balance'] ?? 0).toInt(),
                              currentHealth: _socketService.statsNotifier.value['health'] ?? 100,
                              currentTime: time,
                              prisonEndTime: _socketService.statsNotifier.value['prisonEndTime'] ?? 0,
                            )
                          : _currentScreen == 4 
                              ? HospitalScreen()
                              : _currentScreen == 5 
                                  ? OperationsScreen(
                                      currentLocation: _socketService.statsNotifier.value['location'] ?? 'Unknown',
                                      currentBalance: (_socketService.statsNotifier.value['balance'] ?? 0).toInt(),
                                      currentHealth: _socketService.statsNotifier.value['health'] ?? 100,
                                      currentTime: time,
                                      lastLowLevelOp: (_socketService.statsNotifier.value['lastLowLevelOp'] ?? 0).toInt(),
                                      prisonEndTime: (_socketService.statsNotifier.value['prisonEndTime'] ?? 0).toInt(),
                                      lastMidLevelOp: (_socketService.statsNotifier.value['lastMidLevelOp'] ?? 0.toInt()),
                                      lastHighLevelOp: (_socketService.statsNotifier.value['lastHighLevelOp'] ?? 0).toInt(),
                                      skill: _socketService.statsNotifier.value['skill'] ?? 0,
                                      hasEnhancedStamina: _socketService.statsNotifier.value['enhancedStaminaEndTime'] != null &&
                                          (_socketService.statsNotifier.value['enhancedStaminaEndTime'] as int) > SocketService().currentServerTime,
                                    )
                                  : _currentScreen == 6 
                                      ? ProfileScreen(
                                          stats: {
                                            ..._socketService.statsNotifier.value,
                                            'balance': (_socketService.statsNotifier.value['balance'] ?? 0).toInt(),
                                          },
                                        )
                                      : _currentScreen == 7 
                                          ? StoreScreen(
                                              currentBalance: (_socketService.statsNotifier.value['balance'] ?? 0).toInt(),
                                              currentHealth: _socketService.statsNotifier.value['health'] ?? 100,
                                              currentTime: time,
                                              currentLocation: _socketService.statsNotifier.value['location'] ?? 'Unknown',
                                            )
                                          : _currentScreen == 9 
                                              ? PrisonScreen(
                                                  currentDisplayName: FirebaseAuth.instance.currentUser?.displayName ?? '',
                                                  initialViewerPrisonEndTime: _socketService.statsNotifier.value['prisonEndTime'] ?? 0,
                                                )
                                              : _currentScreen == 10 
                                                  ? const KillPlayerScreen()
                                                  : _currentScreen == 11 
                                                      ? const HallOfFameScreen()
                                                      : _currentScreen == 12 
                                                          ? const BusinessesScreen()
                                                          : _currentScreen == 13
                                                            ? const FitnessCenterScreen()
                                                            : const BusinessesScreen(),

          floatingActionButton: _currentScreen == 2
              ? FloatingActionButton(
                  onPressed: () => _showNewMessageDialog(context),
                  child: const Icon(Icons.add_comment),
                  tooltip: 'New Message',
                )
              : null,
        ),
      );
    },
  );
}

Widget _buildDashboard() {
  return Container(
    decoration: const BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/background.jpg'),
        fit: BoxFit.cover,
      ),
    ),
    child: Container(
      // Dark overlay for better readability
      color: Colors.black.withOpacity(0.27),
      child: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: _socketService.statsNotifier,
        builder: (context, stats, child) {
          final int? staminaEndTime = stats['enhancedStaminaEndTime'] as int?;
          final bool hasEnhancedStamina = 
              staminaEndTime != null && staminaEndTime > SocketService().currentServerTime;
          
          String? staminaRemainingText;
          if (hasEnhancedStamina && staminaEndTime != null) {
            final remainingMs = staminaEndTime - SocketService().currentServerTime;
            if (remainingMs > 0) {
              final remainingSeconds = (remainingMs / 1000).ceil();
              final minutes = remainingSeconds ~/ 60;
              final seconds = remainingSeconds % 60;
              staminaRemainingText = '$minutes:${seconds.toString().padLeft(2, '0')}';
            }
          }

          // ==================== NET WORTH CALCULATION ====================
          final int bankBalance = (stats['balance'] as num?)?.toInt() ?? 0;

          final List<dynamic> inventory = stats['inventory'] as List<dynamic>? ?? [];
          int inventoryValue = 0;

          for (var item in inventory) {
            if (item is Map) {
              final itemValue = (item['value'] as num?)?.toInt() 
                  ?? (item['cost'] as num?)?.toInt() 
                  ?? 0;
              inventoryValue += itemValue;
            }
          }

          final int inventoryAt60Percent = (inventoryValue * 0.6).floor();

          int propertiesValue = 0;
          final List<dynamic> ownedPropertyNames = stats['ownedProperties'] as List<dynamic>? ?? [];
          final List<Map<String, dynamic>> allProperties = SocketService().properties;

          for (var name in ownedPropertyNames) {
            if (name is String) {
              final prop = allProperties.firstWhere(
                (p) => p['name'] == name,
                orElse: () => {},
              );
              if (prop.isNotEmpty) {
                propertiesValue += (prop['cost'] as num?)?.toInt() ?? 0;
              }
            }
          }

          final int netWorth = bankBalance + inventoryAt60Percent + propertiesValue;

          return Column(
            children: [
              DashboardHeader(
                time: time,
                stats: stats,
                hasEnhancedStamina: hasEnhancedStamina,
                staminaRemainingText: staminaRemainingText,
                onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                onDeveloperOptionsPressed: _showDeveloperOptions,
              ),
              DashboardBankCard(
                balance: (stats['balance'] as num?)?.toInt() ?? 0,
                netWorth: netWorth,
              ),
              // Transaction History
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Transaction History',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              _isTxHistoryMinimized ? Icons.expand_more : Icons.expand_less,
                              color: Colors.white70,
                              size: 24,
                            ),
                            onPressed: () {
                              setState(() => _isTxHistoryMinimized = !_isTxHistoryMinimized);
                            },
                            tooltip: _isTxHistoryMinimized ? 'Expand' : 'Minimize',
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      if (!_isTxHistoryMinimized)
                        SizedBox(
                          height: 220,
                          child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                            valueListenable: _socketService.transactionHistoryNotifier,
                            builder: (context, history, child) {
                              if (history.isEmpty) {
                                return const Center(
                                  child: Text('No transactions yet', style: TextStyle(color: Colors.grey)),
                                );
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
                                          style: TextStyle(
                                            color: isPositive ? Colors.green : Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            tx['description'] as String,
                                            style: const TextStyle(color: Colors.white70),
                                          ),
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

              // Chat Messages
              Expanded(
                child: ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (_, i) => ListTile(title: Text(messages[i])),
                ),
              ),

              // Message Input
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller, 
                        decoration: const InputDecoration(hintText: 'Type message...')
                      ),
                    ),
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
      ),
    ),
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

  void _showCrimeAlert() {
    final data = _socketService.crimeAlertNotifier.value;
    if (data == null) return;

    _crimeAlertOverlay?.remove();

    _crimeAlertOverlay = OverlayEntry(
      builder: (context) => CrimeAlertOverlay(
        message: data['message'] ?? '',
        onIgnore: () {
          _crimeAlertOverlay?.remove();
          _crimeAlertOverlay = null;
          _socketService.crimeAlertNotifier.value = null;
        },
        onDeliverJustice: () {
          _crimeAlertOverlay?.remove();
          _crimeAlertOverlay = null;
          _socketService.crimeAlertNotifier.value = null;

          // Show Deliver Justice overlay
          _showDeliverJusticeOverlay();
        },
      ),
    );

    Overlay.of(context).insert(_crimeAlertOverlay!);
  }

  void _showDeliverJusticeOverlay() {
    _deliverJusticeOverlay?.remove();

    _deliverJusticeOverlay = OverlayEntry(
      builder: (context) => DeliverJusticeOverlay(
        onDismiss: () {
          _deliverJusticeOverlay?.remove();
          _deliverJusticeOverlay = null;
        },
      ),
    );

    Overlay.of(context).insert(_deliverJusticeOverlay!);
  }

  void _showDeveloperOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Developer Options',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 20),

              // Test Buttons
              ElevatedButton(
                onPressed: () {
                  SocketService().addTestExp();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Test: +70 Experience')),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                child: const Text('EXP +70'),
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () {
                  SocketService().addTestMoney(200);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Test: +\$200')),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('MONEY +\$200'),
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () {
                  SocketService().addTestMoney(500000);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Test: +\$500,000')),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('MONEY +\$500K'),
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () {
                  SocketService().addTestBullets(10000);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Test: +10,000 Bullets')),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('BULLETS +10K'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
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
    SocketService().stopGlobalCourseCompletionWatcher();
    SocketService().stopGlobalHealingClaimer();
    _socketService.rescueNotifier.removeListener(_showRescueAnimation);
    _socketService.rankUpNotifier.removeListener(_showRankUpAnimation);
    _socketService.crimeAlertNotifier.removeListener(_showCrimeAlert);
    _rescueOverlay?.remove();
    _rankUpOverlay?.remove();
    _crimeAlertOverlay?.remove();
    _deliverJusticeOverlay?.remove();
    WidgetsBinding.instance.removeObserver(this);
    _incomeTimer?.cancel();
    _globalIncomeTimer?.cancel();  // Cancel global timer
    _dashboardTimer?.cancel();
    _socketService.deathNotifier.removeListener(() {
      if (mounted) setState(() {});
    });
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      AudioService().resume();
      SocketService().claimIncome();  // Claim when app resumes
      if (!_socketService.isConnected.value) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          _socketService.connect(user.email!, user.displayName ?? 'Anonymous');  // NEW: Reconnect if needed
        }
      }
    } else if (state == AppLifecycleState.paused) {
      AudioService().pause();
      _socketService.socket?.disconnect();  // Force disconnect on background
    }
  }
}