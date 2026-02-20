import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // NEW: For push notes
import 'package:cloud_firestore/cloud_firestore.dart'; // FIXED: Added this import for FirebaseFirestore and FieldValue
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'socket_service.dart';
import 'constants.dart';
import 'dart:async';
import 'online_players_screen.dart';
import 'airport_screen.dart';
import 'messages_screen.dart';
import 'status_app_bar.dart';

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

  // FIXED: Initialize local notifications plugin
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('app_icon'); // Use your drawable icon
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // NEW: Set up the bell helper for sleeping app
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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

// ====================== LOGIN / REGISTER (unchanged) ======================
class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLogin = true;
  bool isLoading = false;
  String message = '';

  Future<void> handleAuth() async {
    setState(() { isLoading = true; message = ''; });

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        setState(() => message = '✅ Account created! Check your email and click the verification link.');
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified) {
        if (user.displayName == null || user.displayName!.isEmpty) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SetDisplayNameScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GameScreen()));
        }
      } else {
        setState(() => message = 'Please verify your email first.');
      }
    } catch (e) {
      setState(() => message = e.toString());
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Login' : 'Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : handleAuth,
              child: Text(isLoading ? 'Loading...' : (isLogin ? 'Login' : 'Create Account')),
            ),
            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(isLogin ? 'Create new account' : 'Already have an account? Login'),
            ),
            if (message.isNotEmpty) Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
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
      // NEW: Check if name is unique
      final query = await FirebaseFirestore.instance.collection('players').where('displayName', isEqualTo: name).get();
      if (query.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Oops! That name is taken. Pick a different one.')));
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

class _GameScreenState extends State<GameScreen> {
  final SocketService _socketService = SocketService();

  List<String> messages = [];
  List<String> onlinePlayers = [];
  TextEditingController _controller = TextEditingController();

  String time = 'Loading...';
  Map<String, dynamic> stats = {'balance': 0, 'health': 100, 'location': 'Riverstone'};
  bool cooldown = false;
  bool isDead = false;
  Timer? cooldownTimer;

  int _currentScreen = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _connectToServer();
    _setupPushNotifications(); // NEW: Set up the bell
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
    _socketService.socket?.on(SocketEvents.init, (data) {
      setState(() => stats = Map.from(data['player'] ?? {}));
      _socketService.loadMessages();
      if ((stats['health'] ?? 100) <= 0) isDead = true;
    });
    _socketService.socket?.on(SocketEvents.updateStats, (data) {
      setState(() {
        stats = Map.from(data);
        if (stats['health'] <= 0) isDead = true;
      });
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
    if (cooldown || isDead) return;
    _socketService.robBank();
    setState(() => cooldown = true);
    cooldownTimer = Timer(const Duration(seconds: GameConstants.robCooldownSeconds), () {
      if (mounted) setState(() => cooldown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isDead) {
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
                  await FirebaseAuth.instance.currentUser?.updateDisplayName(null);
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

    return Scaffold(
      key: _scaffoldKey,
      appBar: _currentScreen == 0
          ? AppBar(
              title: Text('Squad Game - ${FirebaseAuth.instance.currentUser?.displayName ?? "Player"}'),
              leading: Builder(
                builder: (context) => Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _socketService.hasUnreadMessages,
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
            )
          : StatusAppBar(
              title: _currentScreen == 1 
                  ? 'Players Online' 
                  : _currentScreen == 2 
                      ? 'Messages' 
                      : '✈️ Airport',
              stats: stats,
              time: time,
              onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.blue),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    FirebaseAuth.instance.currentUser?.displayName ?? "Player",
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats['location'] ?? "Unknown",
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Dashboard'),
              onTap: () {
                setState(() => _currentScreen = 0);
                Navigator.pop(context);
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _socketService.hasUnreadMessages,
              builder: (context, hasUnread, child) {
                return ListTile(
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
                  onTap: () {
                    setState(() => _currentScreen = 2);
                    Navigator.pop(context);
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Players Online'),
              onTap: () {
                setState(() => _currentScreen = 1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.airplanemode_active),
              title: const Text('Airport'),
              onTap: () {
                setState(() => _currentScreen = 3);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),

      body: _currentScreen == 0 
          ? _buildDashboard() 
          : _currentScreen == 1 
              ? OnlinePlayersScreen(onlinePlayers: onlinePlayers)
              : _currentScreen == 2 
                  ? MessagesScreen()
                  : AirportScreen(
                      currentLocation: stats['location'] ?? 'Unknown',
                      currentBalance: stats['balance'] ?? 0,
                      currentHealth: stats['health'] ?? 100,
                      currentTime: time,
                    ),

      floatingActionButton: _currentScreen == 2
          ? FloatingActionButton(
              onPressed: () => _showNewMessageDialog(context),
              child: const Icon(Icons.add_comment),
              tooltip: 'New Message',
            )
          : null,
    );
  }

  Widget _buildDashboard() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.grey[900],
          child: Column(
            children: [
              Text(time, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Bank: \$${stats['balance']}', style: const TextStyle(fontSize: 20, color: Colors.green)),
              LinearProgressIndicator(value: (stats['health'] ?? 100) / 100.0, color: Colors.green),
              Text('Health: ${stats['health'] ?? 100}/100'),
              const SizedBox(height: 8),
              Text('Location: ${stats['location'] ?? "Unknown"}', style: const TextStyle(fontSize: 16, color: Colors.white70)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: messages.length,
            itemBuilder: (_, i) => ListTile(title: Text(messages[i])),
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
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: cooldown ? null : robBank,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
              child: Text(cooldown ? 'Cooldown 60s' : '💰 ROB A BANK 💰', style: const TextStyle(fontSize: 18)),
            ),
          ),
        ),
      ],
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

  @override
  void dispose() {
    cooldownTimer?.cancel();
    // _socketService.disconnect();
    super.dispose();
  }
}