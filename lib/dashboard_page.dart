// lib/dashboard_page.dart

import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps;
import 'package:geolocator/geolocator.dart';
import 'app_colors.dart';
import 'settings_page.dart'; // <--- KEEPING THIS IMPORT FOR SETTINGS

// --- MAIN DASHBOARD SCREEN ---
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  // -- STATE --
  google_maps.LatLng _myLocation = const google_maps.LatLng(0, 0);
  Map<String, google_maps.LatLng> _teamLocations = {};
  
  // MOVEMENT VECTORS
  Map<String, List<double>> _userDirections = {}; 

  bool _usersSpawned = false;
  
  // SETTINGS
  double _geofenceRadius = 50.0;
  double _targetCount = 3.0; 

  // LOGS
  List<String> _activityLogs = [];
  Map<String, bool> _previousUserStatus = {}; 
  
  // GEOFENCE CENTER (Guardian)
  google_maps.LatLng _geofenceCenter = const google_maps.LatLng(37.4219983, -122.084);
  
  @override
  void initState() {
    super.initState();
    _startTracking();
    _startMovementLoop();
    _addLog("Guardian Authorized. System Online.");
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      String time = "${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}:${DateTime.now().second.toString().padLeft(2,'0')}";
      _activityLogs.insert(0, "[$time] $message");
      if (_activityLogs.length > 50) _activityLogs.removeLast();
    });
  }

  // 1. TRACKING
  Future<void> _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _myLocation = google_maps.LatLng(position.latitude, position.longitude);
          _geofenceCenter = google_maps.LatLng(position.latitude, position.longitude);
          
          if (!_usersSpawned) {
            _respawnUsers(_targetCount.toInt());
            _usersSpawned = true;
          }
        });
      }
    });
  }

  // --- SPAWN USERS ---
  void _respawnUsers(int count) {
    Map<String, google_maps.LatLng> newTeam = {};
    _userDirections.clear();
    final random = Random();

    for (int i = 1; i <= count; i++) {
      double angle = random.nextDouble() * 2 * pi;
      double dist = 10.0 + random.nextInt(70); 
      double offset = dist * 0.000009;

      double startLat = _geofenceCenter.latitude + (offset * cos(angle));
      double startLng = _geofenceCenter.longitude + (offset * sin(angle));

      newTeam["User $i"] = google_maps.LatLng(startLat, startLng);

      _userDirections["User $i"] = [
        (random.nextDouble() - 0.5) * 0.00003, 
        (random.nextDouble() - 0.5) * 0.00003
      ];
    }

    setState(() {
      _teamLocations = newTeam;
      _previousUserStatus.clear();
      newTeam.forEach((key, value) {
        double d = Geolocator.distanceBetween(
          value.latitude, value.longitude, 
          _geofenceCenter.latitude, _geofenceCenter.longitude
        );
        _previousUserStatus[key] = d <= _geofenceRadius;
      });
    });
  }

  // 2. MOVEMENT LOOP
  void _startMovementLoop() {
    Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!mounted) return;
      if (_teamLocations.isEmpty) return;

      Map<String, google_maps.LatLng> updatedLocations = {};
      final random = Random();

      _teamLocations.forEach((user, currentPos) {
        List<double> direction = _userDirections[user]!;
        
        double newLat = currentPos.latitude + direction[0];
        double newLng = currentPos.longitude + direction[1];

        double distFromGuardian = Geolocator.distanceBetween(
          newLat, newLng, 
          _geofenceCenter.latitude, _geofenceCenter.longitude
        );

        if (distFromGuardian > 120) {
           double latDiff = _geofenceCenter.latitude - newLat;
           double lngDiff = _geofenceCenter.longitude - newLng;
           _userDirections[user] = [latDiff * 0.00001, lngDiff * 0.00001];
        } 
        else if (random.nextInt(10) > 8) {
           _userDirections[user] = [
             (random.nextDouble() - 0.5) * 0.00004, 
             (random.nextDouble() - 0.5) * 0.00004
           ];
        }

        updatedLocations[user] = google_maps.LatLng(newLat, newLng);

        bool isSafe = distFromGuardian <= _geofenceRadius;
        bool wasSafe = _previousUserStatus[user] ?? true;

        if (isSafe != wasSafe) {
          if (!isSafe) {
            _addLog("ALERT: $user exited Safe Zone ($distFromGuardian.0m)");
            HapticFeedback.heavyImpact();
          } else {
            _addLog("$user entered Safe Zone.");
          }
          _previousUserStatus[user] = isSafe;
        }
      });

      setState(() {
        _teamLocations = updatedLocations;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    bool anyBreach = false;
    _teamLocations.forEach((user, pos) {
       double dist = Geolocator.distanceBetween(
         pos.latitude, pos.longitude, 
         _geofenceCenter.latitude, _geofenceCenter.longitude
       );
       if (dist > _geofenceRadius) anyBreach = true;
    });

    final List<Widget> pages = [
      DashboardTab(
        location: _myLocation,
        activeUsers: _teamLocations.length,
        radius: _geofenceRadius,
        targetCount: _targetCount,
        isAnyBreach: anyBreach, 
        onRadiusChanged: (val) => setState(() => _geofenceRadius = val),
        onTargetCountChanged: (val) {
          setState(() => _targetCount = val);
          _respawnUsers(val.toInt());
        },
        onViewMap: () => setState(() => _currentIndex = 1),
      ),
      MapTab(
        myLocation: _myLocation,
        teamLocations: _teamLocations,
        center: _geofenceCenter,
        radius: _geofenceRadius,
      ),
      LogsTab(logs: _activityLogs),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "KEEP WATCH", 
          style: TextStyle(
            color: Colors.white, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 1.5
          )
        ),
        // --- SETTINGS BUTTON (KEPT) ---
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      backgroundColor: AppColors.background, // Moved background color here to cover AppBar area
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        height: 65,
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.cardDark,
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined, color: AppColors.textGrey),
            selectedIcon: Icon(Icons.dashboard, color: AppColors.accent),
            label: 'Tracker', 
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined, color: AppColors.textGrey),
            selectedIcon: Icon(Icons.map, color: AppColors.accent),
            label: 'Live Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt, color: AppColors.textGrey),
            selectedIcon: Icon(Icons.list_alt, color: AppColors.accent),
            label: 'Logs', 
          ),
        ],
      ),
    );
  }
}

// --- SUB-WIDGETS (Dashboard, Map, Logs) ---

class DashboardTab extends StatelessWidget {
  final google_maps.LatLng location;
  final int activeUsers;
  final double radius;
  final double targetCount;
  final bool isAnyBreach;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<double> onTargetCountChanged;
  final VoidCallback onViewMap;

  const DashboardTab({
    super.key,
    required this.location,
    required this.activeUsers,
    required this.radius,
    required this.targetCount,
    required this.isAnyBreach,
    required this.onRadiusChanged,
    required this.onTargetCountChanged,
    required this.onViewMap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER REMOVED (Moved to AppBar)
              const SizedBox(height: 10),
              
              const Text("Status Console", style: TextStyle(color: AppColors.textGrey, fontSize: 13, letterSpacing: 1)),
              const SizedBox(height: 20),

              // --- CONTROL PANEL ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Geofence Radius", style: TextStyle(color: Colors.white70)),
                        Text("${radius.toInt()}m", style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: radius,
                      min: 10,
                      max: 100,
                      divisions: 9,
                      onChanged: onRadiusChanged,
                    ),
                    const Divider(color: Colors.white10, height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Active Targets", style: TextStyle(color: Colors.white70)),
                        Text("${targetCount.toInt()} Users", style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: targetCount,
                      min: 1,
                      max: 5, 
                      divisions: 4, 
                      activeColor: Colors.orange, 
                      thumbColor: Colors.white,
                      onChanged: onTargetCountChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // STATUS CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isAnyBreach 
                        ? [AppColors.danger, const Color(0xFF8B2323)] 
                        : [AppColors.success, const Color(0xFF1E6F2E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: isAnyBreach ? AppColors.danger.withOpacity(0.4) : AppColors.success.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("SYSTEM STATUS", style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    Text(
                      isAnyBreach ? "BREACH DETECTED" : "SECURE",
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: onViewMap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: isAnyBreach ? AppColors.danger : AppColors.success,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      icon: const Icon(Icons.remove_red_eye),
                      label: const Text("Verify on Map"),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 25),
              const Text("Target Status", style: TextStyle(color: AppColors.textGrey, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),

              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: activeUsers,
                  itemBuilder: (context, index) {
                    return Container(
                      width: 85,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.directions_walk, color: Colors.blueGrey, size: 28),
                          const SizedBox(height: 4),
                          Text("User ${index + 1}", style: const TextStyle(fontSize: 12, color: Colors.white)),
                          const SizedBox(height: 2),
                          const Text("Walking...", style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 25),
              const Text("My Telemetry", style: TextStyle(color: AppColors.textGrey, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.6,
                children: [
                  _infoCard("Latitude", location.latitude.toStringAsFixed(4), Icons.north),
                  _infoCard("Longitude", location.longitude.toStringAsFixed(4), Icons.east),
                  _infoCard("Role", "Guardian", Icons.security),
                  _infoCard("GPS", "Active", Icons.gps_fixed),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.textGrey),
          const Spacer(),
          Text(title, style: const TextStyle(color: AppColors.textGrey, fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}

class MapTab extends StatelessWidget {
  final google_maps.LatLng myLocation;
  final Map<String, google_maps.LatLng> teamLocations;
  final google_maps.LatLng center;
  final double radius;

  const MapTab({
    super.key,
    required this.myLocation,
    required this.teamLocations,
    required this.center,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    Set<google_maps.Marker> markers = {};
    
    markers.add(google_maps.Marker(
      markerId: const google_maps.MarkerId("guardian"),
      position: center,
      icon: google_maps.BitmapDescriptor.defaultMarkerWithHue(google_maps.BitmapDescriptor.hueBlue),
      infoWindow: const google_maps.InfoWindow(title: "GUARDIAN (You)"),
    ));

    teamLocations.forEach((name, pos) {
      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, center.latitude, center.longitude);
      bool isSafe = dist <= radius;
      
      markers.add(google_maps.Marker(
        markerId: google_maps.MarkerId(name),
        position: pos,
        icon: google_maps.BitmapDescriptor.defaultMarkerWithHue(isSafe ? 120.0 : 0.0), // Green/Red
        infoWindow: google_maps.InfoWindow(title: name, snippet: isSafe ? "Safe" : "BREACH"),
      ));
    });

    return google_maps.GoogleMap(
      initialCameraPosition: google_maps.CameraPosition(target: center, zoom: 18),
      markers: markers,
      circles: {
        google_maps.Circle(
          circleId: const google_maps.CircleId("fence"),
          center: center,
          radius: radius,
          fillColor: AppColors.accent.withOpacity(0.15),
          strokeColor: AppColors.accent,
          strokeWidth: 2,
        )
      },
    );
  }
}

class LogsTab extends StatelessWidget {
  final List<String> logs;

  const LogsTab({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text("Mission Logs", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: logs.length,
                separatorBuilder: (c, i) => const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final log = logs[index];
                  bool isAlert = log.contains("ALERT");
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isAlert ? Icons.warning : Icons.check_circle,
                      color: isAlert ? AppColors.danger : AppColors.success,
                    ),
                    title: Text(
                      log,
                      style: TextStyle(
                        color: isAlert ? AppColors.danger : AppColors.textWhite,
                        fontFamily: "Courier",
                        fontSize: 13,
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