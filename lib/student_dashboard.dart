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

  // Store the timestamp of the last fetched announcement
  Timestamp? lastFetchedAnnouncementTimestamp;

  @override
  void initState() {
    super.initState();
    fetchAnnouncements(); // Fetch announcements
    addBusStopMarkers();
    addUetRcetMarker(); // Add UET RCET marker
    fetchBusLocations(); // Fetch bus locations
  }

  final LatLng uetRcetLocation = const LatLng(32.3610, 74.2079);
  List<Map<String, dynamic>> busDetails = [];
  List<Map<String, dynamic>> announcements = []; // Store announcements as Map
  ScrollController scrollController = ScrollController();

  // Bus stops for Route A
  final List<Map<String, dynamic>> routeABusStops = [
    // Bus stop data
  ];

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
      _stopMarkers["UET RCET"] = uetMarker; // Add to stop markers for simplicity
    });
  }

  void fetchAnnouncements() {
    // Fetch announcements only after the last fetched timestamp
    Query query = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('timestamp', descending: true);

    if (lastFetchedAnnouncementTimestamp != null) {
      query = query.where('timestamp', isGreaterThan: lastFetchedAnnouncementTimestamp);
    }

    query.snapshots().listen((snapshot) {
      setState(() {
        // Update the last fetched timestamp to the most recent announcement's timestamp
        if (snapshot.docs.isNotEmpty) {
          lastFetchedAnnouncementTimestamp = snapshot.docs.first['timestamp'];
          announcements = snapshot.docs.map((doc) {
            return {
              'message': doc['message'],
              'busId': doc['busId'],
              'route': doc['route'],
              'timestamp': doc['timestamp'],
            };
          }).toList(); // Convert to list of maps
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
            if (data['location'] != null &&
                data['location']['latitude'] != null &&
                data['location']['longitude'] != null) {
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
                  SnackBar(
                    content: Text("Bus ${data['busId']} has reached UET RCET."),
                  ),
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

              // ETA Calculation
              String eta = _calculateETA(driverPosition);
              busDetails.add({
                'busId': data['busId'],
                'eta': eta,
                'status': data['status'] ?? 'Arriving',
                'stopName': data['stopName'] ?? 'Unknown',
              });

              // OSRM Route Logic - calculate route
              _calculateRoute(uetRcetLocation, driverPosition);
            }
          }
        }
        _isLoading = false;
      });
    });
  }

  String _calculateETA(LatLng driverPosition) {
    // Calculate the distance between the bus and UET RCET location
    double distance = Geolocator.distanceBetween(
      driverPosition.latitude,
      driverPosition.longitude,
      uetRcetLocation.latitude,
      uetRcetLocation.longitude,
    );

    // Assuming an average speed of 40 km/h
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
      body: SingleChildScrollView(  // Make entire body scrollable
        child: Column(
          children: [
            // Map Section
            Container(
              height: 400, // Set a fixed height for map view
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
            // Bus Details Section
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
            // Announcements Section
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
