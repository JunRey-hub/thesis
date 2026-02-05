import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart'; // Ensure you import your colors
import 'account_settings_page.dart'; // <--- Import the new page

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  
  // Logic to send Password Reset Email
  void _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      if (user != null && user.email != null) {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Password reset email sent! Check your inbox."),
              backgroundColor: Colors.green,
            )
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"), 
        backgroundColor: AppColors.background, 
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.background,
      body: ListView(
        children: [
          const SizedBox(height: 20),
          
          // --- Section 1: Account ---
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text("Account", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
          ),
          
          ListTile(
            leading: const Icon(Icons.person, color: Colors.white),
            title: const Text("Account Info", style: TextStyle(color: Colors.white)),
            subtitle: const Text("Name, Profile Image, Phone", style: TextStyle(color: Colors.grey)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              // Navigate to the separate Account Page
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const AccountSettingsPage())
              );
            },
          ),
          
          const Divider(color: Colors.grey),

          // --- Section 2: Security ---
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text("Security", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
          ),
          
          ListTile(
            leading: const Icon(Icons.lock_reset, color: Colors.white),
            title: const Text("Change Password", style: TextStyle(color: Colors.white)),
            subtitle: const Text("Receive an email to reset password", style: TextStyle(color: Colors.grey)),
            onTap: _changePassword,
          ),

          const Divider(color: Colors.grey),

          // --- Section 3: Logout ---
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                // Navigate back to Login (Route '/')
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
    );
  }
}