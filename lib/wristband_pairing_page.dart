import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WRISTBAND PAIRING PAGE  —  multi-device support
//
// Firebase structure (new):
//   users/{uid}/paired_wristbands/{deviceId}/label   String
//
// Rules enforced:
//   • Device MUST exist in live_location/{id} (verified) before pairing
//   • Same device cannot be added twice
//   • Old single-device field is auto-migrated on first load
// ─────────────────────────────────────────────────────────────────────────────
class WristbandPairingPage extends StatefulWidget {
  const WristbandPairingPage({super.key});

  @override
  State<WristbandPairingPage> createState() => _WristbandPairingPageState();
}

class _WristbandPairingPageState extends State<WristbandPairingPage>
    with SingleTickerProviderStateMixin {
  final _idController    = TextEditingController();
  final _labelController = TextEditingController();

  /// All paired devices for this account: deviceId → label
  Map<String, String> _pairedDevices = {};

  bool _isLoading    = false;
  bool _isVerifying  = false;
  // 'found' | 'not_found' | 'already_paired' | null
  String? _verifyStatus;

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
    _loadPairedDevices();
  }

  @override
  void dispose() {
    _idController.dispose();
    _labelController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // LOAD — reads new structure, migrates old if needed
  // ─────────────────────────────────────────────────────────────────
  Future<void> _loadPairedDevices() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await _db.ref('users/${user.uid}').get();
    if (!snap.exists || !mounted) return;

    final data = snap.value as Map? ?? {};
    final Map<String, String> loaded = {};

    // New multi-device structure
    final newMap = data['paired_wristbands'];
    if (newMap is Map) {
      newMap.forEach((k, v) {
        final id    = k.toString();
        final label = (v is Map ? v['label'] : v)?.toString() ?? 'Wristband';
        loaded[id]  = label;
      });
    }

    // Migrate old single-device field on first run — and delete it so it never haunts us again
    if (loaded.isEmpty) {
      final oldId    = data['paired_wristband']?.toString();
      final oldLabel = data['wristband_label']?.toString() ?? 'Wristband';
      if (oldId != null && oldId.isNotEmpty) {
        loaded[oldId] = oldLabel;
        // Write to new structure AND delete the old fields so migration never re-runs
        await _db.ref('users/${user.uid}/paired_wristbands/$oldId').set({'label': oldLabel});
        await _db.ref('users/${user.uid}').update({
          'paired_wristband': null,
          'wristband_label': null,
        });
      }
    }

    if (mounted) setState(() => _pairedDevices = loaded);
  }

  // ─────────────────────────────────────────────────────────────────
  // VERIFY — checks live_location/{id} exists in the database
  // ─────────────────────────────────────────────────────────────────
  Future<void> _verifyDevice() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;

    // Guard: already paired to this account?
    if (_pairedDevices.containsKey(id)) {
      setState(() => _verifyStatus = 'already_paired');
      return;
    }

    setState(() {
      _isVerifying  = true;
      _verifyStatus = null;
    });

    try {
      final snap = await _db.ref('live_location/$id').get();
      if (mounted) {
        setState(() {
          _verifyStatus = snap.exists ? 'found' : 'not_found';
          _isVerifying  = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase();
        final isPermissionDenied =
            msg.contains('permission') || msg.contains('denied');
        setState(() {
          _verifyStatus = isPermissionDenied ? 'permission_denied' : 'error';
          _isVerifying  = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // PAIR — only callable when _verifyStatus == 'found'
  // ─────────────────────────────────────────────────────────────────
  Future<void> _pairDevice() async {
    if (_verifyStatus != 'found') return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final id    = _idController.text.trim();
    final label = _labelController.text.trim().isEmpty
        ? 'Wristband ${_pairedDevices.length + 1}'
        : _labelController.text.trim();

    if (id.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      await _db
          .ref('users/${user.uid}/paired_wristbands/$id')
          .set({'label': label});

      if (mounted) {
        setState(() {
          _pairedDevices[id] = label;
          _isLoading         = false;
          _verifyStatus      = null;
        });
        _idController.clear();
        _labelController.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("'$label' paired successfully!"),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Failed to pair: $e"),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // UNPAIR a specific device
  // ─────────────────────────────────────────────────────────────────
  Future<void> _unpairDevice(String deviceId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final c     = AppColorScheme.of(context);
    final label = _pairedDevices[deviceId] ?? deviceId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text("Unpair Device?",
            style: TextStyle(color: c.textPrimary)),
        content: Text(
          "Remove '$label' from this account?\nTracking will stop. You can re-pair at any time.",
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel", style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Unpair",
                style: TextStyle(
                    color: c.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    await _db.ref('users/${user.uid}/paired_wristbands/$deviceId').remove();

    // Also wipe the legacy single-device fields if they match this device,
    // so they can never ghost the device back after unpairing
    final legacySnap =
        await _db.ref('users/${user.uid}/paired_wristband').get();
    if (legacySnap.value?.toString() == deviceId) {
      await _db.ref('users/${user.uid}').update({
        'paired_wristband': null,
        'wristband_label':  null,
      });
    }

    if (mounted) {
      setState(() {
        _pairedDevices.remove(deviceId);
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("'$label' unpaired."),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // QR scanned — populate Manual tab and switch to it
  // ─────────────────────────────────────────────────────────────────
  void _onQrScanned(String rawValue) {
    String deviceId = rawValue.trim();
    if (deviceId.startsWith('{')) {
      try {
        final stripped =
            deviceId.replaceAll(RegExp(r'[{}"\\s]'), '').split(',');
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
      _verifyStatus      = null;
    });
    _tabController.animateTo(0);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Scanned: $deviceId — verify then tap Pair"),
      backgroundColor: AppColors.success,
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────────────
  // QR dialog for an existing paired device
  // ─────────────────────────────────────────────────────────────────
  void _showQrDialog(String deviceId, String label) {
    final c = AppColorScheme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text("Scan on another device to pair instantly",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: QrImageView(
                  data: deviceId,
                  version: QrVersions.auto,
                  size: 200,
                  eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: deviceId));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Device ID copied"),
                      duration: Duration(seconds: 1)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: c.background,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(deviceId,
                          style: TextStyle(
                              color: c.accent,
                              fontFamily: "Courier",
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      const SizedBox(width: 8),
                      Icon(Icons.copy, color: c.textSecondary, size: 14),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child:
                      Text("Close", style: TextStyle(color: c.textSecondary)),
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
    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text("Device Pairing"),
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: c.accent,
          labelColor: c.accent,
          unselectedLabelColor: c.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.keyboard), text: "Manual"),
            Tab(icon: Icon(Icons.qr_code_scanner), text: "Scan QR"),
          ],
        ),
      ),
      body: Column(
        children: [

          // ── Paired devices list ────────────────────────────────────
          if (_pairedDevices.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Row(
                      children: [
                        Icon(Icons.devices, color: c.accent, size: 15),
                        const SizedBox(width: 8),
                        Text(
                          "PAIRED DEVICES",
                          style: TextStyle(
                              color: c.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_pairedDevices.length}',
                            style: TextStyle(
                                color: c.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // One row per device
                  ..._pairedDevices.entries.map((entry) {
                    final id    = entry.key;
                    final label = entry.value;
                    return Column(
                      children: [
                        Divider(
                            color: c.border.withOpacity(0.35), height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.watch, color: c.success, size: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(label,
                                        style: TextStyle(
                                            color: c.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                    Text(id,
                                        style: TextStyle(
                                            color: c.textSecondary,
                                            fontFamily: "Courier",
                                            fontSize: 11)),
                                  ],
                                ),
                              ),
                              // Paired badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: c.success.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text("Paired",
                                    style: TextStyle(
                                        color: c.success,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ),
                              // QR button
                              IconButton(
                                icon: Icon(Icons.qr_code,
                                    color: c.accent, size: 20),
                                tooltip: "Show QR",
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    _showQrDialog(id, label),
                              ),
                              // Unpair button
                              IconButton(
                                icon: Icon(Icons.link_off,
                                    color: c.danger, size: 20),
                                tooltip: "Unpair",
                                visualDensity: VisualDensity.compact,
                                onPressed: _isLoading
                                    ? null
                                    : () => _unpairDevice(id),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),

          // ── Tab views ──────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ManualEntryTab(
                  idController:    _idController,
                  labelController: _labelController,
                  verifyStatus:    _verifyStatus,
                  isVerifying:     _isVerifying,
                  isLoading:       _isLoading,
                  onVerify:        _verifyDevice,
                  onPair:          _pairDevice,
                  onIdChanged: (_) =>
                      setState(() => _verifyStatus = null),
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
    final c = AppColorScheme.of(context);
    // Pair is only enabled after a successful verify
    final bool canPair =
        verifyStatus == 'found' && idController.text.trim().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            "Enter the wristband Device ID from your TTN console, "
            "then tap Verify. The device must have transmitted data "
            "at least once before it can be paired.",
            style: TextStyle(
                color: c.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),

          // Label field
          TextField(
            controller: labelController,
            style: TextStyle(color: c.textPrimary),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: "Device Label (optional)",
              hintText: "e.g., Child's Wristband",
              prefixIcon: Icon(Icons.label_outline, color: c.accent),
            ),
          ),
          const SizedBox(height: 12),

          // Device ID field
          TextField(
            controller: idController,
            style: TextStyle(
                color: c.textPrimary, fontFamily: "Courier"),
            onChanged: onIdChanged,
            decoration: InputDecoration(
              labelText: "Wristband Device ID *",
              hintText: "e.g., eui-70b3d57ed005f2a9",
              prefixIcon: Icon(Icons.nfc, color: c.accent),
              suffixIcon: verifyStatus == 'found'
                  ? Icon(Icons.check_circle, color: c.success)
                  : (verifyStatus == 'not_found' ||
                          verifyStatus == 'already_paired' ||
                          verifyStatus == 'permission_denied' ||
                          verifyStatus == 'error')
                      ? Icon(Icons.cancel, color: c.danger)
                      : null,
            ),
          ),

          // Status messages
          if (verifyStatus == 'found')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text("✓ Device found in database. Ready to pair.",
                  style: TextStyle(color: c.success, fontSize: 13)),
            ),
          if (verifyStatus == 'not_found')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "✗ Device not found. Make sure it's powered on and has "
                "sent at least one data packet to TTN.",
                style: TextStyle(
                    color: c.danger, fontSize: 13, height: 1.4),
              ),
            ),
          if (verifyStatus == 'already_paired')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "⚠ This device is already paired to your account.",
                style: TextStyle(color: Colors.orange, fontSize: 13),
              ),
            ),
          if (verifyStatus == 'permission_denied')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.lock_outline, color: Colors.orange, size: 15),
                      const SizedBox(width: 6),
                      Text("Firebase permission denied",
                          style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      "Your database rules only allow reading your own UID path. "
                      "Update your RTDB rules to allow any authenticated user to "
                      "read live_location:\n\n"
                      '"live_location": { ".read": "auth != null" }',
                      style: TextStyle(
                          color: Colors.orange.shade200,
                          fontSize: 12,
                          height: 1.5,
                          fontFamily: "Courier"),
                    ),
                  ],
                ),
              ),
            ),
          if (verifyStatus == 'error')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "✗ Could not reach the database. Check your connection and try again.",
                style: TextStyle(color: c.danger, fontSize: 13, height: 1.4),
              ),
            ),

          const SizedBox(height: 16),

          // Verify button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isVerifying ? null : onVerify,
              icon: isVerifying
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.accent))
                  : Icon(Icons.search, color: c.accent),
              label: Text(
                isVerifying ? "Verifying…" : "Verify Device",
                style: TextStyle(color: c.accent),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.accent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Pair button — greyed out until verified
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message:
                  canPair ? "" : "Verify the device first before pairing",
              child: ElevatedButton.icon(
                onPressed: (isLoading || !canPair) ? null : onPair,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.link, color: Colors.black),
                label: Text(
                  isLoading ? "Pairing…" : "Pair This Device",
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canPair
                      ? AppColors.accent
                      : AppColors.accent.withOpacity(0.3),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Help card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: c.border.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.help_outline,
                        color: c.textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Text("Where to find the Device ID",
                        style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "1. Log into your TTN (The Things Network) console\n"
                  "2. Navigate to Application > End Devices\n"
                  "3. Copy the Device ID (not the EUI)\n"
                  "4. Paste it above and tap Verify\n\n"
                  "The wristband must have sent at least one packet\n"
                  "before it appears in the database.",
                  style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                      height: 1.6),
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
  bool _scanned         = false;
  bool _torchOn         = false;
  bool _hasPermission   = false;
  bool _cameraLoading   = false;
  CameraFacing _facing  = CameraFacing.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startController();
    setState(() => _hasPermission = true);
  }

  Future<void> _startController() async {
    setState(() => _cameraLoading = true);
    
    // Properly dispose old controller first
    final old = _controller;
    _controller = null;
    if (mounted) setState(() {});
    
    try {
      await old?.dispose();
    } catch (_) {}
    
    // Small delay to let camera hardware release
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (!mounted) return;

    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: _facing,
      torchEnabled: false,
      autoStart: true,
    );

    try {
      await controller.start();
      if (mounted) {
        setState(() {
          _controller     = controller;
          _cameraLoading  = false;
        });
      } else {
        controller.dispose();
      }
    } catch (_) {
      // Back camera unavailable — fall back to front
      controller.dispose();
      if (_facing == CameraFacing.back && mounted) {
        setState(() {
          _facing        = CameraFacing.front;
          _cameraLoading = false;
        });
        _startController();
      } else {
        if (mounted) setState(() => _cameraLoading = false);
      }
    }
  }

  void _flipCamera() {
    setState(() {
      _facing  = _facing == CameraFacing.back
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
    if (state == AppLifecycleState.resumed)  _controller!.start();
    if (state == AppLifecycleState.paused)   _controller!.stop();
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

  // Pick a QR image from gallery and decode it via mobile_scanner
  Future<void> _pickImageAndScan() async {
    final picker = ImagePicker();
    final XFile? picked =
        await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    // Pause live camera while processing
    _controller?.stop();

    final result = await _controller?.analyzeImage(picked.path);

    if (!mounted) return;

    final value = result?.barcodes.firstOrNull?.rawValue;
    if (value != null && value.isNotEmpty) {
      setState(() => _scanned = true);
      widget.onScanned(value);
    } else {
      // Resume camera and show error
      _controller?.start();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "No QR code found in that image. Try a clearer photo."),
          backgroundColor: AppColors.danger,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission || _controller == null || _cameraLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 16),
            Text("Starting camera…",
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera feed
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
          errorBuilder: (context, error, child) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off,
                    color: Colors.white38, size: 48),
                const SizedBox(height: 12),
                Text("Camera error: ${error.errorCode.name}",
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _startController,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black),
                  child: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),

        // Scan frame
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

        // Top instruction
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.72),
                  Colors.transparent
                ],
              ),
            ),
            child: const Text(
              "Point the camera at the QR code, or tap 🖼 to upload an image",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.78),
                  Colors.transparent
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                _MapFab(
                  icon: Icons.flip_camera_ios,
                  iconColor: Colors.white,
                  tooltip: _facing == CameraFacing.back
                      ? "Switch to front camera"
                      : "Switch to back / laptop camera",
                  onTap: _flipCamera,
                ),
                const SizedBox(width: 12),
                // Upload QR from gallery
                _MapFab(
                  icon: Icons.photo_library_outlined,
                  iconColor: Colors.white,
                  tooltip: "Upload QR code image",
                  onTap: _pickImageAndScan,
                ),
                if (_scanned) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _resetScanner,
                    icon: const Icon(Icons.qr_code_scanner,
                        color: Colors.black),
                    label: const Text("Scan Again",
                        style: TextStyle(color: Colors.black)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Success overlay
        if (_scanned)
          Container(
            color: AppColors.success.withOpacity(0.15),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 80),
                  SizedBox(height: 12),
                  Text("QR Code Scanned!",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text("Review the device ID in the Manual tab",
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCorners() => [
        _Corner(top: true,  left: true),
        _Corner(top: true,  left: false),
        _Corner(top: false, left: true),
        _Corner(top: false, left: false),
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
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
    const size      = 22.0;
    const thickness = 3.5;
    const color     = AppColors.accent;
    return Positioned(
      top:    top  ? 0 : null,
      bottom: top  ? null : 0,
      left:   left ? 0 : null,
      right:  left ? null : 0,
      child: CustomPaint(
        size: const Size(size, size),
        painter: _CornerPainter(
          topLeft:     top && left,
          topRight:    top && !left,
          bottomLeft:  !top && left,
          bottomRight: !top && !left,
          color:       color,
          thickness:   thickness,
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
      ..color       = color
      ..strokeWidth = thickness
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.square;
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (topLeft)     { path.moveTo(0, h); path.lineTo(0, 0); path.lineTo(w, 0); }
    if (topRight)    { path.moveTo(0, 0); path.lineTo(w, 0); path.lineTo(w, h); }
    if (bottomLeft)  { path.moveTo(0, 0); path.lineTo(0, h); path.lineTo(w, h); }
    if (bottomRight) { path.moveTo(w, 0); path.lineTo(w, h); path.lineTo(0, h); }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}