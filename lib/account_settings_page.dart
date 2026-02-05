import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart'; // Ensure you have this imported

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  User? user = FirebaseAuth.instance.currentUser; 
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Load existing data from Realtime Database
  void _loadUserData() async {
    if (user != null) {
      final ref = FirebaseDatabase.instance.ref("users/${user!.uid}");
      final snapshot = await ref.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        if (mounted) {
          setState(() {
            _nameController.text = data['fullName'] ?? '';
            _phoneController.text = data['phone'] ?? '';
          });
        }
      }
    }
  }

  // Save changes to Realtime Database
  Future<void> _saveChanges() async {
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseDatabase.instance.ref("users/${user!.uid}").update({
        "fullName": _nameController.text.trim(),
        "phone": _phoneController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account details saved!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // --- Profile Image Placeholder ---
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: null, // Add NetworkImage here if you implement storage
                    child: const Icon(Icons.person, size: 60, color: Colors.white54),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.accent,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 18, color: Colors.black),
                        onPressed: () {
                          // Logic for image picker would go here
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Image upload feature coming soon!"))
                          );
                        },
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 30),

            // --- Input Fields ---
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Full Name",
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.person_outline, color: AppColors.accent),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _phoneController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Phone Number",
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.phone, color: AppColors.accent),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            const SizedBox(height: 20),

            // --- Read Only Email ---
            TextField(
              readOnly: true,
              controller: TextEditingController(text: user?.email),
              style: const TextStyle(color: Colors.white70),
              decoration: const InputDecoration(
                labelText: "Email (Cannot change)",
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.email, color: Colors.grey),
                border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              ),
            ),
            
            const SizedBox(height: 40),

            // --- Save Button ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text("SAVE CHANGES", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}