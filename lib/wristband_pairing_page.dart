import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WRISTBAND PAIRING PAGE
// pubspec.yaml dependencies needed:
//   mobile_scanner: ^5.0.0
//   qr_flutter: ^4.1.0
// ─────────────────────────────────────────────────────────────────────────────
class WristbandPairingPage extends StatefulWidget {
  const WristbandPairingPage({super.key});

  @override
  State<WristbandPairingPage> createState() => _WristbandPairingPageState();
}

class _WristbandPairingPageState extends State<WristbandPairingPage>
    with SingleTickerProviderStateMixin {
  final _idController = TextEditingController();
  final _labelController = TextEditingController();

  bool _isLoading = false;
  bool _isVerifying = false;
  String? _currentPairedId;
  String? _currentLabel;
  String? _verifyStatus; // 'found' | 'not_found' | null

  late final TabController _tabController;

  final _db = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL:
        'https://keep-watch-d3e89-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCurrentPairing();
  }

  @override
  void dispose() {
    _idController.dispose();
    _labelController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  Future<void> _loadCurrentPairing() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await _db.ref('users/${user.uid}').get();
    if (snap.exists && mounted) {
      final data = snap.value as Map? ?? {};
      setState(() {
        _currentPairedId = data['paired_wristband']?.toString();
        _currentLabel = data['wristband_label']?.toString() ?? 'Unnamed Device';
        if (_currentPairedId != null) {
          _idController.text = _currentPairedId!;
          _labelController.text = _currentLabel!;
        }
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────
  Future<void> _verifyDevice() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _verifyStatus = null;
    });

    try {
      final snap = await _db.ref('live_location/$id').get();
      if (mounted) {
        setState(() {
          _verifyStatus = snap.exists ? 'found' : 'not_found';
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  Future<void> _pairDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final id = _idController.text.trim();
    final label = _labelController.text.trim().isEmpty
        ? 'Wristband'
        : _labelController.text.trim();
    if (id.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      await _db.ref('users/${user.uid}').update({
        'paired_wristband': id,
        'wristband_label': label,
      });

      if (mounted) {
        setState(() {
          _currentPairedId = id;
          _currentLabel = label;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Wristband paired successfully!"),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to pair: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  Future<void> _unpairDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text("Unpair Device?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "This will stop all tracking. You can re-pair at any time.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Unpair",
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    await _db.ref('users/${user.uid}').update({
      'paired_wristband': null,
      'wristband_label': null,
    });

    if (mounted) {
      setState(() {
        _currentPairedId = null;
        _currentLabel = null;
        _idController.clear();
        _labelController.clear();
        _verifyStatus = null;
        _isLoading = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Called when QR is successfully scanned — fills manual tab fields
  // ─────────────────────────────────────────────────────────────────
  void _onQrScanned(String rawValue) {
    String deviceId = rawValue.trim();

    // Support simple JSON: {"device_id":"dev-001"}
    if (deviceId.startsWith('{')) {
      try {
        final stripped = deviceId
            .replaceAll(RegExp(r'[{}"\\s]'), '')
            .split(',');
        for (final part in stripped) {
          final kv = part.split(':');
          if (kv.length == 2 && kv[0].contains('device_id')) {
            deviceId = kv[1];
            break;
          }
        }
      } catch (_) {}
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _idController.text = deviceId;
      _verifyStatus = null;
    });

    // Switch to Manual tab so user can confirm + add label
    _tabController.animateTo(0);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Scanned: $deviceId — confirm and tap Pair"),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  void _showQrDialog(String deviceId) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Device QR Code",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Scan this on another device to pair instantly",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              // White background so QR is scannable
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: deviceId,
                  version: QrVersions.auto,
                  size: 200,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Device ID chip
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: deviceId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Device ID copied"),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        deviceId,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontFamily: "Courier",
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.copy, color: Colors.grey, size: 14),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Close",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Device Pairing"),
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.keyboard), text: "Manual"),
            Tab(icon: Icon(Icons.qr_code_scanner), text: "Scan QR"),
          ],
        ),
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Currently paired banner ────────────────────────────
          if (_currentPairedId != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.success.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.watch, color: AppColors.success, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentLabel ?? 'Paired Device',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _currentPairedId!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: "Courier",
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Show QR of current device
                  IconButton(
                    icon: const Icon(Icons.qr_code, color: AppColors.accent),
                    tooltip: "Show QR Code",
                    onPressed: () => _showQrDialog(_currentPairedId!),
                  ),
                  IconButton(
                    icon: const Icon(Icons.link_off, color: AppColors.danger),
                    tooltip: "Unpair",
                    onPressed: _isLoading ? null : _unpairDevice,
                  ),
                ],
              ),
            ),

          // ── Tab views ─────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ManualEntryTab(
                  idController: _idController,
                  labelController: _labelController,
                  verifyStatus: _verifyStatus,
                  isVerifying: _isVerifying,
                  isLoading: _isLoading,
                  onVerify: _verifyDevice,
                  onPair: _pairDevice,
                  onIdChanged: (_) => setState(() => _verifyStatus = null),
                ),
                _QrScannerTab(onScanned: _onQrScanned),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MANUAL ENTRY TAB
// ─────────────────────────────────────────────────────────────────────────────
class _ManualEntryTab extends StatelessWidget {
  final TextEditingController idController;
  final TextEditingController labelController;
  final String? verifyStatus;
  final bool isVerifying;
  final bool isLoading;
  final VoidCallback onVerify;
  final VoidCallback onPair;
  final ValueChanged<String> onIdChanged;

  const _ManualEntryTab({
    required this.idController,
    required this.labelController,
    required this.verifyStatus,
    required this.isVerifying,
    required this.isLoading,
    required this.onVerify,
    required this.onPair,
    required this.onIdChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text(
            "Enter the wristband Device ID from your TTN console, "
            "or use the Scan QR tab for instant entry.",
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Label
          TextField(
            controller: labelController,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: "Device Label (optional)",
              labelStyle: TextStyle(color: Colors.grey),
              hintText: "e.g., Child's Wristband",
              hintStyle: TextStyle(color: Colors.white24),
              prefixIcon: Icon(Icons.label_outline, color: AppColors.accent),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Device ID
          TextField(
            controller: idController,
            style: const TextStyle(color: Colors.white, fontFamily: "Courier"),
            onChanged: onIdChanged,
            decoration: InputDecoration(
              labelText: "Wristband Device ID *",
              labelStyle: const TextStyle(color: Colors.grey),
              hintText: "e.g., dev-001",
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.nfc, color: AppColors.accent),
              suffixIcon: verifyStatus == 'found'
                  ? const Icon(Icons.check_circle, color: AppColors.success)
                  : verifyStatus == 'not_found'
                      ? const Icon(Icons.cancel, color: AppColors.danger)
                      : null,
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),

          if (verifyStatus == 'found')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "✓ Device found. Ready to pair.",
                style: TextStyle(color: AppColors.success, fontSize: 13),
              ),
            ),
          if (verifyStatus == 'not_found')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "⚠ Device not found. Power it on and ensure it has sent data.",
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isVerifying ? null : onVerify,
              icon: isVerifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : const Icon(Icons.search, color: AppColors.accent),
              label: Text(
                isVerifying ? "Verifying…" : "Verify Device",
                style: const TextStyle(color: AppColors.accent),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (isLoading || idController.text.trim().isEmpty) ? null : onPair,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.link, color: Colors.black),
              label: Text(
                isLoading ? "Pairing…" : "Pair This Device",
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.help_outline, color: AppColors.textGrey, size: 18),
                    SizedBox(width: 8),
                    Text(
                      "Where to find the Device ID",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  "1. Log into your TTN (The Things Network) console\n"
                  "2. Navigate to Application > End Devices\n"
                  "3. Copy the Device ID (not the EUI)\n"
                  "4. Paste it above and tap Verify\n\n"
                  "Tip: Use the Scan QR tab for faster pairing.",
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QR SCANNER TAB
// ─────────────────────────────────────────────────────────────────────────────
class _QrScannerTab extends StatefulWidget {
  final ValueChanged<String> onScanned;
  const _QrScannerTab({required this.onScanned});

  @override
  State<_QrScannerTab> createState() => _QrScannerTabState();
}

class _QrScannerTabState extends State<_QrScannerTab>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _scanned = false;
  bool _torchOn = false;
  bool _hasPermission = false;
  bool _permissionDenied = false;
  // Start with front camera so it works on both phone (front) and laptop (webcam)
  CameraFacing _facing = CameraFacing.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startController();
    setState(() => _hasPermission = true);
  }

  void _startController() {
    _controller?.dispose();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: _facing,
      torchEnabled: false,
      autoStart: true,
    );
    // Explicitly start in case autoStart doesn't fire
    _controller!.start().catchError((_) {
      // If back camera fails (e.g. on laptop), flip to front
      if (_facing == CameraFacing.back && mounted) {
        setState(() => _facing = CameraFacing.front);
        _startController();
      }
    });
    if (mounted) setState(() {});
  }

  void _flipCamera() {
    setState(() {
      _facing = _facing == CameraFacing.back
          ? CameraFacing.front
          : CameraFacing.back;
      _scanned = false;
      _torchOn = false;
    });
    _startController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.resumed) {
      _controller!.start();
    } else if (state == AppLifecycleState.paused) {
      _controller!.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  void _resetScanner() {
    setState(() => _scanned = false);
    _controller?.start();
  }

  @override
  Widget build(BuildContext context) {
    // ── Permission denied state ──────────────────────────────────
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined, color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              const Text(
                "Camera permission denied",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                "Please enable camera access in your device settings, then return here.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _startController(),
                icon: const Icon(Icons.refresh),
                label: const Text("Try Again"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Loading / waiting for permission ────────────────────────
    if (!_hasPermission || _controller == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 16),
            Text("Starting camera…", style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // ── Camera feed ──────────────────────────────────────────
        MobileScanner(
          controller: _controller!,
          onDetect: (capture) {
            if (_scanned) return;
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value != null && value.isNotEmpty) {
              setState(() => _scanned = true);
              _controller?.stop();
              widget.onScanned(value);
            }
          },
          errorBuilder: (context, error, child) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off, color: Colors.white38, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    "Camera error: ${error.errorCode.name}",
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _startController,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text("Retry"),
                  ),
                ],
              ),
            );
          },
        ),

        // ── Scan frame ───────────────────────────────────────────
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.accent, width: 2.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(children: _buildCorners()),
          ),
        ),

        // ── Top instruction ──────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.72),
                  Colors.transparent,
                ],
              ),
            ),
            child: const Text(
              "Point the camera at the wristband QR code",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        // ── Bottom controls ──────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.78),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Torch toggle
                _MapFab(
                  icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                  iconColor: _torchOn ? Colors.yellow : Colors.white,
                  tooltip: "Toggle flashlight",
                  onTap: () {
                    _controller?.toggleTorch();
                    setState(() => _torchOn = !_torchOn);
                  },
                ),
                const SizedBox(width: 12),
                // Camera flip (front ↔ back / webcam switch)
                _MapFab(
                  icon: Icons.flip_camera_ios,
                  iconColor: Colors.white,
                  tooltip: _facing == CameraFacing.back
                      ? "Switch to front camera"
                      : "Switch to back / laptop camera",
                  onTap: _flipCamera,
                ),
                if (_scanned) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _resetScanner,
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.black),
                    label: const Text(
                      "Scan Again",
                      style: TextStyle(color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── Success overlay ──────────────────────────────────────
        if (_scanned)
          Container(
            color: AppColors.success.withOpacity(0.15),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 80,
                  ),
                  SizedBox(height: 12),
                  Text(
                    "QR Code Scanned!",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "Review the device ID in the Manual tab",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCorners() {
    return [
      _Corner(top: true, left: true),
      _Corner(top: true, left: false),
      _Corner(top: false, left: true),
      _Corner(top: false, left: false),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String tooltip;
  final VoidCallback onTap;

  const _MapFab({
    required this.icon,
    required this.iconColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final bool top;
  final bool left;

  const _Corner({required this.top, required this.left});

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    const thickness = 3.5;
    const color = AppColors.accent;

    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      child: CustomPaint(
        size: const Size(size, size),
        painter: _CornerPainter(
          topLeft: top && left,
          topRight: top && !left,
          bottomLeft: !top && left,
          bottomRight: !top && !left,
          color: color,
          thickness: thickness,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool topLeft, topRight, bottomLeft, bottomRight;
  final Color color;
  final double thickness;

  const _CornerPainter({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.color,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final w = size.width;
    final h = size.height;
    final path = Path();

    if (topLeft) {
      path.moveTo(0, h);
      path.lineTo(0, 0);
      path.lineTo(w, 0);
    }
    if (topRight) {
      path.moveTo(0, 0);
      path.lineTo(w, 0);
      path.lineTo(w, h);
    }
    if (bottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, h);
      path.lineTo(w, h);
    }
    if (bottomRight) {
      path.moveTo(w, 0);
      path.lineTo(w, h);
      path.lineTo(0, h);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}