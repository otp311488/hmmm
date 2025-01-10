import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_screen.dart';
import 'dart:async';

class DriverLocationMarker extends StatefulWidget {
  const DriverLocationMarker({Key? key}) : super(key: key);

  @override
  _DriverLocationMarkerState createState() => _DriverLocationMarkerState();
}

class _DriverLocationMarkerState extends State<DriverLocationMarker> {
  LatLng? currentPosition;
  String selectedRoute = "Route A";
  String selectedBus = "Bus 1"; // Default bus
  final List<String> busNumbers = ["Bus 1", "Bus 2", "Bus 3", "Bus 4"];
  final LatLng finalDestination = LatLng(32.3610, 74.2079); // UET RCET location
  Timer? locationUpdateTimer;
  bool hasReachedDestination = false;

  final Map<String, List<Map<String, dynamic>>> routeStops = {
    "Route A": [
      {"name": "Chanda Qila", "location": LatLng(32.0940, 74.2025), "time": "6:45"},
      {"name": "Mall of Gujranwala", "location": LatLng(32.1097, 74.1997), "time": "7:35"},
      {"name": "NADRA", "location": LatLng(32.1370, 74.2091), "time": "7:37"},
      {"name": "Sheikhupura Mor", "location": LatLng(32.1477, 74.1912), "time": "7:40"},
      // Add all stops here
    ],
  };

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location permission is required.")),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        currentPosition = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      print("Error fetching location: $e");
    }
  }

  Future<void> _sendAnnouncement(String title, String message) async {
    try {
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': title,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'busId': selectedBus,
        'route': selectedRoute,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Announcement sent successfully!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send announcement: $e")),
      );
    }
  }

  void _showAnnouncementDialog() {
    String title = "Announcement";
    String message = "";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("Send Announcement"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(labelText: "Title"),
              onChanged: (value) => title = value,
            ),
            TextField(
              decoration: InputDecoration(labelText: "Message"),
              maxLines: 3,
              onChanged: (value) => message = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (message.isNotEmpty) {
                _sendAnnouncement(title, message);
              }
            },
            child: Text("Send"),
          ),
        ],
      ),
    );
  }

  // Start location sharing periodically (update every 10 seconds)
  void startSharingLocation() {
    locationUpdateTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      if (currentPosition != null) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        setState(() {
          currentPosition = LatLng(position.latitude, position.longitude);
        });

        double distanceToDestination = Geolocator.distanceBetween(
          currentPosition!.latitude,
          currentPosition!.longitude,
          finalDestination.latitude,
          finalDestination.longitude,
        );

        if (distanceToDestination < 50) {
          timer.cancel();
          hasReachedDestination = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Reached UET RCET. Location sharing stopped.")),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedStops = routeStops[selectedRoute] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Bus Location'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => LoginScreen()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.announcement),
            onPressed: _showAnnouncementDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Text(
                  "Select Bus: ",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 10),
                DropdownButton<String>(
                  value: selectedBus,
                  items: busNumbers
                      .map((bus) => DropdownMenuItem<String>(
                            value: bus,
                            child: Text(bus),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedBus = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              markers: {
                if (currentPosition != null)
                  Marker(markerId: MarkerId(selectedBus), position: currentPosition!),
                Marker(
                  markerId: const MarkerId('destination'),
                  position: finalDestination,
                  infoWindow: const InfoWindow(title: "UET RCET"),
                ),
                ...selectedStops.map(
                  (stop) => Marker(
                    markerId: MarkerId(stop["name"]),
                    position: stop["location"],
                    infoWindow: InfoWindow(
                      title: stop["name"],
                      snippet: "Next stop time: ${stop["time"]}",
                    ),
                  ),
                ),
              },
              initialCameraPosition: CameraPosition(
                target: currentPosition ?? finalDestination,
                zoom: 14,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ElevatedButton(
        onPressed: () {
          if (currentPosition != null && !hasReachedDestination) {
            startSharingLocation();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Location sharing started!")),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(hasReachedDestination
                  ? "Already reached UET RCET."
                  : "Unable to fetch location.")),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        ),
        child: const Text(
          "Share",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
