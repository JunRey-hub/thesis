import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';
import 'login_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ONBOARDING  —  shown only on first launch
// Requires:  shared_preferences: ^2.2.0  (already needed for theme)
// ─────────────────────────────────────────────────────────────────────────────
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingData(
      icon: Icons.security,
      useAppIcon: true,
      title: "Welcome to\nKeep Watch",
      body:
          "A real-time safety tracking system for guardians. "
          "Monitor your tracked person's location, set safe zones, "
          "and get instant alerts — all from your phone.",
      isFirst: true,
    ),
    _OnboardingData(
      icon: Icons.watch,
      title: "Pair Your\nWristband",
      body:
          "Keep Watch works with a LoRa GPS wristband that sends "
          "live location data. After logging in, go to "
          "Settings → Device Pairing to link your device by ID or QR code.",
    ),
    _OnboardingData(
      icon: Icons.fence,
      title: "Set Your\nSafe Zone",
      body:
          "Draw a geofence around any area — home, school, or a park. "
          "Choose Dynamic mode to follow your own location, or Fixed "
          "mode to pin it anywhere on the map. You'll be alerted the moment "
          "the wristband crosses the boundary.",
      isLast: true,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Skip button ────────────────────────────────────────
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 20),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    "Skip",
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),

            // ── Pages ──────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (context, index) =>
                    _OnboardingSlide(data: _pages[index], scheme: c),
              ),
            ),

            // ── Dots ───────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? c.accent : c.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 32),

            // ── Action button ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isLast ? "Get Started" : "Next",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isLast ? Icons.check_circle_outline : Icons.arrow_forward,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _OnboardingData {
  final IconData icon;
  final String title;
  final String body;
  final bool isFirst;
  final bool isLast;
  final bool useAppIcon;   // use ico.png instead of icon

  const _OnboardingData({
    required this.icon,
    required this.title,
    required this.body,
    this.isFirst = false,
    this.isLast = false,
    this.useAppIcon = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SINGLE SLIDE
// ─────────────────────────────────────────────────────────────────────────────
class _OnboardingSlide extends StatelessWidget {
  final _OnboardingData data;
  final AppColorScheme scheme;

  const _OnboardingSlide({
    required this.data,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Icon bubble ──────────────────────────────────────────
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.accent.withOpacity(0.1),
              border: Border.all(
                color: scheme.accent.withOpacity(0.25),
                width: 2,
              ),
            ),
            child: data.useAppIcon
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Image.asset(
                      'assets/icon/onboarding.png',
                      fit: BoxFit.contain,
                    ),
                  )
                : Icon(
                    data.icon,
                    size: 60,
                    color: scheme.accent,
                  ),
          ),

          const SizedBox(height: 40),

          // ── Title ────────────────────────────────────────────────
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 20),

          // ── Body ─────────────────────────────────────────────────
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.textSecondary,
              fontSize: 15,
              height: 1.65,
            ),
          ),

          // ── Feature chips on first slide ─────────────────────────
          if (data.isFirst) ...[
            const SizedBox(height: 32),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _Chip(label: "Live GPS", icon: Icons.gps_fixed, scheme: scheme),
                _Chip(label: "Geofencing", icon: Icons.fence, scheme: scheme),
                _Chip(label: "LoRa Wristband", icon: Icons.watch, scheme: scheme),
                _Chip(label: "Instant Alerts", icon: Icons.notifications_active, scheme: scheme),
              ],
            ),
          ],

          // ── Step indicators on middle/last slides ─────────────────
          if (!data.isFirst) ...[
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.border.withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 15,
                    color: scheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    data.isLast
                        ? "You can adjust this anytime in the app"
                        : "Find this in Settings after logging in",
                    style: TextStyle(
                      color: scheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final AppColorScheme scheme;

  const _Chip({
    required this.label,
    required this.icon,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.border.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: scheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}