import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({Key? key}) : super(key: key);

  @override
  _StudentDashboardState createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final Map<String, Marker> _busMarkers = {};
  final Map<String, Marker> _stopMarkers = {};
  final Set<Polyline> _polylines = {};
  String selectedRoute = "Route A";
  bool _isLoading = true;
  String etaMessage = "";
  bool _isRouteAvailable = true;

  Timestamp? lastFetchedAnnouncementTimestamp;

  final LatLng uetRcetLocation = const LatLng(32.3610, 74.2079);
  List<Map<String, dynamic>> busDetails = [];
  List<Map<String, dynamic>> announcements = [];
  ScrollController scrollController = ScrollController();

  final List<Map<String, dynamic>> routeABusStops = [
    {"name": "Chanda Qila", "location": LatLng(32.0940, 74.2025), "time": "6:45"},
    {"name": "Mall of Gujranwala", "location": LatLng(32.1097, 74.1997), "time": "7:35"},
    {"name": "NADRA", "location": LatLng(32.1370, 74.2091), "time": "7:37"},
    {"name": "Sheikhupura Mor", "location": LatLng(32.1477, 74.1912), "time": "7:40"},
    {"name": "Sheranwala Bagh", "location": LatLng(32.1555, 74.1889), "time": "7:42"},
    {"name": "Sialkoti Gate", "location": LatLng(32.1583, 74.1891), "time": "7:43"},
    {"name": "Gondlanwala Adda", "location": LatLng(32.1481, 74.1773), "time": "7:45"},
    {"name": "Larri Adda", "location": LatLng(32.1722, 74.1838), "time": "7:48"},
    {"name": "KFC", "location": LatLng(32.1877, 74.1944), "time": "7:50"},
    {"name": "Sharifpura", "location": LatLng(32.1514, 74.1541), "time": "7:52"},
    {"name": "Shaheenabad", "location": LatLng(32.1878, 74.1739), "time": "7:54"},
    {"name": "Pindi Bypass", "location": LatLng(32.2044, 74.1739), "time": "7:56"},
    {"name": "DC Colony", "location": LatLng(32.166351, 74.195900), "time": "8:00"},
    {"name": "Rahwali", "location": LatLng(32.2479, 74.1680), "time": "8:05"},
    {"name": "Ghakhar", "location": LatLng(32.3002, 74.1388), "time": "8:13"},
    {"name": "Ojla Pull", "location": LatLng(32.3372718, 74.1392), "time": "8:17"},
    {"name": "Kot Inayat Khan", "location": LatLng(32.2100, 74.1400), "time": "8:22"},
  ];

  @override
  void initState() {
    super.initState();
    fetchAnnouncements();
    addBusStopMarkers();
    addUetRcetMarker();
    fetchBusLocations();
  }

  void addBusStopMarkers() {
    setState(() {
      _stopMarkers.clear();
      for (var stop in routeABusStops) {
        final marker = Marker(
          markerId: MarkerId(stop['name']),
          position: stop['location'],
          infoWindow: InfoWindow(
            title: stop['name'],
            snippet: "Time: ${stop['time']}",
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        );
        _stopMarkers[stop['name']] = marker;
      }
    });
  }

  void addUetRcetMarker() {
    setState(() {
      final uetMarker = Marker(
        markerId: const MarkerId("UET RCET"),
        position: uetRcetLocation,
        infoWindow: const InfoWindow(
          title: "UET RCET",
          snippet: "University of Engineering & Technology RCET",
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      );
      _stopMarkers["UET RCET"] = uetMarker;
    });
  }

  void fetchAnnouncements() {
    Query query = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('timestamp', descending: true);

    if (lastFetchedAnnouncementTimestamp != null) {
      query = query.where('timestamp', isGreaterThan: lastFetchedAnnouncementTimestamp);
    }

    query.snapshots().listen((snapshot) {
      setState(() {
        if (snapshot.docs.isNotEmpty) {
          lastFetchedAnnouncementTimestamp = snapshot.docs.first['timestamp'];
          announcements = snapshot.docs.map((doc) {
            return {
              'message': doc['message'],
              'busId': doc['busId'],
              'route': doc['route'],
              'timestamp': doc['timestamp'],
            };
          }).toList();
        }
      });
    });
  }

  void fetchBusLocations() {
    setState(() => _isLoading = true);
    FirebaseFirestore.instance
        .collection('bus_locations')
        .where('route', isEqualTo: selectedRoute)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _busMarkers.clear();
        _polylines.clear();
        etaMessage = "";
        busDetails.clear();

        if (snapshot.docs.isEmpty) {
          _isRouteAvailable = false;
        } else {
          _isRouteAvailable = true;
          for (var doc in snapshot.docs) {
            final data = doc.data();
            if (data['location'] != null) {
              final LatLng driverPosition = LatLng(
                data['location']['latitude'],
                data['location']['longitude'],
              );

              if (Geolocator.distanceBetween(
                      driverPosition.latitude,
                      driverPosition.longitude,
                      uetRcetLocation.latitude,
                      uetRcetLocation.longitude) < 50) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Bus ${data['busId']} has reached UET RCET.")),
                );
                continue;
              }

              final marker = Marker(
                markerId: MarkerId(data['busId']),
                position: driverPosition,
                infoWindow: InfoWindow(
                  title: data['busId'],
                  snippet: "Status: ${data['status'] ?? 'Unknown'}",
                ),
              );
              _busMarkers[data['busId']] = marker;

              String eta = _calculateETA(driverPosition);
              busDetails.add({
                'busId': data['busId'],
                'eta': eta,
                'status': data['status'] ?? 'Arriving',
                'stopName': data['stopName'] ?? 'Unknown',
              });

              _calculateRoute(uetRcetLocation, driverPosition);
            }
          }
        }
        _isLoading = false;
      });
    });
  }

  String _calculateETA(LatLng driverPosition) {
    double distance = Geolocator.distanceBetween(
      driverPosition.latitude,
      driverPosition.longitude,
      uetRcetLocation.latitude,
      uetRcetLocation.longitude,
    );

    double timeInHours = distance / 1000 / 40;
    int timeInMinutes = (timeInHours * 60).round();

    return timeInMinutes.toString();
  }

  Future<void> _calculateRoute(LatLng start, LatLng end) async {
    final String osrmUrl =
        "http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&steps=true";

    try {
      final response = await http.get(Uri.parse(osrmUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final route = data['routes'][0];
        final geometry = route['geometry'];
        final List<LatLng> polylineCoordinates = _decodePolyline(geometry);
        setState(() {
          _polylines.add(Polyline(
            polylineId: PolylineId('route1'),
            points: polylineCoordinates,
            color: Colors.blue,
            width: 4,
          ));
        });
      }
    } catch (e) {
      print("Error fetching OSRM route: $e");
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polylinePoints = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index) - 63;
        index++;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int deltaLat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += deltaLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index) - 63;
        index++;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int deltaLng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += deltaLng;

      polylinePoints.add(LatLng((lat / 1E5), (lng / 1E5)));
    }

    return polylinePoints;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 400,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: LatLng(32.1617, 74.1883),
                        zoom: 12,
                      ),
                      markers: {..._busMarkers.values.toSet(), ..._stopMarkers.values.toSet()},
                      polylines: _polylines,
                    ),
            ),
            busDetails.isNotEmpty
                ? Column(
                    children: busDetails.map((bus) {
                      return Card(
                        margin: const EdgeInsets.all(8.0),
                        elevation: 5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          leading: Icon(Icons.directions_bus, color: Colors.blueAccent),
                          title: Text(
                            "Bus: ${bus['busId'] ?? "Unknown"}",
                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "ETA: ${bus['eta'] ?? "N/A"} mins\nStatus: ${bus['status'] ?? "N/A"}\nNext Stop: ${bus['stopName'] ?? "N/A"}",
                            style: GoogleFonts.poppins(),
                          ),
                        ),
                      );
                    }).toList(),
                  )
                : Center(
                    child: Text(
                      "No buses available",
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                  ),
            announcements.isNotEmpty
                ? Column(
                    children: announcements.map((announcement) {
                      return Card(
                        margin: const EdgeInsets.all(8.0),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          leading: Icon(Icons.announcement, color: Colors.orange),
                          title: Text(
                            announcement['message'] ?? "No message",
                            style: GoogleFonts.poppins(),
                          ),
                        ),
                      );
                    }).toList(),
                  )
                : Center(
                    child: CircularProgressIndicator(),
                  ),
          ],
        ),
      ),
    );
  }
}
