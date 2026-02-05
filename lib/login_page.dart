import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // <--- NEW IMPORT
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'register_page.dart';
import 'dashboard_page.dart';
import 'personal_info_page.dart'; // <--- MAKE SURE YOU CREATED THIS FILE

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();

  // --- NEW SMART LOGIN LOGIC ---
  Future<void> _login() async {
    // 1. Show Loading Circle
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );

    try {
      // 2. Attempt Firebase Login
      UserCredential cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passController.text.trim(),
      );

      User? user = cred.user;

      if (user != null) {
        // --- CHECK 1: EMAIL VERIFICATION ---
        if (!user.emailVerified) {
          await FirebaseAuth.instance.signOut(); // Kick them out immediately
          
          if (mounted) Navigator.pop(context); // Close Spinner

          // Show Warning Dialog
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.grey[900],
                title: const Text("Email Not Verified", style: TextStyle(color: Colors.white)),
                content: const Text(
                  "Please check your inbox and verify your email before logging in.",
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context), 
                    child: const Text("OK", style: TextStyle(color: AppColors.accent))
                  )
                ],
              ),
            );
          }
          return; // Stop here
        }

        // --- CHECK 2: PROFILE COMPLETION ---
        // Check database to see if they finished setup
        final dbRef = FirebaseDatabase.instance.ref("users/${user.uid}");
        final snapshot = await dbRef.get();

        if (mounted) Navigator.pop(context); // Close Spinner

        if (mounted) {
          if (snapshot.exists && snapshot.child("profileComplete").value == true) {
            // A. Profile is Ready -> Go to Dashboard
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => const MainScaffold())
            );
          } else {
            // B. Profile Missing -> Go to Personal Info Page
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => const PersonalInfoPage())
            );
          }
        }
      }

    } on FirebaseAuthException catch (e) {
      // 3. Handle Login Errors
      if (mounted) {
        Navigator.pop(context); // Close loading
        
        String errorMessage = "Authentication Failed";
        if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
          errorMessage = "Invalid email or password.";
        } else if (e.code == 'network-request-failed') {
          errorMessage = "No internet connection.";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.danger,
          ),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.security, size: 80, color: AppColors.accent),
              const SizedBox(height: 20),
              const Text("KEEP WATCH", textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
              const SizedBox(height: 50),
              
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Guardian Email", 
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.person_outline, color: AppColors.textGrey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
                ),
              ),
              const SizedBox(height: 15),
              
              TextField(
                controller: _passController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Passcode", 
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.lock_outline, color: AppColors.textGrey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
                ),
              ),
              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: _login, 
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("AUTHENTICATE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
              
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const RegisterPage())),
                child: const Text("Register New Guardian", style: TextStyle(color: AppColors.textGrey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}