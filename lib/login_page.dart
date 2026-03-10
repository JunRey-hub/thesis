import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'register_page.dart';
import 'dashboard_page.dart';
import 'personal_info_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passController  = TextEditingController();
  bool _obscurePass = true;

  Future<void> _login() async {
    final c = AppColorScheme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: c.accent),
      ),
    );

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passController.text.trim(),
      );

      final user = cred.user;
      if (user == null) return;

      // ── Email verification check ────────────────────────────────
      if (!user.emailVerified) {
        await FirebaseAuth.instance.signOut();
        if (mounted) Navigator.pop(context);
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Email Not Verified"),
              content: const Text(
                "Please check your inbox and verify your email before logging in.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
        return;
      }

      // ── Profile completion check ────────────────────────────────
      final dbRef  = FirebaseDatabase.instance.ref("users/${user.uid}");
      final snap   = await dbRef.get();
      if (mounted) Navigator.pop(context);

      if (mounted) {
        if (snap.exists && snap.child("profileComplete").value == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainScaffold()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PersonalInfoPage()),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final c = AppColorScheme.of(context);
        String msg = "Authentication Failed";
        if (e.code == 'user-not-found' ||
            e.code == 'wrong-password' ||
            e.code == 'invalid-credential') {
          msg = "Invalid email or password.";
        } else if (e.code == 'network-request-failed') {
          msg = "No internet connection.";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: c.danger),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Logo ─────────────────────────────────────────────
              Icon(Icons.security, size: 80, color: c.accent),
              const SizedBox(height: 16),
              Text(
                "KEEP WATCH",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Guardian Tracking System",
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 50),

              // ── Email ─────────────────────────────────────────────
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: "Guardian Email",
                  prefixIcon: Icon(Icons.person_outline, color: c.textSecondary),
                ),
              ),
              const SizedBox(height: 15),

              // ── Password ──────────────────────────────────────────
              TextField(
                controller: _passController,
                obscureText: _obscurePass,
                style: TextStyle(color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: "Passcode",
                  prefixIcon: Icon(Icons.lock_outline, color: c.textSecondary),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      color: c.textSecondary,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // ── Login button ──────────────────────────────────────
              ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "AUTHENTICATE",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),

              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterPage()),
                ),
                child: Text(
                  "Register New Guardian",
                  style: TextStyle(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}