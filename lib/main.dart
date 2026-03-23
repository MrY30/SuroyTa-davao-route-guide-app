import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/favorite_location.dart';
import 'hive_service.dart';
import 'package:fluttertoast/fluttertoast.dart';

// NOT SO FINAL COLORS
const Color primaryColor = Color(0xFF42c585);
const Color fontColor = Color(0xfff9f5f0); // Texts and Icons
const Color btnColor = Color(0xff184a46); // Navigation Bar, FABs, and Elevated Buttons
const Color sheetBackgroundColor = Color(0xff1f2730); // Draggable Scrollable Sheet
const Color unselectedNavColor = Color(0xff9bb2a7); // Navigation Icons and Text not selected
const Color cardColor = Color(0xff374656);
const Color deleteColor = Color(0xffdb5f4e);
const Color darkDeleteColor = Color(0xffa83525);
const Color disableColor = Color(0xff5d7d7b);

void main() async {
  // Ensure Flutter is ready before reading files
  WidgetsFlutterBinding.ensureInitialized(); 
  
  // Load the hidden variables
  await dotenv.load(fileName: ".env"); 
  
  // --- NEW: INITIALIZE HIVE ---
  await Hive.initFlutter();
  
  // Register the adapter generated in Step 3
  Hive.registerAdapter(FavoriteLocationAdapter());
  
  // Open the specific box where we will store the locations
  await Hive.openBox<FavoriteLocation>('locations_box');

  runApp(const SakayTaApp());
}

class SakayTaApp extends StatelessWidget {
  const SakayTaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sakay Ta',
      debugShowCheckedModeBanner: false, // Removes the debug banner
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

// 1. The Data Model (Unchanged)
class JeepneyRoute {
  final String name;
  final String filePath;
  final Color color;
  bool isVisible;
  Polyline? polylineData;

  JeepneyRoute({
    required this.name,
    required this.filePath,
    required this.color,
    this.isVisible = false,
  });
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// ALGORITHM HERE
// 1. A clean data class to hold our successful results
class RouteResult {
  final String routeName;
  final double estimatedStartWalk; // Split from total
  final double estimatedEndWalk;   // Split from total
  final int boardIndex; 
  final int alightIndex; 
  
  // --- THE NEW MATH PROPERTIES ---
  final double ridingDistanceKm; 
  final double estimatedFare;

  // --- OSRM PROPERTIES ---
  double? actualStartWalk; // Split from total
  double? actualEndWalk;   // Split from total
  List<LatLng>? actualWalkPathStart; 
  List<LatLng>? actualWalkPathEnd; 
  bool isFetchingActualRoute = false; 

  RouteResult({
    required this.routeName,
    required this.estimatedStartWalk,
    required this.estimatedEndWalk,
    required this.boardIndex,
    required this.alightIndex,
    required this.ridingDistanceKm,
    required this.estimatedFare,
  });

  // A helper getter so we can still easily sort the list by the shortest overall walk
  double get totalEstimatedWalk => estimatedStartWalk + estimatedEndWalk;
}

// 2. The Isolate Function (Must be top-level, outside your classes)
// It accepts a map containing the start pin, dest pin, and all route coordinates.
List<RouteResult> processRoutesInBackground(Map<String, dynamic> data) {
  final LatLng start = data['start'];
  final LatLng dest = data['dest'];
  final Map<String, List<LatLng>> allRouteCoordinates = data['routes'];

  final Distance haversine = const Distance();
  List<RouteResult> validRoutes = [];

  // ==========================================
  // THE COST FUNCTION DIALS
  // Tweak these to change how "lazy" the algorithm is!
  // ==========================================
  const double walkMultiplier = 15.0; // 1m of walking adds 15 penalty points
  const double rideMultiplier = 1.0;  // 1m of riding adds 1 penalty point
  const double minRideDistance = 200.0; // Ignore rides shorter than 200m

  allRouteCoordinates.forEach((routeName, coordinates) {
    if (coordinates.isEmpty) return; 

    // 1. PRE-CALCULATE: Cumulative Distances (Speeds up the math massively)
    List<double> cumulativeDistances = [0.0];
    double totalRouteDistance = 0.0;
    for (int i = 0; i < coordinates.length - 1; i++) {
      totalRouteDistance += haversine.as(LengthUnit.Meter, coordinates[i], coordinates[i+1]);
      cumulativeDistances.add(totalRouteDistance);
    }

    // 2. FIND CANDIDATES: Gather all points within 400m
    List<int> candidateStarts = [];
    List<int> candidateDests = [];

    for (int i = 0; i < coordinates.length; i++) {
      if (haversine.as(LengthUnit.Meter, start, coordinates[i]) <= 400) {
        candidateStarts.add(i);
      }
      if (haversine.as(LengthUnit.Meter, dest, coordinates[i]) <= 400) {
        candidateDests.add(i);
      }
    }

    if (candidateStarts.isEmpty || candidateDests.isEmpty) return; 

    // 3. PAIRING: Calculate the Penalty Score for every possible combination
    int bestStartIdx = -1;
    int bestDestIdx = -1;
    double lowestPenaltyScore = double.infinity;
    
    // Store the exact distances of the winning pair
    double finalRideDistance = 0.0; 
    double bestStartWalk = 0.0;
    double bestDestWalk = 0.0;

    for (int sIdx in candidateStarts) {
      for (int dIdx in candidateDests) {
        if (sIdx == dIdx) continue;

        // Calculate Ride Distance
        double rideDist = 0.0;
        if (sIdx < dIdx) {
          rideDist = cumulativeDistances[dIdx] - cumulativeDistances[sIdx];
        } else { // It's a loop!
          rideDist = (totalRouteDistance - cumulativeDistances[sIdx]) + cumulativeDistances[dIdx];
        }

        // Filter out ridiculous 1-block jeepney rides
        if (rideDist < minRideDistance) continue; 

        // Calculate Walk Distances
        double sWalk = haversine.as(LengthUnit.Meter, start, coordinates[sIdx]);
        double dWalk = haversine.as(LengthUnit.Meter, dest, coordinates[dIdx]);
        double totalWalk = sWalk + dWalk;

        // --- THE COST FUNCTION ---
        // Calculate the total "pain" of this specific route combination
        double penaltyScore = (totalWalk * walkMultiplier) + (rideDist * rideMultiplier);

        // Does this pair have the lowest penalty? Make it the new winner!
        if (penaltyScore < lowestPenaltyScore) {
          lowestPenaltyScore = penaltyScore;
          bestStartIdx = sIdx;
          bestDestIdx = dIdx;
          finalRideDistance = rideDist;
          bestStartWalk = sWalk;
          bestDestWalk = dWalk;
        }
      }
    }

    // 4. RESULT: If a valid route passed all tests, build it!
    if (bestStartIdx != -1 && bestDestIdx != -1) {
      double ridingDistanceKm = finalRideDistance / 1000.0;

      // Base fare logic
      double fare = 13.0; 
      if (ridingDistanceKm > 4.0) {
        fare += (ridingDistanceKm - 4.0) * 1.80; 
      }

      validRoutes.add(
        RouteResult(
          routeName: routeName,
          estimatedStartWalk: bestStartWalk,
          estimatedEndWalk: bestDestWalk,
          boardIndex: bestStartIdx,
          alightIndex: bestDestIdx,
          ridingDistanceKm: ridingDistanceKm,
          estimatedFare: fare,
          // You might need to add this property to your RouteResult class if you want to sort by it:
          // totalEstimatedWalk: bestStartWalk + bestDestWalk, 
        ),
      );
    }
  });

  // 5. GLOBAL SORTING: Keep the easiest walk at the top of the UI
  // Make sure your RouteResult class has a getter for totalEstimatedWalk!
  validRoutes.sort((a, b) => (a.estimatedStartWalk + a.estimatedEndWalk).compareTo(b.estimatedStartWalk + b.estimatedEndWalk));
  
  return validRoutes;
}
// END OF ALGORITHM

// 1. Define the modes
enum PinMode { none, start, destination }

// 2. Add these variables to your state
PinMode currentPinMode = PinMode.none;
LatLng? startPin;
LatLng? destinationPin;
bool enableGPS = false;

// --- NEW STATE: Explore Tab Search ---
final TextEditingController _searchController = TextEditingController();
String _searchQuery = '';

// --- NEW STATE: Database Service ---
final HiveService _hiveService = HiveService(); 


class _MapScreenState extends State<MapScreen> {
  List<JeepneyRoute> allRoutes = [];

  // --- NEW STATE VARIABLES ---
  final DraggableScrollableController sheetController = DraggableScrollableController();
  final MapController mapController = MapController();
  List<RouteResult> suggestedRoutes = [];
  RouteResult? selectedRoute;

  maplibre.MapLibreMapController? maplibreController; // NEW: The native GPU controller

  int _selectedIndex = 1;

  @override
  void initState() {
    super.initState();
    initializeRouteList();
  }

  // --- NEW STATE: Favorites Popup Overlay ---
  bool _isSavePopupVisible = false;
  String _currentDestinationName = ''; // Stores Nominatim name, or empty for manual pins
  final TextEditingController _saveNameController = TextEditingController();

  @override
  void dispose() {
    // Always dispose controllers to prevent memory leaks!
    _searchController.dispose();
    _saveNameController.dispose();
    super.dispose();
  }
  // --- NEW LOGIC: Talk to OSRM API ---
  Future<Map<String, dynamic>?> fetchWalkingRouteFromOSRM(LatLng start, LatLng end) async {
    // OSRM expects coordinates in Longitude,Latitude format
    final url = 'https://router.project-osrm.org/route/v1/foot/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson';
    
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        final distance = data['routes'][0]['distance'] as num;
        
        // Convert GeoJSON [lon, lat] back to FlutterMap LatLng
        List<LatLng> path = coords.map((c) => LatLng(c[1], c[0])).toList();
        
        return {
          'path': path,
          'distance': distance.toDouble(),
        };
      }
    } catch (e) {
      debugPrint("OSRM Request Failed: $e");
    }
    return null;
  }

  // 2. Logic: Loading the Catalog
  // --- UPDATED LOGIC: Loading Catalog with Colors ---
  Future<void> initializeRouteList() async {
    try {
      final String response = await rootBundle.loadString('assets/routes_catalog.json');
      final List<dynamic> catalogData = json.decode(response);

      List<JeepneyRoute> tempRoutes = [];

      for (var item in catalogData) {
        // 1. Clean the hex string (remove the '#' if it exists)
        String hexString = item['color'].toString().replaceAll('#', '');
        // 2. Add 'FF' to the front for 100% opacity, then parse it
        Color parsedColor = Color(int.parse('0xFF$hexString'));

        tempRoutes.add(
          JeepneyRoute(
            name: item['name'],
            filePath: item['file'],
            color: parsedColor, // Use the real color!
          ),
        );
      }

      setState(() {
        allRoutes = tempRoutes;
      });
    } catch (e) {
      debugPrint("Error loading catalog: $e");
    }
  }

  // 3. Logic: Lazy Loading Routes (Manual Toggles)
  // --- UPDATED LOGIC: Toggle Route by Object ---
  Future<void> handleRouteToggle(JeepneyRoute route) async {
    bool newState = !route.isVisible;
    _isSelectedRoute = !route.isVisible;

    if (newState == true && route.polylineData == null) {
      route.polylineData = await parseRoute(route.filePath, route.color);
    }

    setState(() {
      route.isVisible = newState;
      selectedRoute = null; 
    });
    
    drawMapElements(); 
  }

  // --- NEW LOGIC: Bulk Route Actions ---
  Future<void> _toggleAllRoutes(bool showAll) async {
    if(showAll){
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(
      //     content: Text('Loading all routes on map...'), 
      //     duration: const Duration(milliseconds: 1500)
      //   ),
      // );
      Fluttertoast.showToast(msg: "Loading all routes on map");
    }

    // Loop through ALL routes, not just the filtered ones
    for (var route in allRoutes) {
      if (showAll && route.polylineData == null) {
        // If turning on, parse the GeoJSON if we haven't yet
        route.polylineData = await parseRoute(route.filePath, route.color);
      }
      route.isVisible = showAll;
      _isSelectAllChecked = showAll;
    }

    setState(() {
      selectedRoute = null; // Clear any routing algorithms
    });
    
    drawMapElements(); // Command the GPU to draw the massive update
  }

  Future<Polyline> parseRoute(String filePath, Color routeColor) async {
    final String response = await rootBundle.loadString(filePath);
    final data = await json.decode(response);

    List<LatLng> points = [];

    for (var feature in data['features']) {
      if (feature['geometry']['type'] == 'LineString') {
        var coords = feature['geometry']['coordinates'];
        for (var coord in coords) {
          points.add(LatLng(coord[1], coord[0]));
        }
      }
    }

    return Polyline(
      points: points,
      strokeWidth: 4.0,
      color: routeColor,
    );
  }
  // testing
  // --- NEW LOGIC: Hardware GPS ---
  Future<void> getUserCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Check if GPS hardware is turned on
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enable GPS.')));
      return;
    }

    // 2. Check and request permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions denied.')));
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissions permanently denied.')));
      return;
    }

    // 3. Get the actual location
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    LatLng userLatLng = LatLng(position.latitude, position.longitude);

    // 4. Set it as the Start Pin and move the map camera
    setState(() {
      startPin = userLatLng;
      enableGPS = true;
      _clearRoutingData();
    });
    maplibreController?.animateCamera(
      maplibre.CameraUpdate.newLatLngZoom(
        maplibre.LatLng(userLatLng.latitude, userLatLng.longitude), 
        16.0
      )
    );
    drawMapElements();
  }
  
  // --- UPGRADED LOGIC: Dual-Input Search (Nominatim + Coordinates) ---
  Future<void> searchLocation(String query) async {
    if (query.isEmpty) return;

    // 1. THE SMART INTERCEPTOR (Regex checks for "number, number")
    final RegExp coordRegExp = RegExp(r'^([-+]?\d{1,2}(?:\.\d+)?),\s*([-+]?\d{1,3}(?:\.\d+)?)$');
    final match = coordRegExp.firstMatch(query);

    if (match != null) {
      // PATH A: It's a raw coordinate! No internet required.
      final lat = double.parse(match.group(1)!);
      final lon = double.parse(match.group(2)!);
      LatLng searchResult = LatLng(lat, lon);

      setState((){
        destinationPin = searchResult;
        _clearRoutingData();
        _currentDestinationName = '';
      });
      
      drawMapElements();

      if(sheetController.isAttached){
        sheetController.animateTo(0.26, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut,);
      }

      Future.delayed(const Duration(milliseconds: 400), (){
        maplibreController?.animateCamera(
          maplibre.CameraUpdate.newLatLngZoom(
            maplibre.LatLng(searchResult.latitude, searchResult.longitude), 16.0
          )
        );
      });
       
      await _saveToHistory("Pinned Coordinate", searchResult); // Save to Hive
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinate dropped!'), duration: Duration(seconds: 1)),
      );

      return; // Exit the function early!
    }

    // PATH B: It's text. Proceed with Nominatim Geocoding.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Searching for "$query"...'), duration: const Duration(seconds: 1)),
    );

    final String scopedQuery = "$query, Davao City";
    final url = 'https://nominatim.openstreetmap.org/search?q=$scopedQuery&format=json&limit=1';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'SakayTaApp/1.0 (${dotenv.env['EMAIL_NOMINATIM']})'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final displayName = data[0]['name'] ?? query; // Get the official name if available
          LatLng searchResult = LatLng(lat, lon);

          setState((){
            destinationPin = searchResult;
            _clearRoutingData();
            _currentDestinationName = displayName;
          });
        
          drawMapElements();

          if(sheetController.isAttached){
            sheetController.animateTo(0.26, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut,);
          }

          Future.delayed(const Duration(milliseconds: 400), (){
            maplibreController?.animateCamera(
              maplibre.CameraUpdate.newLatLngZoom(
                maplibre.LatLng(searchResult.latitude, searchResult.longitude), 16.0
              )
            );
          });

          await _saveToHistory(displayName, searchResult); // Save to Hive
          
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location not found in Davao City.'))
          );
        }
      }
    } catch (e) {
      debugPrint("Geocoding Error: $e");
    }
  }

  // --- NEW LOGIC: Centralized Data Invalidation ---
  // Call this ANY TIME the startPin or destinationPin changes or is removed.
  void _clearRoutingData() {
    suggestedRoutes.clear();
    selectedRoute = null;
    
    // Also clear any manual toggles to ensure the map is pristine
    for (var route in allRoutes) {
      route.isVisible = false;
    }
    
    // Note: We don't call setState or drawMapElements() here because 
    // we will call this method *inside* the existing setState blocks of your triggers.
  }

  // --- NEW LOGIC: MapLibre Imperative Drawing ---
  void drawMapElements() async {
    // 1. Clear the canvas of old lines and pins
    await maplibreController?.clearLines();
    await maplibreController?.clearCircles();
    await maplibreController?.clearSymbols();

    // --- CONTEXTUAL RENDERING GATEKEEPER ---
    if (_selectedIndex == 0) {
      // ==========================================
      // TAB 0: EXPLORE MODE
      // Goal: Only draw catalog routes from the checklist. 
      // Ignore start/dest pins and suggested routes.
      // ==========================================
      final visibleRoutes = allRoutes.where((r) => r.isVisible && r.polylineData != null);
      for (var route in visibleRoutes) {
        String hexColor = '#${route.color.value.toRadixString(16).substring(2)}';
        maplibreController?.addLine(maplibre.LineOptions(
          geometry: route.polylineData!.points.map((p) => maplibre.LatLng(p.latitude, p.longitude)).toList(),
          lineColor: hexColor,
          lineWidth: 4.0,
          lineOpacity: 1, // Slightly transparent so it doesn't clutter the map
        ));
      }
    }else{
      // ==========================================
      // TAB 1 & 2: ROUTING MODE (Locate & Search)
      // Goal: Only draw pins and the A-to-B suggested routing lines.
      // ==========================================

      // 1. Draw Custom Start Pin
      if (startPin != null) {
        maplibreController?.addSymbol(maplibre.SymbolOptions(
          geometry: maplibre.LatLng(startPin!.latitude, startPin!.longitude),
          iconImage: 'start-icon',
          iconSize: 0.7, 
          iconAnchor: 'bottom', 
        ));
      }

      // 2. Draw Custom Destination Pin
      if (destinationPin != null) {
        maplibreController?.addSymbol(maplibre.SymbolOptions(
          geometry: maplibre.LatLng(destinationPin!.latitude, destinationPin!.longitude),
          iconImage: 'dest-icon',
          iconSize: 0.7, 
          iconAnchor: 'bottom',
        ));
      }

      // 🔍 DEBUG: Only selected route points
      // if (selectedRoute != null) {
      //   final routeData = allRoutes.firstWhere((r) => r.name == selectedRoute!.routeName);

      //   for (var point in routeData.polylineData!.points) {
      //     maplibreController?.addCircle(
      //       maplibre.CircleOptions(
      //         geometry: maplibre.LatLng(point.latitude, point.longitude),
      //         circleRadius: 3.0,
      //         circleColor: "#0000FF", // blue
      //       ),
      //     );
      //   }
      // }

      // 3. Draw the Selected Route
      if (selectedRoute != null && startPin != null && destinationPin != null) {
        final routeData = allRoutes.firstWhere((r) => r.name == selectedRoute!.routeName);
        final points = routeData.polylineData!.points;

        // Calculate Jeepney Ride Points (Handling your Loop logic!)
        List<LatLng> ridePoints;
        if (selectedRoute!.boardIndex < selectedRoute!.alightIndex) {
          ridePoints = points.sublist(selectedRoute!.boardIndex, selectedRoute!.alightIndex + 1);
        } else {
          ridePoints = [
            ...points.sublist(selectedRoute!.boardIndex),
            ...points.sublist(0, selectedRoute!.alightIndex + 1),
          ];
        }

        String hexColor = '#${routeData.color.value.toRadixString(16).substring(2)}';

        // Command the GPU to draw the solid jeepney line
        maplibreController?.addLine(maplibre.LineOptions(
          geometry: ridePoints.map((p) => maplibre.LatLng(p.latitude, p.longitude)).toList(),
          lineColor: hexColor,
          lineWidth: 6.0,
        ));

        // Draw the Walking Paths (Start and End)
        final startWalkPoints = selectedRoute!.actualWalkPathStart ?? [startPin!, points[selectedRoute!.boardIndex]];
        final endWalkPoints = selectedRoute!.actualWalkPathEnd ?? [points[selectedRoute!.alightIndex], destinationPin!];

        // Walk to Jeepney
        maplibreController?.addLine(maplibre.LineOptions(
          geometry: startWalkPoints.map((p) => maplibre.LatLng(p.latitude, p.longitude)).toList(),
          lineColor: '#000000', // Black
          lineWidth: 3.0,
        ));

        // Walk to Destination
        maplibreController?.addLine(maplibre.LineOptions(
          geometry: endWalkPoints.map((p) => maplibre.LatLng(p.latitude, p.longitude)).toList(),
          lineColor: '#000000',
          lineWidth: 3.0,
        ));
      }
    }
  }

  // --- NEW LOGIC: Load Custom Images into MapLibre ---
  Future<void> _loadCustomPins() async {
    // Load Start Pin
    final ByteData startBytes = await rootBundle.load('assets/images/start_pin.png');
    final Uint8List startList = startBytes.buffer.asUint8List();
    await maplibreController?.addImage('start-icon', startList);

    // Load Destination Pin
    final ByteData destBytes = await rootBundle.load('assets/images/dest_pin.png');
    final Uint8List destList = destBytes.buffer.asUint8List();
    await maplibreController?.addImage('dest-icon', destList);
  }

  // --- NEW LOGIC: A reusable button builder ---
  Widget _buildPinButton({
    required String label,
    required String imagePath,
    required PinMode mode,
    required LatLng? pinData,
    required VoidCallback onTap,
  }) {
      bool isSelecting = currentPinMode == mode;
      bool isPlaced = pinData != null;

      Color bgColor = btnColor;
      Color txtColor = fontColor;
      Widget trailingIcon = const SizedBox.shrink();

      // The 3-State Visual Logic
      if (isPlaced) {
        bgColor = primaryColor; // STATE 3: Placed (Solid Primary Color)
        txtColor = fontColor;
        // Add a tiny checkmark to really sell the "Placed" state
        trailingIcon = const Padding(
          padding: EdgeInsets.only(left: 4), 
          child: Icon(Icons.check_circle, color: Colors.white, size: 16)
        );
      } else if (isSelecting) {
        bgColor = disableColor; // STATE 2: Selecting (Dimmed/Pulsing)
        txtColor = fontColor;
      } 
    // Otherwise, it falls back to STATE 1: Idle (btnColor)

    return SizedBox(
      width: 120, // Slightly wider to accommodate the new checkmark
      height: 40,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: txtColor,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          elevation: isPlaced ? 6 : (isSelecting ? 0 : 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Image.asset(imagePath, width: 24, height: 24),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
            trailingIcon, 
          ],
        ),
      ),
    );
  }

  // --- NEW LOGIC: Custom Navigation Button ---
  Widget _buildNavItem({required IconData icon, required String label, required int index}) {
    bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });

        drawMapElements();

        // We will add the actual logic (opening sheets, showing search bars) here later!
        if (sheetController.isAttached){
          sheetController.animateTo(
            _selectedIndex == 1 ? 0.26 : 0.96, 
            duration: const Duration(milliseconds: 300), 
            curve: Curves.easeInOut);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 123,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          // Replace Colors.purpleAccent with your 'selectedColor' variable
          color: isSelected ? primaryColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          //border: Border.all(color: Colors.black)
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Wrap tightly around the icon
          children: [
            Icon(
              icon,
              color: isSelected ? fontColor : unselectedNavColor, // Active vs Inactive colors
              size: 30,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? fontColor : unselectedNavColor,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            )
          ],
        ),
      ),
      );
  }

  // DRAGGABLE SCROLLABLE SHEET BUILDERS
  // --- LOCATE SHEET CONTENT ---
  List<Widget> _buildLocateContent() {
    if (suggestedRoutes.isEmpty) {
      return [
        const Text(
          'SUROY TA!',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor),
        ),
        const SizedBox(height: 10),
        const Text(
          'Welcome to SUROY TA! A Public Utility Jeepney (PUJ) Routing and Fare Estimation System design for Davaoeños',
          style: TextStyle(color: fontColor),
        ),
      ];
    } else {
      return [
        const Text(
          'Suggested Routes',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor),
        ),
        const SizedBox(height: 10),
        const Text(
          'Pick the jeep you wish to ride and it will give you the walking distance, and estimated fare.',
          style: TextStyle(color: fontColor),
        ),
        ...suggestedRoutes.map((result) {

          final startWalkText = result.actualStartWalk != null 
              ? '${result.actualStartWalk!.toStringAsFixed(0)}m'
              : '~${result.estimatedStartWalk.toStringAsFixed(0)}m';
              
          final endWalkText = result.actualEndWalk != null 
              ? '${result.actualEndWalk!.toStringAsFixed(0)}m'
              : '~${result.estimatedEndWalk.toStringAsFixed(0)}m';

          final fareText = 'Php ${result.estimatedFare.toStringAsFixed(2)}';
          final rideDistanceText = '${result.ridingDistanceKm.toStringAsFixed(1)} km';

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            child: ListTile(
              leading: const Icon(Icons.directions_bus, color: Colors.purple),
              title: Text(result.routeName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                'Walk to Jeep: $startWalkText | Jeep to Dest: $endWalkText\n'
                'Ride: $rideDistanceText | Est. Fare: $fareText'
              ),
              trailing: result.isFetchingActualRoute 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                setState(() {
                  selectedRoute = result;
                });
                drawMapElements();

                // Fetch OSRM only if we haven't yet
                if (result.actualStartWalk == null && startPin != null && destinationPin != null) {
                  setState(() { result.isFetchingActualRoute = true; });

                  final routeData = allRoutes.firstWhere((r) => r.name == result.routeName);
                  final boardPoint = routeData.polylineData!.points[result.boardIndex];
                  final alightPoint = routeData.polylineData!.points[result.alightIndex];

                  final startLeg = await fetchWalkingRouteFromOSRM(startPin!, boardPoint);
                  final endLeg = await fetchWalkingRouteFromOSRM(alightPoint, destinationPin!);

                  if (startLeg != null && endLeg != null) {
                    setState(() {
                      result.actualWalkPathStart = startLeg['path'];
                      result.actualWalkPathEnd = endLeg['path'];
                      result.actualStartWalk = startLeg['distance'];
                      result.actualEndWalk = endLeg['distance'];
                    });
                    drawMapElements();
                  }
                  
                  setState(() { result.isFetchingActualRoute = false; });
                }

                sheetController.animateTo(
                  0.26,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                );
              },
            ),
          );
        }),
      ];
    }
  }
  
  bool _isSelectAllChecked = false;
  bool _isSelectedRoute = false;
  // --- EXPLORE SHEET CONTENT ---
  List<Widget> _buildExploreContent() {
    final filteredRoutes = allRoutes.where((route) {
      return route.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Explore Routes',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor),
          ),
          GestureDetector(
            onTap: () {_toggleAllRoutes(false); _isSelectedRoute = false;},
            child: AnimatedScale(
              duration: Duration(milliseconds: 200),
              scale: _isSelectedRoute ? 1.0 : 0.0,
              curve: Curves.ease,
              child: Container(
              height: 35,
              width: 85,
              decoration: BoxDecoration(
                color: _isSelectedRoute ? deleteColor :sheetBackgroundColor,
                borderRadius: BorderRadius.circular(20),
                border: BoxBorder.all(
                  color: _isSelectedRoute ? darkDeleteColor :sheetBackgroundColor,
                  width: 3
                )
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: _isSelectedRoute ? fontColor :sheetBackgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded, 
                      color: _isSelectedRoute ? deleteColor :sheetBackgroundColor, 
                      size: 15
                    )
                  ),
                  SizedBox(width: 5),
                  Text(
                    "Clear",
                    style: TextStyle(
                      color: _isSelectedRoute ? fontColor : sheetBackgroundColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14
                    )
                  )
                ],
              )
            )
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
          'Discover the available jeepney routes in Davao City. Scroll or Search to find your specific route and Tap on the route.',
          style: TextStyle(color: fontColor),
        ),
      const SizedBox(height: 20),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search for a route...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: fontColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
      ),
      const SizedBox(height: 25),
      Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 5),
        elevation: 10,
        color: cardColor,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _isSelectAllChecked ? primaryColor : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: CheckboxListTile(
          title: Text("Select All Routes", style: const TextStyle(fontWeight: FontWeight.bold, color: fontColor)),
          value: _isSelectAllChecked,
          side: BorderSide(color: Colors.transparent, width: 2),
          activeColor: Colors.transparent,
          checkColor: Colors.transparent,
          secondary: const Icon(Icons.select_all_rounded, color: fontColor, size: 30),
          onChanged: (bool ? value){
            setState(() {
              _isSelectAllChecked = value ?? false;
            });

            if (value == true) {
              _toggleAllRoutes(true);  // Select all
              _isSelectedRoute = true;
            } else {
              _toggleAllRoutes(false); // Clear all
              _isSelectedRoute = false;
            }
          },
        ),
      ),
      const SizedBox(height: 20),
      ...filteredRoutes.map((route) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 5),
          clipBehavior: Clip.antiAlias,
          color: cardColor,
          elevation: 10,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: route.isVisible ? primaryColor : Colors.transparent, width: 2), // Add a border with the route color
            borderRadius: BorderRadius.circular(12),
          ),
          child: CheckboxListTile(
            title: Text(route.name, style: TextStyle(fontWeight: FontWeight.bold, color: fontColor)),
            value: route.isVisible,
            side: BorderSide(color: primaryColor, width: 2),
            activeColor: primaryColor,
            secondary: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: route.color,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.black26),
              ),
            ),
            onChanged: (bool? value) {
              handleRouteToggle(route);
            },
          ),
        );
      }),
      const SizedBox(height: 80), 
    ];
  }

  // --- SEARCH SHEET CONTENT ---
  List<Widget> _buildSearchContent() {
    // Fetch live data from the local database
    final historyList = _hiveService.getHistory();
    // Sort history so the newest is at the top
    historyList.sort((a, b) => b.id.compareTo(a.id)); 
    
    final favoritesList = _hiveService.getFavorites();

    return [
      const Text(
        'Asa Ta?',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor),
      ),
      const SizedBox(height: 10),
      const Text(
          'Find the location you wish to go by typing its name or paste its coordinates from external maps.',
          style: TextStyle(color: fontColor),
        ),
      const SizedBox(height: 20),
      
      // 1. THE DUAL-INPUT SEARCH BAR
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Search here...',
            prefixIcon: Icon(Icons.search),
            filled: true,
            fillColor: fontColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (value) {
            searchLocation(value);
          },
        ),
      ),
      const SizedBox(height: 24),

      // 2. FAVORITES SECTION (Horizontal Scroll)
      const Text(
        'Saved Places',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: fontColor),
      ),
      const SizedBox(height: 10),
      if (favoritesList.isEmpty)
        const Text(
          'No saved places yet. Long press a search result to save it here!',
          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
        )
      else
        SizedBox(
          height: 90, // Fixed height for the horizontal cards
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: favoritesList.length,
            itemBuilder: (context, index) {
              final fav = favoritesList[index];
              return GestureDetector(
                onTap: () {
                  // Jump directly to the favorite!
                  setState(() => destinationPin = LatLng(fav.latitude, fav.longitude));
                  drawMapElements();

                  if(sheetController.isAttached){
                    sheetController.animateTo(0.26, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut,);
                  }

                  Future.delayed(const Duration(milliseconds: 400), (){
                    maplibreController?.animateCamera(
                      maplibre.CameraUpdate.newLatLngZoom(
                        maplibre.LatLng(fav.latitude, fav.longitude), 16.0
                      )
                    );
                  });
                },
                child: Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(IconData(fav.iconCodePoint ?? 0, fontFamily: 'MaterialIcons'), color: primaryColor, size: 20),
                      const SizedBox(height: 8),
                      Text(
                        fav.name,
                        style: const TextStyle(color: fontColor, fontSize: 14, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 24),

      // 3. RECENT SEARCHES SECTION (Vertical List)
      const Text(
        'Recent Searches',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: fontColor),
      ),
      const SizedBox(height: 10),
      if (historyList.isEmpty)
        const Text(
          'Your recent searches will appear here.',
          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
        )
      else
        ...historyList.map((historyItem) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: cardColor,
              child: Icon(IconData(historyItem.iconCodePoint ?? 0, fontFamily: 'MaterialIcons'), color: unselectedNavColor),
            ),
            title: Text(historyItem.name, style: const TextStyle(color: fontColor, fontWeight: FontWeight.bold)),
            subtitle: Text('${historyItem.latitude.toStringAsFixed(4)}, ${historyItem.longitude.toStringAsFixed(4)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.close, color: Colors.grey, size: 20),
              onPressed: () async {
                // Delete from Hive and refresh UI
                await _hiveService.deleteLocation(historyItem.id);
                setState(() {}); 
              },
            ),
            onTap: () {
              // Clicking a history item instantly drops the pin there again
              setState(() => destinationPin = LatLng(historyItem.latitude, historyItem.longitude));

              drawMapElements();

              if(sheetController.isAttached){
                sheetController.animateTo(0.26, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut,);
              }

              Future.delayed(const Duration(milliseconds: 400), (){
                maplibreController?.animateCamera(
                  maplibre.CameraUpdate.newLatLngZoom(
                    maplibre.LatLng(historyItem.latitude, historyItem.longitude), 16.0
                  )
                );
              });
            },
          );
        }),
        
      const SizedBox(height: 80), // Bottom padding
    ];
  }
  
  // --- NEW LOGIC: Save to History ---
  Future<void> _saveToHistory(String name, LatLng coords) async {
    final history = _hiveService.getHistory();
    
    // Sort by ID (which is our timestamp) so the oldest is first
    history.sort((a, b) => a.id.compareTo(b.id));

    // If we already have 5, delete the oldest one before adding the new one
    if (history.length >= 5) {
      await _hiveService.deleteLocation(history.first.id);
    }

    final newHistoryItem = FavoriteLocation(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Using timestamp as unique ID
      name: name,
      latitude: coords.latitude,
      longitude: coords.longitude,
      iconCodePoint: Icons.restore.codePoint, // The 'reset/history' icon
      isFavorite: false, 
    );

    await _hiveService.saveLocation(newHistoryItem);
    
    // Refresh the UI to show the new history item
    setState(() {}); 
  }

  // --- NEW LOGIC: Check if current pin is a Favorite ---
  FavoriteLocation? _getCurrentFavorite() {
    if (destinationPin == null) return null;
    
    final favorites = _hiveService.getFavorites();
    
    for (var fav in favorites) {
      // Compare coordinates up to 4 decimal places to avoid micro-precision bugs
      if (fav.latitude.toStringAsFixed(4) == destinationPin!.latitude.toStringAsFixed(4) &&
          fav.longitude.toStringAsFixed(4) == destinationPin!.longitude.toStringAsFixed(4)) {
        return fav; // Found a match!
      }
    }
    return null; // No match found
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          // The Map Using MapLibre
          maplibre.MapLibreMap(
            // MapLibre natively takes the MapTiler style URL!
            styleString: 'https://api.maptiler.com/maps/streets-v4/style.json?key=${dotenv.env['MAPTILER_API_KEY']}',
            
            // MapLibre has its own CameraPosition and LatLng classes, so we use our alias
            initialCameraPosition: const maplibre.CameraPosition(
              target: maplibre.LatLng(7.0700, 125.6000), 
              zoom: 14.0,
            ),
            
            // Allow the user to rotate the map
            rotateGesturesEnabled: true,

            compassEnabled: true,
            compassViewMargins: const Point(16, 150),
            
            // Grab the controller once the C++ engine is ready
            onMapCreated: (maplibre.MapLibreMapController controller) {
              maplibreController = controller;
            },

            onStyleLoadedCallback: (){
              _loadCustomPins(); // Load our custom pin images into the GPU's memory
            },

            // Tap handling for dropping pins (using MapLibre's math)
            onMapClick: (Point<double> point, maplibre.LatLng coordinates) {
              // We convert MapLibre's LatLng back to our app's standard latlong2 format
              LatLng standardCoords = LatLng(coordinates.latitude, coordinates.longitude);
              
              setState(() {
                if (currentPinMode == PinMode.start) {
                  startPin = standardCoords;
                  currentPinMode = PinMode.none;
                  _clearRoutingData();
                } else if (currentPinMode == PinMode.destination) {
                  destinationPin = standardCoords;
                  _currentDestinationName = '';
                  currentPinMode = PinMode.none;
                  _clearRoutingData();
                }
                // (We will add the code to physically draw the pins here in the next step)
                drawMapElements();
              });
            },
            // This code limits the app to Davao City only
            // This prevents MapLibre to render parts of the map outside Davao City
            cameraTargetBounds: maplibre.CameraTargetBounds(
              maplibre.LatLngBounds(
                southwest: maplibre.LatLng(6.9000, 125.4000), // Southwest corner of Davao City
                northeast: maplibre.LatLng(7.2500, 125.9000), // Northeast corner of Davao City
              ),
            ),

            minMaxZoomPreference: const maplibre.MinMaxZoomPreference(11.0, 22.0),
          ),

          SafeArea(
            child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    height: 62,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: btnColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: btnColor.withOpacity(0.3),
                          offset: Offset(0, 20),
                          blurRadius: 20
                        )
                      ],
                    ),
                    child: Center(
                        child:Text(
                        "SUROY TA!",
                        style: TextStyle(
                          fontFamily: 'Cubao',
                          fontSize: 30,
                          color: fontColor,
                          shadows: [
                            Shadow(
                              offset: Offset(1, 4),
                              blurRadius: 7,
                              color: Colors.black.withOpacity(0.5)
                            )
                          ]
                        ),
                      ),
                    )
                  ),
                ),
          ),
 
          // --- NEW LAYER: The Dynamic Route Legend ---
          Positioned(
            top: 110, // Aligned perfectly with the Star button on the right
            left: 16,
            // The BoxConstraints prevent the legend from stretching too wide and covering the whole screen
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Builder(
                builder: (context) {
                  // 1. Filter out only the routes the user has actively checked
                  final visibleRoutes = allRoutes.where((r) => r.isVisible).toList();
                  
                  // 2. Determine if the legend should be shown
                  final bool showLegend = _selectedIndex == 0 && visibleRoutes.isNotEmpty;

                  return AnimatedOpacity(
                    opacity: showLegend ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !showLegend, // Don't block map touches if it's invisible
                      // AnimatedSize makes the card smoothly grow/shrink as items are added/removed
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: btnColor.withOpacity(0.8), // Slight transparency looks premium on maps
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min, 
                            children: [
                              const Text(
                                'Legend',
                                style: TextStyle(
                                  fontSize: 12, 
                                  fontWeight: FontWeight.bold, 
                                  color: fontColor,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              
                              // --- NEW: THE SCROLLABLE CAP ---
                              ConstrainedBox(
                                // Set the maximum height. 200.0 is roughly 6-7 routes before scrolling starts.
                                constraints: const BoxConstraints(maxHeight: 75.0), 
                                child: SingleChildScrollView(
                                  // This inner column holds the actual route items
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: visibleRoutes.map((route) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6.0),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // The Route Color Indicator
                                            Container(
                                              width: 16,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: route.color,
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            // The Route Name
                                            Expanded(
                                              child: Text(
                                                route.name,
                                                style: const TextStyle(
                                                  fontSize: 10, 
                                                  color: fontColor,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(), // .toList() is added back here for the inner Column
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
              ),
            ),
          ),
          
          // Dynamic Floating Buttons (Start & Target Pins on the Left, GPS & Find on the Right)
          AnimatedBuilder(
            animation: sheetController,
            builder: (context, child) {
              // 1. Get the current size of the sheet safely
              double currentSize = 0.18; // Default starting height
              if (sheetController.isAttached) {
                currentSize = sheetController.size;
              }

              // 2. THE CAP: Limit the size to 0.4 so the buttons stop moving up
              double cappedSize = currentSize > 0.4 ? 0.4 : currentSize;

              // 3. THE MATH: Calculate the exact pixel height
              double screenHeight = MediaQuery.of(context).size.height;
              // Add 16 pixels of padding so the buttons float nicely above the sheet's top edge
              double dynamicBottom = (screenHeight * cappedSize) + 16.0;

              // 4. THE FLOOR: Prevent the buttons from crashing into the navigation bar
              // When the sheet is at 0.0, the buttons must stay at 110
              if (dynamicBottom < 110.0) {
                dynamicBottom = 110.0;
              }

              // The master switch for the Find button
              bool canFind = startPin != null && destinationPin != null;

              return Positioned(
                bottom: dynamicBottom,
                left: 16,
                right: 16, // Stretching across the screen allows us to use MainAxisAlignment.spaceBetween
                child: AnimatedOpacity(
                  opacity: _selectedIndex == 0 ? 0.0 : 1.0, 
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: _selectedIndex == 0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end, // Aligns bottoms of both sides
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        
                        // --- LEFT SIDE: Start & Target Buttons ---
                        Row(
                          children: [
                            _buildPinButton(
                              label: 'Start', 
                              imagePath: 'assets/images/start_pin.png', 
                              mode: PinMode.start,
                              pinData: startPin,
                              onTap: (){
                                setState(() {
                                  if (startPin != null) {
                                    // Action 3: Clear the placed pin
                                    startPin = null;
                                    enableGPS = false; // Wiping the pin wipes GPS tracking
                                    currentPinMode = PinMode.none;
                                    _clearRoutingData();
                                  } else if (currentPinMode == PinMode.start) {
                                    // Action 2: Cancel selection
                                    currentPinMode = PinMode.none;
                                  } else {
                                    // Action 1: Enter selection mode
                                    currentPinMode = PinMode.start;
                                    enableGPS = false; // Mutually exclusive override!
                                  }
                                  drawMapElements();
                                });
                              }
                            ),
                            const SizedBox(width: 10),
                            _buildPinButton(
                              label: 'Target', 
                              imagePath: 'assets/images/dest_pin.png', 
                              mode: PinMode.destination,
                              pinData: destinationPin,
                              onTap: (){
                                setState(() {
                                  if (destinationPin != null) {
                                    destinationPin = null;
                                    currentPinMode = PinMode.none;
                                    _clearRoutingData();
                                  } else if (currentPinMode == PinMode.destination) {
                                    currentPinMode = PinMode.none;
                                  } else {
                                    currentPinMode = PinMode.destination;
                                  }
                                  drawMapElements();
                                });
                              }
                            ),
                          ],
                        ),

                        // --- RIGHT SIDE: GPS & Find Buttons ---
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FloatingActionButton(
                              heroTag: "btnGPS",
                              backgroundColor: enableGPS ? btnColor : disableColor,
                              onPressed: () {
                                getUserCurrentLocation();
                              },
                              // Make sure enableGPS and fontColor are defined in your state
                              child: Icon(enableGPS ? Icons.gps_fixed: Icons.gps_off, color: fontColor), 
                            ),
                            const SizedBox(height: 10),
                            FloatingActionButton.extended(
                              heroTag: "btnFind",
                              backgroundColor: canFind ? btnColor : disableColor,
                              onPressed: canFind ? () async {
                                if (startPin == null || destinationPin == null) {
                                  // Optional: Show a quick snackbar to the user
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please select Start and Destination on the map.')),
                                  );
                                  return;
                                }

                                Map<String, List<LatLng>> routePayload = {};
                                
                                for (var route in allRoutes) {
                                  route.polylineData ??= await parseRoute(route.filePath, route.color);
                                  routePayload[route.name] = route.polylineData!.points;
                                }

                                List<RouteResult> bestRoutes = await compute(
                                  processRoutesInBackground, 
                                  {
                                    'start': startPin,
                                    'dest': destinationPin,
                                    'routes': routePayload,
                                  }
                                );

                                // --- NEW LOGIC: Update State and Animate Sheet ---
                                setState(() {
                                  suggestedRoutes = bestRoutes;
                                  // Clear manual toggles to clean up the map for the new search
                                  for (var r in allRoutes) { r.isVisible = false; }
                                  selectedRoute = null; 
                                });

                                // Trigger the animation to push the sheet to the top of the screen
                                if (suggestedRoutes.isNotEmpty) {
                                  sheetController.animateTo(
                                    0.96,
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeInOut,
                                  );
                                } else {
                                  if(context.mounted){
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('No routes found.'))
                                    );
                                  }
                                }
                              } : () {
                                // If they tap the disabled button, gently tell them why
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please place both Start and Target pins first.')),
                                );
                              },
                              icon: const Icon(Icons.navigation, color: fontColor),
                              label: const Text("Find", style: TextStyle(color: fontColor, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // --- NEW LAYER: The Contextual Star Button ---
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: AnimatedScale(
              scale: (destinationPin != null && !_isSavePopupVisible && _selectedIndex != 0) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: Builder(
                builder: (context){
                  FavoriteLocation? currentFav = _getCurrentFavorite();
                  bool isSaved = currentFav != null;

                  return GestureDetector(
                    onTap: () async{
                      if(isSaved){
                        await _hiveService.deleteLocation(currentFav.id);
                        setState(() {});
                        if(context.mounted){
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Removed from Favorites'))
                          );
                        }
                      } else{
                        setState(() {
                          // Pre-fill the text field. If empty, keep it empty so the hint text shows.
                          _saveNameController.text = _currentDestinationName;
                          _isSavePopupVisible = true; // Trigger the drop-down animation!
                        });
                      }
                    },
                    child: Container(
                      height: 40,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: btnColor.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: btnColor.withOpacity(0.3),
                            offset: Offset(0, 20),
                            blurRadius: 20
                          )
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20), 
                        child:Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                isSaved
                                  ? currentFav.name
                                  : (destinationPin != null 
                                      ? '${destinationPin!.latitude.toStringAsFixed(4)}, ${destinationPin!.longitude.toStringAsFixed(4)}'
                                      : ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 20,
                                  color: fontColor,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1, 4),
                                      blurRadius: 7,
                                      color: Colors.black.withOpacity(0.5)
                                    )
                                  ]
                                ),
                              ),
                            ),
                            Icon(isSaved ? Icons.star : Icons.star_border, color: isSaved ? Colors.amber : Colors.white),
                          ],
                        )
                      )
                    ),
                  );
                }
              )
            ),
          ),
          
          // The Swipe-Up Bottom Sheet
          DraggableScrollableSheet(
            controller: sheetController, // Attached the remote control here
            initialChildSize: 0.96, 
            minChildSize: _selectedIndex == 1 ? 0.0 : 0.26,     
            maxChildSize: 0.96,
            snap: true,
            snapSizes: const [0.26],     
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: sheetBackgroundColor, 
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    if(_selectedIndex == 0) ..._buildExploreContent(),
                    if(_selectedIndex == 1) ..._buildLocateContent(),
                    if(_selectedIndex == 2) ..._buildSearchContent(),

                  ],
                ),
              );
            },
          ),

          // --- NEW LAYER: The Animated Drop-Down Overlay ---
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut, // That premium bounce effect
            top: _isSavePopupVisible ? 120 : -300, // Slides from off-screen to just below the header
            left: 16,
            right: 16,
            child: Card(
              color: btnColor,
              elevation: 15,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Save to Favorites?',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: fontColor),
                    ),
                    const SizedBox(height: 16),
                    // The Name Input Field
                    TextField(
                      controller: _saveNameController,
                      style: const TextStyle(color: sheetBackgroundColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Write the name of location...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: fontColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      destinationPin != null 
                          ? '${destinationPin!.latitude.toStringAsFixed(4)}, ${destinationPin!.longitude.toStringAsFixed(4)}'
                          : '',
                      style: const TextStyle(color: primaryColor, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() => _isSavePopupVisible = false); // Dismiss
                          },
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            // 1. Fallback name if they left it blank
                            final finalName = _saveNameController.text.trim().isEmpty 
                                ? 'Saved Location' 
                                : _saveNameController.text.trim();

                            // 2. Create the Hive Object
                            final newFav = FavoriteLocation(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              name: finalName,
                              latitude: destinationPin!.latitude,
                              longitude: destinationPin!.longitude,
                              iconCodePoint: Icons.star.codePoint, // Default to a star icon
                              isFavorite: true,
                            );

                            // 3. Save to database
                            await _hiveService.saveLocation(newFav);

                            // 4. Close the popup and notify user
                            setState(() {
                              _isSavePopupVisible = false;
                            });
                            
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Added to Favorites!')),
                              );
                            }
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // Navigation Bar
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 62,
          padding: const EdgeInsets.all(0),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: btnColor,
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: btnColor.withOpacity(0.3),
                offset: Offset(0, 20),
                blurRadius: 20
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNavItem(icon: Icons.map_outlined, label: "Explore", index: 0),
              _buildNavItem(icon: Icons.location_on, label: "Locate", index: 1),
              _buildNavItem(icon: Icons.search, label: "Search", index: 2),
            ],
          )
        ),
      )
    );
  }
}