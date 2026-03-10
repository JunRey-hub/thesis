import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps;
import 'package:geolocator/geolocator.dart';
import 'app_colors.dart';
import 'settings_page.dart';

// --- MAIN DASHBOARD SCREEN ---
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  // -- ADD THIS: Stream subscription to prevent memory leaks --
  StreamSubscription<Position>? _positionStream;

  // -- UPDATED: Default set to Dumaguete instead of (0,0) and Googleplex --
  google_maps.LatLng _myLocation = const google_maps.LatLng(9.3068, 123.3054);
  google_maps.LatLng _geofenceCenter = const google_maps.LatLng(9.3068, 123.3054);
  
  // STATE
  Map<String, google_maps.LatLng> _teamLocations = {};
  
  // SETTINGS
  double _geofenceRadius = 50.0;

  // LOGS
  List<String> _activityLogs = [];
  Map<String, bool> _previousUserStatus = {}; 

  // --- PROFILE IMAGE STATE ---
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _startTracking();
    _testFirebaseConnection(); 
    _listenToLiveLocations(); 
    _loadProfileImage(); 
    _addLog("Guardian Authorized. System Online.");
  }

  // -- ADD THIS: Cleanup method for when you switch accounts/log out --
  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // --- 0. TEST FIREBASE CONNECTION ---
  void _testFirebaseConnection() {
    final database = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://keep-watch-d3e89-default-rtdb.asia-southeast1.firebasedatabase.app/',
    );

    database.ref(".info/connected").onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      if (connected) {
        print("🟢 SUCCESS: FIREBASE IS CONNECTED!");
        _addLog("SYSTEM: Database connection established.");
      } else {
        print("🔴 ERROR: FIREBASE IS DISCONNECTED.");
        _addLog("SYSTEM: Database disconnected.");
      }
    });
  }

  // --- FETCH PROFILE IMAGE ---
  Future<void> _loadProfileImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          final data = doc.data();
          if (data != null && data.containsKey('profileImage')) {
             setState(() {
               _profileImageUrl = data['profileImage'];
             });
             return; 
          }
        }
      } catch (e) {
        print("Firestore load error: $e");
      }

      if (user.photoURL != null && mounted) {
        setState(() {
          _profileImageUrl = user.photoURL;
        });
      }
    }
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      String time = "${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}:${DateTime.now().second.toString().padLeft(2,'0')}";
      _activityLogs.insert(0, "[$time] $message");
      if (_activityLogs.length > 50) _activityLogs.removeLast();
    });
  }

  // -- UPDATED: 1. TRACKING (Guardian's Location) --
  Future<void> _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _addLog("SYSTEM: GPS Permission Denied.");
        return;
      }
    }

    // INSTANT FETCH: Grab location immediately before waiting for the stream
    try {
      Position? currentPos = await Geolocator.getLastKnownPosition() ?? 
                             await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _myLocation = google_maps.LatLng(currentPos.latitude, currentPos.longitude);
          _geofenceCenter = google_maps.LatLng(currentPos.latitude, currentPos.longitude);
        });
      }
    } catch (e) {
      print("Could not get initial position: $e");
    }

    // STREAM: Listen for continuous updates
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _myLocation = google_maps.LatLng(position.latitude, position.longitude);
          _geofenceCenter = google_maps.LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  // 2. REALTIME FIREBASE LISTENER (SECURE TWO-STEP FETCH)
  void _listenToLiveLocations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _addLog("SYSTEM: No user logged in. Tracking disabled.");
      return;
    }

    final database = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://keep-watch-d3e89-default-rtdb.asia-southeast1.firebasedatabase.app/',
    );

    try {
      // STEP 1: Find which wristband belongs to this user
      final userSnapshot = await database.ref('users/${user.uid}/paired_wristband').get();
      
      String? pairedWristbandId;
      if (userSnapshot.exists && userSnapshot.value != null) {
        pairedWristbandId = userSnapshot.value.toString();
      }

      if (pairedWristbandId == null || pairedWristbandId.isEmpty) {
        _addLog("SYSTEM: No paired wristband found for this account.");
        print("No paired wristband ID in Realtime Database under users/${user.uid}/paired_wristband");
        return;
      }

      _addLog("SYSTEM: Linked to wristband [$pairedWristbandId]");

      // STEP 2: Listen specifically to that single wristband
      DatabaseReference ref = database.ref('live_location/$pairedWristbandId');
      
      ref.onValue.listen((DatabaseEvent event) {
        if (!mounted) return;
        
        if (event.snapshot.exists && event.snapshot.value != null) {
          try {
            final payloadData = event.snapshot.value;
            
            if (payloadData != null && payloadData is Map) {
              final payload = Map<dynamic, dynamic>.from(payloadData);
              double? lat;
              double? lng;

              // --- SCENARIO A: ROBUST CASE-INSENSITIVE CHECK ---
              bool hasLat = payload.containsKey('latitude') || payload.containsKey('Latitude');
              bool hasLng = payload.containsKey('longitude') || payload.containsKey('Longitude');

              if (hasLat && hasLng) {
                final rawLat = payload['latitude'] ?? payload['Latitude'];
                final rawLng = payload['longitude'] ?? payload['Longitude'];
                
                lat = double.tryParse(rawLat.toString());
                lng = double.tryParse(rawLng.toString());
              } 
              // Scenario B: Raw TTN Webhook format
              else if (payload.containsKey('uplink_message')) {
                final uplink = payload['uplink_message'];
                if (uplink is Map && uplink.containsKey('decoded_payload')) {
                  final decoded = uplink['decoded_payload'];
                  if (decoded is Map && decoded.containsKey('latitude') && decoded.containsKey('longitude')) {
                    lat = double.tryParse(decoded['latitude'].toString());
                    lng = double.tryParse(decoded['longitude'].toString());
                  }
                }
              }

              if (lat != null && lng != null) {
                String deviceId = pairedWristbandId!; // Using the paired ID
                
                double distFromGuardian = Geolocator.distanceBetween(
                  lat, lng, 
                  _geofenceCenter.latitude, _geofenceCenter.longitude
                );

                bool isSafe = distFromGuardian <= _geofenceRadius;
                bool wasSafe = _previousUserStatus[deviceId] ?? true;

                if (isSafe != wasSafe) {
                  if (!isSafe) {
                    _addLog("ALERT: Target exited Safe Zone (${distFromGuardian.toStringAsFixed(1)}m)");
                    HapticFeedback.heavyImpact();
                  } else {
                    _addLog("Target entered Safe Zone.");
                  }
                  _previousUserStatus[deviceId] = isSafe;
                }

                // Update UI state securely!
                setState(() {
                  _teamLocations = {deviceId: google_maps.LatLng(lat!, lng!)};
                });
              }
            }
          } catch (e) {
            print("Error parsing location data: $e");
          }
        } else {
          // No data found for this wristband
          setState(() {
            _teamLocations = {};
          });
        }
      }).onError((error) {
        // --- CATCH FIREBASE RULES ERRORS ---
        print("🚨 FIREBASE LISTENER ERROR: $error");
        _addLog("SYSTEM ERROR: Database permission denied.");
      });

    } catch (e) {
      print("Error fetching paired wristband: $e");
      _addLog("SYSTEM ERROR: Could not verify paired wristband.");
    }
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
        teamLocations: _teamLocations, 
        radius: _geofenceRadius,
        isAnyBreach: anyBreach, 
        onRadiusChanged: (val) => setState(() => _geofenceRadius = val),
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 15.0),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                ).then((_) {
                  _loadProfileImage(); 
                });
              },
              borderRadius: BorderRadius.circular(50),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1.5),
                  color: AppColors.cardDark,
                ),
                child: ClipOval(
                  child: _profileImageUrl != null
                      ? Image.network(
                          _profileImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.person, color: Colors.white, size: 20);
                          },
                        )
                      : const Icon(Icons.settings, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.background,
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

// --- SUB-WIDGETS ---
class DashboardTab extends StatelessWidget {
  final google_maps.LatLng location;
  final Map<String, google_maps.LatLng> teamLocations;
  final double radius;
  final bool isAnyBreach;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onViewMap;

  const DashboardTab({
    super.key,
    required this.location,
    required this.teamLocations,
    required this.radius,
    required this.isAnyBreach,
    required this.onRadiusChanged,
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
                        const Text("Active Targets Tracked", style: TextStyle(color: Colors.white70)),
                        Text("${teamLocations.length} Users", style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                      ],
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
                child: teamLocations.isEmpty 
                  ? const Center(child: Text("No tracking devices detected online.", style: TextStyle(color: AppColors.textGrey)))
                  : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: teamLocations.length,
                    itemBuilder: (context, index) {
                      String userId = teamLocations.keys.elementAt(index);
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
                            // Keeps the ID short so it fits the box nicely
                            Text(userId.length > 8 ? "${userId.substring(0, 8)}..." : userId, style: const TextStyle(fontSize: 12, color: Colors.white)),
                            const SizedBox(height: 2),
                            const Text("Tracked", style: TextStyle(fontSize: 10, color: AppColors.success)),
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