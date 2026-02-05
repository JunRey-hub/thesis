import 'dart:io'; // Required for handling local files
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart'; // Required for Storage
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Required for picking images
import 'app_colors.dart'; 

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
  
  // --- New Variables for Image Handling ---
  File? _imageFile;           // Stores the image selected from gallery
  String? _profileImageUrl;   // Stores the URL downloaded from Firebase
  final ImagePicker _picker = ImagePicker();

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
            // Load the saved image URL if it exists
            _profileImageUrl = data['profileImage']; 
          });
        }
      }
    }
  }

  // --- Step 1: Pick Image from Gallery ---
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512, // Resize to save data/storage
        maxHeight: 512,
        imageQuality: 75,
      );
      
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error picking image: $e"))
        );
      }
    }
  }

  // --- Step 2: Upload Image to Firebase Storage ---
  Future<String?> _uploadImage() async {
    // If no new image was picked, just return the old URL
    if (_imageFile == null) return _profileImageUrl;
    if (user == null) return null;

    try {
      // 1. Create a reference to "user_images/USER_ID.jpg"
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_images/${user!.uid}.jpg');
      
      // 2. Upload the file
      await storageRef.putFile(_imageFile!);
      
      // 3. Get the permanent download URL
      String downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("Storage Error: $e");
      throw Exception("Image upload failed. Check your internet.");
    }
  }

  // --- Step 3: Save Everything to Database ---
  Future<void> _saveChanges() async {
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // A. Upload the image first (if changed)
      String? imageUrl = await _uploadImage();

      // B. Update Realtime Database with Name, Phone, and Image URL
      await FirebaseDatabase.instance.ref("users/${user!.uid}").update({
        "fullName": _nameController.text.trim(),
        "phone": _phoneController.text.trim(),
        "profileImage": imageUrl, // Save the URL
      });

      // C. Update local state
      if (mounted) {
        setState(() {
          _profileImageUrl = imageUrl;
          _imageFile = null; // Clear local file since it's now saved online
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Account details saved successfully!"), 
            backgroundColor: Colors.green
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine which image to show: Local File > Network URL > Default Icon
    ImageProvider? backgroundImage;
    if (_imageFile != null) {
      backgroundImage = FileImage(_imageFile!);
    } else if (_profileImageUrl != null) {
      backgroundImage = NetworkImage(_profileImageUrl!);
    }

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
            // --- Profile Image Area ---
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: backgroundImage,
                    // Only show the person icon if there is no image to display
                    child: backgroundImage == null 
                        ? const Icon(Icons.person, size: 60, color: Colors.white54) 
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.accent,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 18, color: Colors.black),
                        onPressed: _pickImage, // TRIGGERS THE IMAGE PICKER
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
                  ? const SizedBox(
                      height: 20, width: 20, 
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                    )
                  : const Text("SAVE CHANGES", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}