import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'app_colors.dart';
import 'login_page.dart';
import 'onboarding_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME NOTIFIER  —  global ValueNotifier, accessible anywhere via ThemeNotifier.instance
// ─────────────────────────────────────────────────────────────────────────────
class ThemeNotifier extends ValueNotifier<ThemeMode> {
  ThemeNotifier._() : super(ThemeMode.dark);

  static final ThemeNotifier instance = ThemeNotifier._();

  static const _prefKey = 'theme_mode';

  /// Load saved preference on startup
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved == 'light') {
      value = ThemeMode.light;
    } else {
      value = ThemeMode.dark;
    }
  }

  /// Toggle and persist
  Future<void> toggle() async {
    value = value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, value == ThemeMode.dark ? 'dark' : 'light');
  }

  bool get isDark => value == ThemeMode.dark;
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Load saved theme before the first frame
  await ThemeNotifier.instance.loadFromPrefs();

  // Check if onboarding was completed
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_complete') ?? false;

  runApp(MyApp(showOnboarding: !onboardingDone));
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT APP
// ─────────────────────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  final bool showOnboarding;

  const MyApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    // Rebuild MaterialApp whenever the theme notifier changes
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Keep Watch',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: showOnboarding ? const OnboardingPage() : const LoginPage(),
        );
      },
    );
  }
}