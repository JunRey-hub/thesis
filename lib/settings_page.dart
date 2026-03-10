import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'account_settings_page.dart';
import 'wristband_pairing_page.dart';
import 'login_page.dart';
import 'main.dart' show ThemeNotifier;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _fullName;
  String? _profileImageUrl;
  String? _pairedWristbandId;
  String? _wristbandLabel;
  bool _alertsEnabled = true;

  final _db = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL:
        'https://keep-watch-d3e89-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await _db.ref('users/${user.uid}').get();
    if (snap.exists && mounted) {
      final data = snap.value as Map? ?? {};
      setState(() {
        _fullName          = data['fullName']?.toString() ?? 'Guardian';
        _profileImageUrl   = data['profileImage']?.toString();
        _pairedWristbandId = data['paired_wristband']?.toString();
        _wristbandLabel    = data['wristband_label']?.toString() ?? 'Unnamed Device';
        _alertsEnabled     = data['alerts_enabled'] != false;
      });
    }
  }

  Future<void> _toggleAlerts(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _alertsEnabled = value);
    await _db.ref('users/${user.uid}').update({'alerts_enabled': value});
  }

  Future<void> _sendPasswordReset() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;
    final c = AppColorScheme.of(context);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Password reset email sent! Check your inbox."),
          backgroundColor: c.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: c.danger),
        );
      }
    }
  }

  Future<void> _logout() async {
    final c = AppColorScheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Log Out?"),
        content: const Text("You will need to log in again to access tracking."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              "Log Out",
              style: TextStyle(color: c.danger, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────
  Widget _sectionHeader(String title, AppColorScheme c) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            color: c.accent,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 1.4,
          ),
        ),
      );

  Widget _card({required AppColorScheme c, required Widget child}) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withOpacity(0.5)),
        ),
        child: child,
      );

  Widget _divider(AppColorScheme c) =>
      Divider(color: c.border.withOpacity(0.5), height: 1);

  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c    = AppColorScheme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
      ),
      body: ListView(
        children: [

          // ── Profile Card ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.accent, width: 2),
                    color: c.isDark ? Colors.grey[800] : Colors.grey[200],
                  ),
                  child: ClipOval(
                    child: _profileImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: _profileImageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Icon(Icons.person, color: c.textSecondary),
                          )
                        : Icon(Icons.person, color: c.textSecondary),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fullName ?? 'Guardian',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: c.accent),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
                  ).then((_) => _loadUserData()),
                ),
              ],
            ),
          ),

          // ── Account ──────────────────────────────────────────────
          _sectionHeader("Account", c),
          _card(
            c: c,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.person, color: c.textSecondary),
                  title: Text("Account Info", style: TextStyle(color: c.textPrimary)),
                  subtitle: Text("Name, profile image, phone",
                      style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 14, color: c.textSecondary),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
                  ).then((_) => _loadUserData()),
                ),
                _divider(c),
                ListTile(
                  leading: Icon(Icons.lock_reset, color: c.textSecondary),
                  title: Text("Change Password", style: TextStyle(color: c.textPrimary)),
                  subtitle: Text("Send a password reset email",
                      style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  onTap: _sendPasswordReset,
                ),
              ],
            ),
          ),

          // ── Tracking Device ───────────────────────────────────────
          _sectionHeader("Tracking Device", c),
          _card(
            c: c,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.watch,
                        color: _pairedWristbandId != null ? c.success : c.textSecondary,
                        size: 22,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pairedWristbandId != null
                                  ? (_wristbandLabel ?? 'Paired Device')
                                  : "No Device Paired",
                              style: TextStyle(
                                color: _pairedWristbandId != null
                                    ? c.textPrimary
                                    : c.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_pairedWristbandId != null)
                              Text(
                                _pairedWristbandId!,
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 11,
                                  fontFamily: "Courier",
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _pairedWristbandId != null
                              ? c.success.withOpacity(0.15)
                              : c.textSecondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _pairedWristbandId != null ? "Paired" : "None",
                          style: TextStyle(
                            color: _pairedWristbandId != null
                                ? c.success
                                : c.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _divider(c),
                ListTile(
                  leading: Icon(Icons.device_hub, color: c.textSecondary),
                  title: Text(
                    _pairedWristbandId != null
                        ? "Change Paired Device"
                        : "Pair a Wristband",
                    style: TextStyle(color: c.textPrimary),
                  ),
                  subtitle: Text("Link a LoRa tracking wristband",
                      style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  trailing: Icon(Icons.arrow_forward_ios,
                      size: 14, color: c.textSecondary),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WristbandPairingPage()),
                  ).then((_) => _loadUserData()),
                ),
              ],
            ),
          ),

          // ── Alerts ───────────────────────────────────────────────
          _sectionHeader("Alerts & Notifications", c),
          _card(
            c: c,
            child: SwitchListTile(
              secondary:
                  Icon(Icons.notifications_outlined, color: c.textSecondary),
              title: Text("Geofence Breach Alerts",
                  style: TextStyle(color: c.textPrimary)),
              subtitle: Text(
                _alertsEnabled
                    ? "Vibration + log on breach detected"
                    : "Alerts are disabled",
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
              value: _alertsEnabled,
              onChanged: _toggleAlerts,
              activeColor: c.accent,
            ),
          ),

          // ── Appearance ────────────────────────────────────────────
          _sectionHeader("Appearance", c),
          _card(
            c: c,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeNotifier.instance,
              builder: (context, themeMode, _) {
                final isDark = themeMode == ThemeMode.dark;
                return SwitchListTile(
                  secondary: Icon(
                    isDark ? Icons.dark_mode : Icons.light_mode,
                    color: isDark ? c.accent : Colors.amber,
                  ),
                  title: Text(
                    isDark ? "Dark Mode" : "Light Mode",
                    style: TextStyle(color: c.textPrimary),
                  ),
                  subtitle: Text(
                    isDark ? "Switch to light theme" : "Switch to dark theme",
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                  value: isDark,
                  onChanged: (_) => ThemeNotifier.instance.toggle(),
                  activeColor: c.accent,
                );
              },
            ),
          ),

          // ── Session ───────────────────────────────────────────────
          _sectionHeader("Session", c),
          _card(
            c: c,
            child: ListTile(
              leading: Icon(Icons.logout, color: c.danger),
              title: Text(
                "Log Out",
                style:
                    TextStyle(color: c.danger, fontWeight: FontWeight.bold),
              ),
              subtitle: Text("End this guardian session",
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
              onTap: _logout,
            ),
          ),

          const SizedBox(height: 40),
          Center(
            child: Text(
              "Keep Watch v1.0  •  Thesis Capstone",
              style: TextStyle(
                  color: c.textSecondary.withOpacity(0.4), fontSize: 11),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}