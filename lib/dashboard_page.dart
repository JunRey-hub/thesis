import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps;
import 'package:geolocator/geolocator.dart';
import 'app_colors.dart';
import 'settings_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCAFFOLD
// ─────────────────────────────────────────────────────────────────────────────
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  String? _focusDeviceId;   // set when tapping a device in Target Status

  // ── Location State ────────────────────────────────────────────────
  StreamSubscription<Position>? _positionStream;
  google_maps.LatLng _myLocation = const google_maps.LatLng(9.3068, 123.3054);
  Map<String, google_maps.LatLng> _teamLocations = {};

  // ── Geofence State ────────────────────────────────────────────────
  /// 'dynamic' = geofence follows guardian; 'fixed' = geofence stays put
  String _geofenceMode = 'dynamic';
  double _geofenceRadius = 50.0;
  google_maps.LatLng _fixedCenter = const google_maps.LatLng(9.3068, 123.3054);

  google_maps.LatLng get _activeCenter =>
      _geofenceMode == 'fixed' ? _fixedCenter : _myLocation;

  // ── Wristband Status ──────────────────────────────────────────────
  /// All paired devices: deviceId → label
  Map<String, String> _pairedDevices = {};
  /// Per-device online flag
  Map<String, bool> _deviceOnline = {};
  /// Per-device battery %
  Map<String, int?> _deviceBattery = {};
  /// Per-device speed km/h
  Map<String, double?> _deviceSpeed = {};
  /// Per-device last seen
  Map<String, DateTime?> _deviceLastSeen = {};
  /// Live listeners keyed by deviceId
  final Map<String, StreamSubscription> _deviceSubs = {};

  /// Staleness timer — ticks every 10s to re-evaluate which devices are stale
  Timer? _stalenessTimer;

  /// Per-device breach vibration timers — vibrate every 5s while outside geofence
  final Map<String, Timer> _breachTimers = {};

  /// A device is considered stale/disconnected if no packet in this duration
  static const _staleThreshold = Duration(seconds: 60);

  // Convenience getters (first device, used by status card / geofence)
  String? get _pairedWristbandId =>
      _pairedDevices.isEmpty ? null : _pairedDevices.keys.first;
  String? get _wristbandLabel =>
      _pairedDevices.isEmpty ? null : _pairedDevices.values.first;
  bool get _isWristbandOnline {
    if (_pairedDevices.isEmpty) return false;
    final id = _pairedDevices.keys.first;
    final isOnline = _deviceOnline[id] ?? false;
    if (!isOnline) return false;
    final lastSeen = _deviceLastSeen[id];
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen) <= _staleThreshold;
  }
  int? get _wristbandBattery =>
      _pairedDevices.isEmpty ? null : _deviceBattery[_pairedDevices.keys.first];
  DateTime? get _wristbandLastSeen =>
      _pairedDevices.isEmpty ? null : _deviceLastSeen[_pairedDevices.keys.first];

  // ── Logs & Alerts ─────────────────────────────────────────────────
  List<String> _activityLogs = [];
  Map<String, bool> _previousUserStatus = {};
  bool _alertsEnabled = true;

  // ── Profile ───────────────────────────────────────────────────────
  String? _profileImageUrl;

  final _db = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL: 'https://keep-watch-d3e89-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );

  // ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadUserSettings();
    _startTracking();
    _monitorConnection();
    _addLog("Guardian Authorized. System Online.");

    // Staleness timer — refreshes UI every 10s so stale devices update promptly
    _stalenessTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _stalenessTimer?.cancel();
    for (final t in _breachTimers.values) t.cancel();
    _breachTimers.clear();
    for (final sub in _deviceSubs.values) sub.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // LOAD USER SETTINGS & PROFILE  (uses Realtime Database — not Firestore)
  // ─────────────────────────────────────────────────────────────────
  Future<void> _loadUserSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap = await _db.ref('users/${user.uid}').get();
      if (!snap.exists || !mounted) return;

      final data = snap.value as Map? ?? {};

      // Cancel old device listeners before reloading
      for (final sub in _deviceSubs.values) await sub.cancel();
      _deviceSubs.clear();

      // Cancel any active breach vibration timers
      for (final t in _breachTimers.values) t.cancel();
      _breachTimers.clear();

      // Clear all stale device state so unpaired devices disappear immediately
      setState(() {
        _teamLocations.clear();
        _deviceOnline.clear();
        _deviceBattery.clear();
        _deviceSpeed.clear();
        _deviceLastSeen.clear();
        _previousUserStatus.clear();
      });

      // Load paired devices (new multi-device structure)
      final Map<String, String> loaded = {};
      final newMap = data['paired_wristbands'];
      if (newMap is Map) {
        newMap.forEach((k, v) {
          final id    = k.toString();
          final label = (v is Map ? v['label'] : v)?.toString() ?? 'Wristband';
          loaded[id]  = label;
        });
      }
      // Migrate old single-device field — delete it after migrating so it never re-appears
      if (loaded.isEmpty) {
        final oldId    = data['paired_wristband']?.toString();
        final oldLabel = data['wristband_label']?.toString() ?? 'Wristband';
        if (oldId != null && oldId.isNotEmpty) {
          loaded[oldId] = oldLabel;
          await _db.ref('users/${user.uid}/paired_wristbands/$oldId').set({'label': oldLabel});
          await _db.ref('users/${user.uid}').update({
            'paired_wristband': null,
            'wristband_label': null,
          });
        }
      }

      setState(() {
        _profileImageUrl = data['profileImage']?.toString();
        _pairedDevices   = loaded;
        _geofenceRadius  = (data['geofence_radius'] as num?)?.toDouble() ?? 50.0;
        _geofenceMode    = data['geofence_mode']?.toString() ?? 'dynamic';
        _alertsEnabled   = data['alerts_enabled'] != false;

        final savedLat = (data['fixed_center_lat'] as num?)?.toDouble();
        final savedLng = (data['fixed_center_lng'] as num?)?.toDouble();
        if (savedLat != null && savedLng != null) {
          _fixedCenter = google_maps.LatLng(savedLat, savedLng);
        }
      });

      if (loaded.isEmpty) {
        _addLog("SYSTEM: No paired wristband. Go to Settings → Device to pair one.");
      } else {
        for (final id in loaded.keys) {
          _listenToWristband(id);
        }
      }
    } catch (e) {
      _addLog("SYSTEM ERROR: Failed to load settings.");
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // PERSIST GEOFENCE SETTINGS
  // ─────────────────────────────────────────────────────────────────
  Future<void> _saveGeofenceSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _db.ref('users/${user.uid}').update({
      'geofence_radius': _geofenceRadius,
      'geofence_mode': _geofenceMode,
      'fixed_center_lat': _fixedCenter.latitude,
      'fixed_center_lng': _fixedCenter.longitude,
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // GPS TRACKING (Guardian's own location)
  // ─────────────────────────────────────────────────────────────────
  Future<void> _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _addLog("SYSTEM: GPS permission denied.");
        return;
      }
    }

    // Quick initial fix
    try {
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
      if (mounted) {
        setState(() {
          _myLocation = google_maps.LatLng(pos.latitude, pos.longitude);
          // Seed fixed center on first launch only
          if (_geofenceMode == 'dynamic') {
            _fixedCenter = _myLocation;
          }
        });
      }
    } catch (_) {}

    // Continuous stream
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() {
          _myLocation = google_maps.LatLng(pos.latitude, pos.longitude);
        });
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // FIREBASE CONNECTION MONITOR
  // ─────────────────────────────────────────────────────────────────
  void _monitorConnection() {
    _db.ref(".info/connected").onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      _addLog(
        connected
            ? "SYSTEM: Database connection established."
            : "SYSTEM: Database disconnected.",
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // WRISTBAND LIVE LISTENER  (one subscription per device)
  // ─────────────────────────────────────────────────────────────────
  void _listenToWristband(String wristbandId) {
    if (_deviceSubs.containsKey(wristbandId)) return; // no double-subscribe

    final label = _pairedDevices[wristbandId] ?? wristbandId;
    _addLog("SYSTEM: Linked to [$label]");

    final sub = _db.ref('live_location/$wristbandId').onValue.listen((event) {
      if (!mounted) return;

      if (!event.snapshot.exists || event.snapshot.value == null) {
        setState(() {
          _teamLocations.remove(wristbandId);
          _deviceOnline[wristbandId] = false;
        });
        return;
      }

      try {
        final payload =
            Map<dynamic, dynamic>.from(event.snapshot.value as Map);

        double? lat;
        double? lng;

        // Case-insensitive coordinate extraction
        lat = double.tryParse(
              (payload['latitude'] ?? payload['Latitude'])?.toString() ?? '',
            );
        lng = double.tryParse(
              (payload['longitude'] ?? payload['Longitude'])?.toString() ?? '',
            );

        // TTN uplink_message fallback
        if ((lat == null || lng == null) &&
            payload.containsKey('uplink_message')) {
          final decoded =
              (payload['uplink_message'] as Map?)?['decoded_payload'] as Map?;
          if (decoded != null) {
            lat = double.tryParse(decoded['latitude']?.toString() ?? '');
            lng = double.tryParse(decoded['longitude']?.toString() ?? '');
          }
        }

        // Battery level (optional field)
        int? battery = (payload['battery'] ?? payload['Battery']) != null
            ? int.tryParse(
                (payload['battery'] ?? payload['Battery']).toString())
            : null;

        // Speed (km/h)
        double? speed = (payload['speed'] ?? payload['Speed']) != null
            ? double.tryParse(
                (payload['speed'] ?? payload['Speed']).toString())
            : null;

        // Timestamp — supports epoch ms (int) OR string date "YYYY-MM-DD HH:MM:SS"
        DateTime? lastSeen;
        final tsRaw = payload['timestamp'] ?? payload['Timestamp'] ??
                      payload['last_updated'] ?? payload['Last_Updated'];
        if (tsRaw != null) {
          final tsInt = int.tryParse(tsRaw.toString());
          if (tsInt != null) {
            lastSeen = DateTime.fromMillisecondsSinceEpoch(tsInt);
          } else {
            // Try parsing as ISO / human-readable date string
            lastSeen = DateTime.tryParse(tsRaw.toString());
          }
        }
        lastSeen ??= DateTime.now();

        if (lat != null && lng != null) {
          final wristbandPos = google_maps.LatLng(lat, lng);
          final distFromCenter = Geolocator.distanceBetween(
            lat, lng,
            _activeCenter.latitude,
            _activeCenter.longitude,
          );
          final isSafe  = distFromCenter <= _geofenceRadius;
          final wasSafe = _previousUserStatus[wristbandId] ?? true;

          if (_alertsEnabled) {
            final devLabel = _pairedDevices[wristbandId] ?? wristbandId;
            if (!isSafe) {
              // Log once when child first exits
              if (isSafe != wasSafe) {
                _addLog(
                  "ALERT: [$devLabel] exited Safe Zone "
                  "(${distFromCenter.toStringAsFixed(1)}m from center)",
                );
                // Start a 5-second vibration timer for this device
                _breachTimers[wristbandId]?.cancel();
                _breachTimers[wristbandId] = Timer.periodic(
                  const Duration(seconds: 5),
                  (_) {
                    if (mounted) HapticFeedback.heavyImpact();
                  },
                );
                // Vibrate immediately on first detection too
                HapticFeedback.heavyImpact();
              }
            } else {
              // Child returned inside — stop vibrating
              if (isSafe != wasSafe) {
                _breachTimers[wristbandId]?.cancel();
                _breachTimers.remove(wristbandId);
                _addLog("[$devLabel] returned to Safe Zone.");
              }
            }
          } else {
            // Alerts disabled — make sure any running timers are stopped
            _breachTimers[wristbandId]?.cancel();
            _breachTimers.remove(wristbandId);
          }
          _previousUserStatus[wristbandId] = isSafe;

          setState(() {
            _teamLocations[wristbandId]   = wristbandPos;
            _deviceOnline[wristbandId]    = true;
            _deviceBattery[wristbandId]   = battery;
            _deviceSpeed[wristbandId]     = speed;
            _deviceLastSeen[wristbandId]  = lastSeen;
          });
        }
      } catch (e) {
        debugPrint("Error parsing wristband data: $e");
      }
    });
    sub.onError((_) =>
        _addLog("SYSTEM ERROR: Firebase permission denied for wristband data."));

    _deviceSubs[wristbandId] = sub;
  }

  // ─────────────────────────────────────────────────────────────────
  // LOG HELPER
  // ─────────────────────────────────────────────────────────────────
  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      final now = DateTime.now();
      final time =
          "${now.hour.toString().padLeft(2, '0')}:"
          "${now.minute.toString().padLeft(2, '0')}:"
          "${now.second.toString().padLeft(2, '0')}";
      _activityLogs.insert(0, "[$time] $message");
      if (_activityLogs.length > 100) _activityLogs.removeLast();
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // SOS HANDLER
  // ─────────────────────────────────────────────────────────────────
  void _triggerSOS() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    HapticFeedback.heavyImpact();
    _addLog("🆘 SOS TRIGGERED by Guardian. Location recorded.");

    // Log SOS event to Firebase
    await _db.ref('sos_events/${user.uid}').push().set({
      'timestamp': ServerValue.timestamp,
      'guardian_lat': _myLocation.latitude,
      'guardian_lng': _myLocation.longitude,
      'wristband_id': _pairedWristbandId ?? 'none',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("🆘 SOS logged. Your location has been recorded."),
          backgroundColor: AppColorScheme.of(context).danger,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    bool anyBreach = false;
    _teamLocations.forEach((_, pos) {
      final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        _activeCenter.latitude, _activeCenter.longitude,
      );
      if (dist > _geofenceRadius) anyBreach = true;
    });

    final pages = [
      DashboardTab(
        guardianLocation: _myLocation,
        teamLocations: _teamLocations,
        deviceSpeeds: _deviceSpeed,
        pairedDevices: _pairedDevices,
        deviceOnlineMap: _deviceOnline,
        deviceLastSeenMap: _deviceLastSeen,
        staleThreshold: _staleThreshold,
        activeCenter: _activeCenter,
        radius: _geofenceRadius,
        isAnyBreach: anyBreach,
        geofenceMode: _geofenceMode,
        pairedWristbandId: _pairedWristbandId,
        wristbandLabel: _wristbandLabel,
        wristbandLastSeen: _wristbandLastSeen,
        wristbandBattery: _wristbandBattery,
        isWristbandOnline: _isWristbandOnline,
        onRadiusChanged: (val) {
          setState(() => _geofenceRadius = val);
          _saveGeofenceSettings();
        },
        onGeofenceModeChanged: (mode) {
          setState(() {
            _geofenceMode = mode;
            if (mode == 'fixed') {
              _fixedCenter = _myLocation; // Snap to current position
            }
          });
          _saveGeofenceSettings();
        },
        onViewMap: () => setState(() => _currentIndex = 1),
        onDeviceTap: (deviceId) {
          setState(() {
            _currentIndex    = 1;
            _focusDeviceId   = deviceId;
          });
        },
        onSOS: _triggerSOS,
      ),
      MapTab(
        guardianLocation: _myLocation,
        teamLocations: _teamLocations,
        pairedDevices: _pairedDevices,
        deviceLastSeenMap: _deviceLastSeen,
        staleThreshold: _staleThreshold,
        focusDeviceId: _focusDeviceId,
        onFocusConsumed: () => setState(() => _focusDeviceId = null),
        center: _activeCenter,
        radius: _geofenceRadius,
        geofenceMode: _geofenceMode,
        onSetFixedCenter: (latlng) {
          setState(() {
            _fixedCenter = latlng;
            _geofenceMode = 'fixed';
          });
          _saveGeofenceSettings();
          _addLog("Geofence center set at (${latlng.latitude.toStringAsFixed(4)}, ${latlng.longitude.toStringAsFixed(4)})");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Fixed geofence center updated."),
              backgroundColor: AppColorScheme.of(context).accent,
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      LogsTab(logs: _activityLogs),
    ];

    final c = AppColorScheme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "KEEP WATCH",
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ).then((_) => _loadUserSettings());
              },
              borderRadius: BorderRadius.circular(50),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.border, width: 1.5),
                  color: c.card,
                ),
                child: ClipOval(
                  child: _profileImageUrl != null &&
                          _profileImageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _profileImageUrl!,
                          cacheKey: FirebaseAuth.instance.currentUser?.uid,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Icon(
                            Icons.person,
                            color: c.textSecondary,
                            size: 20,
                          ),
                          errorWidget: (_, __, ___) => Icon(
                            Icons.person,
                            color: c.textSecondary,
                            size: 20,
                          ),
                        )
                      : Icon(
                          Icons.person,
                          color: c.textSecondary,
                          size: 20,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: c.background,
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        height: 65,
        backgroundColor: c.background,
        indicatorColor: c.card,
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined, color: c.textSecondary),
            selectedIcon: Icon(Icons.dashboard, color: c.accent),
            label: 'Tracker',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined, color: c.textSecondary),
            selectedIcon: Icon(Icons.map, color: c.accent),
            label: 'Live Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined, color: c.textSecondary),
            selectedIcon: Icon(Icons.list_alt, color: c.accent),
            label: 'Logs',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD TAB
// ─────────────────────────────────────────────────────────────────────────────
class DashboardTab extends StatelessWidget {
  final google_maps.LatLng guardianLocation;
  final google_maps.LatLng activeCenter;
  final Map<String, google_maps.LatLng> teamLocations;
  final Map<String, double?> deviceSpeeds;
  final Map<String, String> pairedDevices;
  final Map<String, bool> deviceOnlineMap;
  final Map<String, DateTime?> deviceLastSeenMap;
  final Duration staleThreshold;
  final double radius;
  final bool isAnyBreach;
  final String geofenceMode;
  final String? pairedWristbandId;
  final String? wristbandLabel;
  final DateTime? wristbandLastSeen;
  final int? wristbandBattery;
  final bool isWristbandOnline;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<String> onGeofenceModeChanged;
  final VoidCallback onViewMap;
  final VoidCallback onSOS;
  final ValueChanged<String> onDeviceTap;   // tapped device id → go to map

  const DashboardTab({
    super.key,
    required this.guardianLocation,
    required this.activeCenter,
    required this.teamLocations,
    required this.deviceSpeeds,
    required this.pairedDevices,
    required this.deviceOnlineMap,
    required this.deviceLastSeenMap,
    required this.staleThreshold,
    required this.radius,
    required this.isAnyBreach,
    required this.geofenceMode,
    required this.onRadiusChanged,
    required this.onGeofenceModeChanged,
    required this.onViewMap,
    required this.onSOS,
    required this.onDeviceTap,
    this.pairedWristbandId,
    this.wristbandLabel,
    this.wristbandLastSeen,
    this.wristbandBattery,
    this.isWristbandOnline = false,
  });

  String _formatLastSeen(DateTime? dt) {
    if (dt == null) return "Never";
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return "${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    return "${diff.inHours}h ago";
  }

  Color _batteryColor(int? pct) {
    if (pct == null) return Colors.grey;
    if (pct > 50) return AppColors.success;
    if (pct > 20) return Colors.orange;
    return AppColors.danger;
  }

  IconData _batteryIcon(int? pct) {
    if (pct == null) return Icons.battery_unknown;
    if (pct > 80) return Icons.battery_full;
    if (pct > 50) return Icons.battery_5_bar;
    if (pct > 20) return Icons.battery_3_bar;
    if (pct > 10) return Icons.battery_1_bar;
    return Icons.battery_alert;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      color: c.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              // ── Wristband Status Card ─────────────────────────────
              if (pairedWristbandId == null)
                _NoPairingBanner(context: context)
              else
                _WristbandStatusCard(
                  label: wristbandLabel ?? 'Wristband',
                  deviceId: pairedWristbandId!,
                  isOnline: isWristbandOnline,
                  battery: wristbandBattery,
                  lastSeen: wristbandLastSeen,
                  batteryColor: _batteryColor(wristbandBattery),
                  batteryIcon: _batteryIcon(wristbandBattery),
                  formatLastSeen: _formatLastSeen,
                ),

              const SizedBox(height: 16),

              // ── Breach Status ─────────────────────────────────────
              _BreachStatusCard(
                isAnyBreach: isAnyBreach,
                onViewMap: onViewMap,
              ),

              const SizedBox(height: 16),

              // ── Geofence Controls ─────────────────────────────────
              _GeofenceControlCard(
                radius: radius,
                geofenceMode: geofenceMode,
                teamCount: teamLocations.length,
                onRadiusChanged: onRadiusChanged,
                onGeofenceModeChanged: onGeofenceModeChanged,
                onViewMap: onViewMap,
              ),

              const SizedBox(height: 16),

              // ── Target Status ─────────────────────────────────────
              Text(
                "Target Status",
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                height: 128,
                child: pairedDevices.isEmpty
                    ? Center(
                        child: Text(
                          "No device paired.",
                          style: TextStyle(color: c.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: pairedDevices.length,
                        itemBuilder: (context, index) {
                          final id    = pairedDevices.keys.elementAt(index);
                          final label = pairedDevices[id] ?? id;
                          final hasLocation = teamLocations.containsKey(id);
                          final isOnline    = deviceOnlineMap[id] ?? false;
                          final lastSeen    = deviceLastSeenMap[id];
                          final isStale     = lastSeen == null
                              ? false
                              : DateTime.now().difference(lastSeen) > staleThreshold;

                          // ── Stale / disconnected card ────────────────
                          if (hasLocation && isStale) {
                            final pos  = teamLocations[id]!;
                            final dist = Geolocator.distanceBetween(
                              pos.latitude, pos.longitude,
                              activeCenter.latitude, activeCenter.longitude,
                            );
                            final ago = _formatLastSeen(lastSeen);
                            return GestureDetector(
                              onTap: () => onDeviceTap(id),
                              child: Container(
                              width: 115,
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.5),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Icon(Icons.person_pin_circle,
                                          color: Colors.grey.shade600, size: 22),
                                      Positioned(
                                        right: 0, bottom: 0,
                                        child: Container(
                                          width: 10, height: 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.grey,
                                            border: Border.all(
                                                color: c.card, width: 1.5),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "${dist.toStringAsFixed(0)}m",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "Lost • $ago",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ), // Container
                            ); // GestureDetector
                          }

                          // ── No location yet — show GPS search state ──
                          if (!hasLocation) {
                            return Container(
                              width: 115,
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: c.border.withOpacity(0.4),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: isOnline
                                          ? Colors.orange
                                          : c.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isOnline
                                        ? "Searching GPS…"
                                        : "Waiting for device…",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isOnline
                                          ? Colors.orange
                                          : c.textSecondary,
                                    ),
                                  ),
                                  if (isOnline)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        "Go outdoors",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }

                          // ── Has location — normal card ───────────────
                          final pos  = teamLocations[id]!;
                          final dist = Geolocator.distanceBetween(
                            pos.latitude, pos.longitude,
                            activeCenter.latitude, activeCenter.longitude,
                          );
                          final safe  = dist <= radius;
                          final speed = deviceSpeeds[id];

                          final IconData moveIcon;
                          final String moveLabel;
                          final Color moveColor;
                          if (speed == null || speed < 1.0) {
                            moveIcon  = Icons.accessibility_new;
                            moveLabel = speed == null ? '—' : 'Still';
                            moveColor = Colors.grey;
                          } else if (speed < 7.0) {
                            moveIcon  = Icons.directions_walk;
                            moveLabel = 'Walking';
                            moveColor = Colors.orange;
                          } else {
                            moveIcon  = Icons.directions_run;
                            moveLabel = 'Running';
                            moveColor = Colors.redAccent;
                          }

                          return GestureDetector(
                            onTap: () => onDeviceTap(id),
                            child: Container(
                            width: 115,
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: safe
                                    ? c.success.withOpacity(0.4)
                                    : c.danger.withOpacity(0.4),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      safe ? Icons.person_pin_circle : Icons.warning_rounded,
                                      color: safe ? c.success : c.danger,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(moveIcon, color: moveColor, size: 18),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "${dist.toStringAsFixed(0)}m",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: safe ? c.success : c.danger,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  moveLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: moveColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Tap to locate",
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ), // Container
                          ); // GestureDetector
                        },
                      ),
              ),

              const SizedBox(height: 16),

              // ── My Telemetry ──────────────────────────────────────
              Text(
                "Guardian Telemetry",
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _infoCard(
                    "Latitude",
                    guardianLocation.latitude.toStringAsFixed(5),
                    Icons.north,
                  ),
                  _infoCard(
                    "Longitude",
                    guardianLocation.longitude.toStringAsFixed(5),
                    Icons.east,
                  ),
                  _infoCard("Role", "Guardian", Icons.security),
                  _infoCard(
                    "Geofence",
                    geofenceMode == 'fixed' ? "Fixed" : "Dynamic",
                    geofenceMode == 'fixed' ? Icons.push_pin : Icons.my_location,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── SOS Button ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSOS,
                  icon: Icon(Icons.sos, color: c.danger, size: 22),
                  label: Text(
                    "EMERGENCY / SOS",
                    style: TextStyle(
                      color: c.danger,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.danger),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(String title, String value, IconData icon) {
    return Builder(builder: (context) {
      final c = AppColorScheme.of(context);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: c.textSecondary),
            const Spacer(),
            Text(title, style: TextStyle(color: c.textSecondary, fontSize: 11)),
            Text(
              value,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _NoPairingBanner extends StatelessWidget {
  final BuildContext context;
  const _NoPairingBanner({required this.context});

  @override
  Widget build(BuildContext ctx) {
    // Orange is intentional here (warning color) — stays consistent across themes
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.watch_off, color: Colors.orange, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "No wristband paired.\nGo to Settings → Device to pair one.",
              style: TextStyle(color: Colors.orange, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _WristbandStatusCard extends StatelessWidget {
  final String label;
  final String deviceId;
  final bool isOnline;
  final int? battery;
  final DateTime? lastSeen;
  final Color batteryColor;
  final IconData batteryIcon;
  final String Function(DateTime?) formatLastSeen;

  const _WristbandStatusCard({
    required this.label,
    required this.deviceId,
    required this.isOnline,
    required this.battery,
    required this.lastSeen,
    required this.batteryColor,
    required this.batteryIcon,
    required this.formatLastSeen,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnline ? c.success.withOpacity(0.4) : c.border.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Icon(Icons.watch, color: c.textSecondary, size: 34),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? c.success : Colors.grey,
                    border: Border.all(color: c.card, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold),
                ),
                Text(
                  isOnline ? "Online" : "Offline • Last: ${formatLastSeen(lastSeen)}",
                  style: TextStyle(
                    color: isOnline ? c.success : c.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (battery != null)
            Column(
              children: [
                Icon(batteryIcon, color: batteryColor, size: 20),
                Text(
                  "$battery%",
                  style: TextStyle(
                    color: batteryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          else
            Icon(Icons.battery_unknown, color: c.textSecondary, size: 20),
        ],
      ),
    );
  }
}

class _BreachStatusCard extends StatelessWidget {
  final bool isAnyBreach;
  final VoidCallback onViewMap;

  const _BreachStatusCard({
    required this.isAnyBreach,
    required this.onViewMap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAnyBreach
              ? [c.danger, const Color(0xFF8B2323)]
              : [c.success, const Color(0xFF1E6F2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isAnyBreach ? c.danger : c.success).withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "SYSTEM STATUS",
                  style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  isAnyBreach ? "BREACH DETECTED" : "SECURE",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: onViewMap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: isAnyBreach ? c.danger : c.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            icon: const Icon(Icons.remove_red_eye, size: 18),
            label: const Text("View Map"),
          ),
        ],
      ),
    );
  }
}

class _GeofenceControlCard extends StatelessWidget {
  final double radius;
  final String geofenceMode;
  final int teamCount;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<String> onGeofenceModeChanged;
  final VoidCallback onViewMap;

  const _GeofenceControlCard({
    required this.radius,
    required this.geofenceMode,
    required this.teamCount,
    required this.onRadiusChanged,
    required this.onGeofenceModeChanged,
    required this.onViewMap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Geofence Radius", style: TextStyle(color: c.textSecondary)),
              Text("${radius.toInt()} m",
                  style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(value: radius, min: 10, max: 200, divisions: 19, onChanged: onRadiusChanged),

          Divider(color: c.border.withOpacity(0.5), height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Geofence Mode", style: TextStyle(color: c.textSecondary)),
              Container(
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _ModeToggleButton(
                      label: "Dynamic",
                      icon: Icons.my_location,
                      isActive: geofenceMode == 'dynamic',
                      onTap: () => onGeofenceModeChanged('dynamic'),
                      tooltip: "Follows guardian's location",
                    ),
                    _ModeToggleButton(
                      label: "Fixed",
                      icon: Icons.push_pin,
                      isActive: geofenceMode == 'fixed',
                      onTap: () => onGeofenceModeChanged('fixed'),
                      tooltip: "Tap map to set center",
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (geofenceMode == 'fixed')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: onViewMap,
                child: Text(
                  "→ Go to Map: drag the pin or tap to reposition",
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),

          Divider(color: c.border.withOpacity(0.5), height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Active Targets", style: TextStyle(color: c.textSecondary)),
              Text(
                "$teamCount device${teamCount != 1 ? 's' : ''}",
                style: TextStyle(color: c.accent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String tooltip;

  const _ModeToggleButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Builder(builder: (context) {
          final c = AppColorScheme.of(context);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? c.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isActive
                      ? (c.isDark ? Colors.black : Colors.white)
                      : c.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive
                        ? (c.isDark ? Colors.black : Colors.white)
                        : c.textSecondary,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAP TAB
// ─────────────────────────────────────────────────────────────────────────────
class MapTab extends StatefulWidget {
  final google_maps.LatLng guardianLocation;
  final Map<String, google_maps.LatLng> teamLocations;
  final Map<String, String> pairedDevices;
  final Map<String, DateTime?> deviceLastSeenMap;
  final Duration staleThreshold;
  final String? focusDeviceId;       // set to animate camera to a device
  final VoidCallback? onFocusConsumed; // called after camera animates
  final google_maps.LatLng center;
  final double radius;
  final String geofenceMode;
  final ValueChanged<google_maps.LatLng> onSetFixedCenter;

  const MapTab({
    super.key,
    required this.guardianLocation,
    required this.teamLocations,
    required this.pairedDevices,
    required this.deviceLastSeenMap,
    required this.staleThreshold,
    this.focusDeviceId,
    this.onFocusConsumed,
    required this.center,
    required this.radius,
    required this.geofenceMode,
    required this.onSetFixedCenter,
  });

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  google_maps.GoogleMapController? _mapController;
  google_maps.MapType _mapType = google_maps.MapType.normal;

  void _centerOnTarget() {
    if (widget.teamLocations.isEmpty) return;
    final pos = widget.teamLocations.values.first;
    _mapController?.animateCamera(
      google_maps.CameraUpdate.newLatLngZoom(pos, 18),
    );
  }

  void _centerOnGuardian() {
    _mapController?.animateCamera(
      google_maps.CameraUpdate.newLatLngZoom(widget.guardianLocation, 18),
    );
  }

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return "${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    return "${diff.inHours}h ago";
  }

  @override
  void didUpdateWidget(MapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusDeviceId != null &&
        widget.focusDeviceId != oldWidget.focusDeviceId) {
      // Small delay so the map has time to finish rendering after tab switch
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        final pos = widget.teamLocations[widget.focusDeviceId];
        if (pos != null) {
          _mapController?.animateCamera(
            google_maps.CameraUpdate.newLatLngZoom(pos, 18),
          );
        }
      });
      widget.onFocusConsumed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<google_maps.Marker> markers = {};

    // Guardian marker
    markers.add(
      google_maps.Marker(
        markerId: const google_maps.MarkerId("guardian"),
        position: widget.guardianLocation,
        icon: google_maps.BitmapDescriptor.defaultMarkerWithHue(
          google_maps.BitmapDescriptor.hueBlue,
        ),
        infoWindow: const google_maps.InfoWindow(title: "GUARDIAN (You)"),
      ),
    );

    // Geofence center marker (only in fixed mode) — draggable
    if (widget.geofenceMode == 'fixed') {
      markers.add(
        google_maps.Marker(
          markerId: const google_maps.MarkerId("fence_center"),
          position: widget.center,
          icon: google_maps.BitmapDescriptor.defaultMarkerWithHue(
            google_maps.BitmapDescriptor.hueAzure,
          ),
          infoWindow: const google_maps.InfoWindow(
            title: "Geofence Center",
            snippet: "Drag to reposition",
          ),
          alpha: 0.9,
          draggable: true,
          onDragEnd: (newPos) => widget.onSetFixedCenter(newPos),
          onDragStart: (_) => HapticFeedback.mediumImpact(),
        ),
      );
    }

    // Wristband markers
    widget.teamLocations.forEach((id, pos) {
      final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        widget.center.latitude, widget.center.longitude,
      );
      final isSafe   = dist <= widget.radius;
      final label    = widget.pairedDevices[id] ?? id;
      final lastSeen = widget.deviceLastSeenMap[id];
      final isStale  = lastSeen == null
          ? false
          : DateTime.now().difference(lastSeen) > widget.staleThreshold;

      // Stale = grey marker; safe = green; breach = red
      final double markerHue = isStale
          ? google_maps.BitmapDescriptor.hueViolet   // grey-ish to signal lost contact
          : (isSafe ? 120.0 : 0.0);

      final String snippet;
      if (isStale) {
        final ago = lastSeen == null ? 'unknown' : _formatAgo(lastSeen);
        snippet = "⚠ Disconnected · Last seen $ago";
      } else if (isSafe) {
        snippet = "Safe (${dist.toStringAsFixed(0)}m)";
      } else {
        snippet = "BREACH (${dist.toStringAsFixed(0)}m away)";
      }

      markers.add(
        google_maps.Marker(
          markerId: google_maps.MarkerId(id),
          position: pos,
          icon: google_maps.BitmapDescriptor.defaultMarkerWithHue(markerHue),
          alpha: isStale ? 0.5 : 1.0,   // fade out stale marker
          infoWindow: google_maps.InfoWindow(
            title: isStale ? "$label  ⚠ OFFLINE" : label,
            snippet: snippet,
          ),
        ),
      );
    });

    return Stack(
      children: [
        google_maps.GoogleMap(
          initialCameraPosition: google_maps.CameraPosition(
            target: widget.center,
            zoom: 18,
          ),
          markers: markers,
          circles: {
            google_maps.Circle(
              circleId: const google_maps.CircleId("fence"),
              center: widget.center,
              radius: widget.radius,
              fillColor: const Color(0xFF58A6FF).withOpacity(0.12),
              strokeColor: const Color(0xFF58A6FF),
              strokeWidth: 2,
            ),
          },
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            // If a device was already focused before map was ready, fly to it now
            if (widget.focusDeviceId != null) {
              final pos = widget.teamLocations[widget.focusDeviceId];
              if (pos != null) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    _mapController?.animateCamera(
                      google_maps.CameraUpdate.newLatLngZoom(pos, 18),
                    );
                  }
                });
              }
              widget.onFocusConsumed?.call();
            }
          },
          mapType: _mapType,
          // Tap on map to reposition fixed geofence
          onTap: widget.geofenceMode == 'fixed'
              ? (latlng) => widget.onSetFixedCenter(latlng)
              : null,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
        ),

        // ── Map Control Buttons ─────────────────────────────────
        Positioned(
          bottom: 20,
          left: 14,
          child: Column(
            children: [
              // Satellite / Normal toggle
              FloatingActionButton.small(
                heroTag: "map_type",
                backgroundColor: const Color(0xFF1C2128),
                onPressed: () {
                  setState(() {
                    _mapType = _mapType == google_maps.MapType.normal
                        ? google_maps.MapType.hybrid
                        : google_maps.MapType.normal;
                  });
                },
                tooltip: _mapType == google_maps.MapType.normal
                    ? "Switch to satellite"
                    : "Switch to map",
                child: Icon(
                  _mapType == google_maps.MapType.normal
                      ? Icons.satellite_alt
                      : Icons.map,
                  color: const Color(0xFF58A6FF),
                ),
              ),
              const SizedBox(height: 8),
              // Center on target
              if (widget.teamLocations.isNotEmpty)
                FloatingActionButton.small(
                  heroTag: "center_target",
                  backgroundColor: const Color(0xFF1C2128),
                  onPressed: _centerOnTarget,
                  tooltip: "Center on wristband",
                  child: const Icon(
                    Icons.person_pin_circle,
                    color: const Color(0xFF58A6FF),
                  ),
                ),
              const SizedBox(height: 8),
              // Center on guardian
              FloatingActionButton.small(
                heroTag: "center_guardian",
                backgroundColor: const Color(0xFF1C2128),
                onPressed: _centerOnGuardian,
                tooltip: "Center on me",
                child: const Icon(Icons.my_location, color: Color(0xFF58A6FF)),
              ),
            ],
          ),
        ),

        // ── Fixed mode instruction banner ───────────────────────
        if (widget.geofenceMode == 'fixed')
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.drag_indicator, color: const Color(0xFF58A6FF), size: 16),
                    SizedBox(width: 6),
                    Text(
                      "Drag the pin  •  or tap to place it",
                      style: TextStyle(color: Colors.white70, fontSize: 12), // map banner - always on dark overlay
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGS TAB
// ─────────────────────────────────────────────────────────────────────────────
class LogsTab extends StatelessWidget {
  final List<String> logs;

  const LogsTab({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      color: c.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Activity Logs",
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${logs.length} entries",
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Log list
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        "No activity recorded yet.",
                        style: TextStyle(color: c.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: c.border.withOpacity(0.4), height: 1),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final isAlert = log.contains("ALERT");
                        final isSOS = log.contains("SOS");
                        final isError = log.contains("ERROR");
                        final isSystem = log.contains("SYSTEM");

                        Color color;
                        IconData icon;
                        if (isSOS) {
                          color = c.danger;
                          icon = Icons.sos;
                        } else if (isAlert) {
                          color = c.danger;
                          icon = Icons.warning_rounded;
                        } else if (isError) {
                          color = Colors.orange;
                          icon = Icons.error_outline;
                        } else if (isSystem) {
                          color = c.textSecondary;
                          icon = Icons.info_outline;
                        } else {
                          color = c.success;
                          icon = Icons.check_circle_outline;
                        }

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(icon, color: color, size: 18),
                          title: Text(
                            log,
                            style: TextStyle(
                              color: isAlert || isSOS
                                  ? color
                                  : c.textPrimary,
                              fontFamily: "Courier",
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}