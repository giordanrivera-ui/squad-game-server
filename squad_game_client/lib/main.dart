import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBORGcBRzeMGsLm30vdSMiAjbFbi30olJE",
      authDomain: "squad-game-1d87d.firebaseapp.com",
      projectId: "squad-game-1d87d",
      storageBucket: "squad-game-1d87d.firebasestorage.app",
      messagingSenderId: "224646200519",
      appId: "1:224646200519:web:de4f329b3a63a1ff63d2e2",
    ),
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Squad Game',
      home: AuthWrapper(),   // ← This is the new smart wrapper
    );
  }
}

// ====================== AUTH WRAPPER (handles auto-login on refresh) ======================
class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;

        // Not logged in
        if (user == null) {
          return AuthScreen();
        }

        // Logged in but email not verified
        if (!user.emailVerified) {
          return AuthScreen(); // Show login screen again
        }

        // Logged in + verified → check if they need to set display name
        if (user.displayName == null || user.displayName!.isEmpty) {
          return SetDisplayNameScreen();
        }

        // Everything good → go straight to game
        return GameScreen();
      },
    );
  }
}

// ====================== LOGIN / REGISTER ======================
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

// ====================== SET DISPLAY NAME ======================
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
  IO.Socket? socket;
  List<String> messages = [];
  List<String> onlinePlayers = [];
  TextEditingController _controller = TextEditingController();

  String time = 'Loading...';
  Map<String, dynamic> stats = {'balance': 0, 'health': 100};
  bool cooldown = false;
  bool isDead = false;
  Timer? cooldownTimer;

  // NEW: Controls which screen is shown
  int _currentScreen = 0; // 0 = Dashboard (main game), 1 = Players Online

  @override
  void initState() {
    super.initState();
    connectToServer();
  }

  void connectToServer() {
    socket = IO.io('https://squad-game-server.onrender.com', IO.OptionBuilder().setTransports(['websocket']).build());

    socket?.onConnect((_) {
      final user = FirebaseAuth.instance.currentUser;
      socket?.emit('register', {'email': user?.email, 'displayName': user?.displayName ?? 'Anonymous'});
      setState(() => messages.add('✅ Connected as ${user?.displayName}'));
    });

    socket?.on('time', (data) => setState(() => time = data));
    socket?.on('init', (data) => setState(() => stats = Map.from(data)));
    socket?.on('update-stats', (data) {
      setState(() {
        stats = Map.from(data);
        if (stats['health'] <= 0) isDead = true;
      });
    });
    socket?.on('message', (data) => setState(() => messages.add(data)));
    socket?.on('online-players', (data) => setState(() => onlinePlayers = List<String>.from(data)));
  }

  void robBank() {
    if (cooldown || isDead) return;
    socket?.emit('rob-bank');
    setState(() => cooldown = true);
    cooldownTimer = Timer(const Duration(seconds: 60), () {
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
      appBar: AppBar(
        title: Text(_currentScreen == 0 
            ? 'Squad Game - ${FirebaseAuth.instance.currentUser?.displayName ?? "Player"}'
            : 'Players Online'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          if (_currentScreen == 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('Online: ${onlinePlayers.length}', style: const TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),

      // ==================== SIDE MENU ========================
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text('Squad Game Menu', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Dashboard'),
              onTap: () {
                setState(() => _currentScreen = 0);
                Navigator.pop(context); // close menu
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Players Online'),
              onTap: () {
                setState(() => _currentScreen = 1);
                Navigator.pop(context); // close menu
              },
            ),
            // Add more items here later
          ],
        ),
      ),

      // ==================== BODY - Switches between screens ====================
      body: _currentScreen == 0 ? _buildDashboard() : _buildPlayersScreen(),
    );
  }

  // Main Dashboard (original game screen)
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
                  if (_controller.text.isNotEmpty) {
                    socket?.emit('message', _controller.text);
                    _controller.clear();
                  }
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

  // Players Online Screen
  Widget _buildPlayersScreen() {
    return onlinePlayers.isEmpty
        ? const Center(child: Text('No one is online right now'))
        : ListView.builder(
            itemCount: onlinePlayers.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.person),
              title: Text(onlinePlayers[index]),
            ),
          );
  }

  @override
  void dispose() {
    cooldownTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }
}