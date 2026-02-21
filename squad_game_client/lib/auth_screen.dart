import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';

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