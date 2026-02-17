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
      home: AuthScreen(),   // Starts with login / register
    );
  }
}

// ====================== LOGIN / REGISTER SCREEN ======================
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
    setState(() => isLoading = true);
    message = '';

    try {
      if (isLogin) {
        // Login
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        // Register new account
        UserCredential user = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        await user.user!.sendEmailVerification();
        setState(() => message = '✅ Account created!\nCheck your email and click the verification link.');
        return;
      }

      // After login, check if email is verified
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => GameScreen()),
        );
      } else {
        setState(() => message = 'Please check your email and click the verification link first.');
      }
    } catch (e) {
      setState(() => message = e.toString());
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Login to Squad Game' : 'Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email address'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : handleAuth,
              child: Text(isLoading ? 'Please wait...' : (isLogin ? 'Login' : 'Create Account')),
            ),
            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(isLogin ? 'Need an account? Register' : 'Already have an account? Login'),
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

// ====================== MAIN GAME SCREEN (only shown after login + verification) ======================
class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  IO.Socket? socket;
  List<String> messages = [];
  TextEditingController _controller = TextEditingController();

  String time = 'Loading...';
  Map<String, dynamic> stats = {'balance': 0, 'health': 100};
  bool cooldown = false;
  bool isDead = false;
  Timer? cooldownTimer;

  @override
  void initState() {
    super.initState();
    connectToServer();
  }

  void connectToServer() {
    socket = IO.io('https://squad-game-server.onrender.com', IO.OptionBuilder()
        .setTransports(['websocket'])
        .build());

    socket?.onConnect((_) {
      setState(() => messages.add('✅ Connected to server!'));
      final user = FirebaseAuth.instance.currentUser;
      socket?.emit('register', user?.email ?? 'anonymous');
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
              const SizedBox(height: 20),
              const Text('YOU ARE DEAD!', style: TextStyle(fontSize: 48, color: Colors.red, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut().then((_) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AuthScreen()));
                }),
                child: const Text('Logout & Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final balance = stats['balance']?.toString() ?? '0';
    final health = (stats['health'] ?? 100) / 100.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Squad Game')),
      body: Column(
        children: [
          // Top bar: Time + Balance + Health
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Column(
              children: [
                Text(time, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text('Bank: \$$balance', style: const TextStyle(fontSize: 20, color: Colors.green)),
                const SizedBox(height: 12),
                Stack(
                  children: [
                    Container(height: 12, decoration: BoxDecoration(color: Colors.red[300], borderRadius: BorderRadius.circular(6))),
                    Container(height: 12, width: health * MediaQuery.of(context).size.width * 0.8, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(6))),
                  ],
                ),
                Text('Health: ${stats['health'] ?? 100}/100'),
              ],
            ),
          ),

          // Chat area
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (_, i) => ListTile(title: Text(messages[i])),
            ),
          ),

          // Chat input
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Type message...'))),
                ElevatedButton(onPressed: () {
                  if (_controller.text.isNotEmpty) {
                    socket?.emit('message', _controller.text);
                    _controller.clear();
                  }
                }, child: const Text('Send')),
              ],
            ),
          ),

          // Rob Bank button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: cooldown ? null : robBank,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700], padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(cooldown ? 'Rob Cooldown (60s)' : '💰 ROB A BANK 💰', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
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