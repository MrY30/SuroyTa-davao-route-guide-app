import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sakay_ta_mobile_app/services/geocoding_service.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/app_info_sheet.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/favorite_card.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/routes_legend.dart';
import 'package:sakay_ta_mobile_app/models/favorite_location.dart';
import 'package:sakay_ta_mobile_app/services/hive_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';
import 'package:sakay_ta_mobile_app/models/jeepney_route.dart';
import 'package:sakay_ta_mobile_app/models/route_result.dart';
import 'package:sakay_ta_mobile_app/services/osrm_service.dart';
import 'package:sakay_ta_mobile_app/core/route_math.dart';

// PHASE 3
import 'package:sakay_ta_mobile_app/ui/widgets/floating_route_card.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/custom_pin_button.dart';

// PHASE 3 PART 2
import 'package:sakay_ta_mobile_app/ui/widgets/app_header.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/custom_navigation_bar.dart';
import 'package:sakay_ta_mobile_app/services/location_service.dart';

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

  await Hive.openBox('settings_box');

  runApp(const SakayTaApp());
}

class SakayTaApp extends StatelessWidget {
  const SakayTaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Suroy Ta',
      debugShowCheckedModeBanner: false, // Removes the debug banner
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: btnColor),
        useMaterial3: true,
        // fontFamily: GoogleFonts.lexend().fontFamily OPTION 1
        fontFamily: GoogleFonts.outfit().fontFamily, //OPTION 2
        // fontFamily: GoogleFonts.paytoneOne().fontFamily
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

enum PinMode { none, start, destination }
PinMode currentPinMode = PinMode.none;
LatLng? startPin;
LatLng? destinationPin;
bool enableGPS = false;

// --- NEW STATE: Explore Tab Search ---
final TextEditingController _searchController = TextEditingController();
String _searchQuery = '';

// --- NEW STATE: Database Service ---
final HiveService _hiveService = HiveService(); 

// PHASE 2
final OsrmService _osrmService = OsrmService();

final LocationService _locationService = LocationService();
final GeocodingService _geocodingService = GeocodingService();

class _MapScreenState extends State<MapScreen> {
  List<JeepneyRoute> allRoutes = [];

  // --- NEW STATE VARIABLES ---
  final DraggableScrollableController sheetController = DraggableScrollableController();
  final MapController mapController = MapController();
  List<RouteResult> suggestedRoutes = [];
  RouteResult? selectedRoute;

  maplibre.MapLibreMapController? maplibreController; // NEW: The native GPU controller

  int _selectedIndex = 1;
  bool _showFloatingCard = false;

  @override
  void initState() {
    super.initState();
    initializeRouteList();

    // --- THE STARTUP LOGIC ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ask Hive: Does the user want to see the info?
      if (_hiveService.getShowInfoOnStartup()) {
        // If yes (or if it's their very first time), show it!
        // _showAppInfoModal(context);
        showAppInfoSheet(context);
      }
    });
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
  // --- Fetching Walking Route using OSRM ---

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
      sheetController.animateTo(
        0.26,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      // _showCustomToast("Loading all routes on map", icon: Icons.notifications);
      Fluttertoast.showToast(msg: 'Loading all routes on map', backgroundColor: cardColor);
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

  void _clearRoutingData() {
    suggestedRoutes.clear();
    selectedRoute = null;
    
    // Also clear any manual toggles to ensure the map is pristine
    for (var route in allRoutes) {
      route.isVisible = false;
    }
    
    // Note: We don't call setState or drawMapElements() here because 
    // we will call this method *inside* the existing setState blocks of your triggers.

    // --- THE FIX: Hide the sheet if we are currently on the Locate tab ---
    if (_selectedIndex == 1 && sheetController.isAttached) {
      sheetController.animateTo(
        0.0, // Slide completely off-screen
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _updateDashedLine(String sourceId, String layerId, List<LatLng> points) async {
    // 1. Strict formatting: Ensure it's a FeatureCollection. 
    // If we have less than 2 points, pass an empty map to clear the line safely.
    Map<String, dynamic> geoJson;
    
    if (points.length < 2) {
      geoJson = {
        "type": "FeatureCollection",
        "features": []
      };
    } else {
      geoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "LineString",
              "coordinates": points.map((p) => [p.longitude, p.latitude]).toList()
            }
          }
        ]
      };
    }

    try {
      // 2. The Professional Way: Just update the data pipeline!
      await maplibreController?.setGeoJsonSource(sourceId, geoJson);
    } catch (e) {
      // 3. If it fails, the source doesn't exist yet. Create it once.
      await maplibreController?.addSource(sourceId, maplibre.GeojsonSourceProperties(data: geoJson));
      await maplibreController?.addLineLayer(
        sourceId, 
        layerId, 
        maplibre.LineLayerProperties(
          lineColor: '#184A46',
          lineWidth: 5.0,
          lineDasharray: [2.0, 2.0], 
        )
      );
    }
  }

  // --- NEW LOGIC: MapLibre Imperative Drawing ---
  void drawMapElements() async {
    // 1. Clear the canvas of old lines and pins
    await maplibreController?.clearLines();
    await maplibreController?.clearCircles();
    await maplibreController?.clearSymbols();


    // 2. Clear custom Sources and Layers (for our dashed lines)
    // We wrap this in a try-catch because it will throw an error on the very first 
    // run if the layers don't exist yet, which is totally fine!
    // 2. SAFELY CLEAR the dashed lines (sends an empty array)
    await _updateDashedLine('start-walk-source', 'start-walk-layer', []);
    await _updateDashedLine('end-walk-source', 'end-walk-layer', []);

    // --- NEW: Clear the main route and arrows ---
    await _updateMainRouteWithArrows('main-route-source', 'main-route-line-layer', 'main-route-arrow-layer', [], '#000000');

    // 4. SAFELY CLEAR all Explore Mode lines (This ensures unchecked routes disappear)
    for (var route in allRoutes) {
      await _updateMainRouteWithArrows(
        'explore-source-${route.name}', 
        'explore-line-${route.name}', 
        'explore-arrow-${route.name}', 
        [], 
        '#FFFFFF'
      );
    }
    
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

        // Command the GPU to draw the solid jeepney line AND the arrows
        // Use dynamic IDs based on the route name so they don't overwrite each other!
        String sourceId = 'explore-source-${route.name}';
        String lineId = 'explore-line-${route.name}';
        String arrowId = 'explore-arrow-${route.name}';

        await _updateMainRouteWithArrows(
          sourceId, 
          lineId, 
          arrowId, 
          route.polylineData!.points, // <-- FIX: Use the full route coordinates here
          hexColor
        );
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

        // String hexColor = '#${routeData.color.value.toRadixString(16).substring(2)}';
        String hexColor = '#42c585';

        // Command the GPU to draw the solid jeepney line AND the arrows
        await _updateMainRouteWithArrows(
          'main-route-source', 
          'main-route-line-layer', 
          'main-route-arrow-layer', 
          ridePoints, 
          hexColor
        );

        // Draw the Walking Paths (Start and End)
        final startWalkPoints = selectedRoute!.actualWalkPathStart ?? [startPin!, points[selectedRoute!.boardIndex]];
        final endWalkPoints = selectedRoute!.actualWalkPathEnd ?? [points[selectedRoute!.alightIndex], destinationPin!];

        await _updateDashedLine('start-walk-source', 'start-walk-layer', startWalkPoints);
        await _updateDashedLine('end-walk-source', 'end-walk-layer', endWalkPoints);

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

    // --- NEW: Load the Directional Arrow ---
    final ByteData arrowBytes = await rootBundle.load('assets/images/arrow.png'); 
    final Uint8List arrowList = arrowBytes.buffer.asUint8List();
    await maplibreController?.addImage('route-arrow', arrowList);

  }

  List<Widget> _suggestedRoutesSheet(){

    // --- STEP 1: SORT THE ROUTES ---
    // We sort by Fare first. If Fare is equal, we sort by Walking Distance.
    suggestedRoutes.sort((a, b){
      int fareComparison = a.estimatedFare.compareTo(b.estimatedFare);
      if (fareComparison != 0){
        return fareComparison;
      }
      return a.totalEstimatedWalk.compareTo(b.totalEstimatedWalk);
    });
    return [
        Text(
          'Suggested Routes',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor, fontFamily: GoogleFonts.paytoneOne().fontFamily),
        ),
        const SizedBox(height: 10),
        const Text(
          'Pick the jeep you wish to ride and it will give you the walking distance, and estimated fare.',
          style: TextStyle(color: fontColor),
        ),
        ...suggestedRoutes.asMap().entries.map((entry){

          final int index = entry.key;
          final RouteResult result = entry.value;

          final bool isBestRoute = index == 0;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 15.0),
            color: btnColor,
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              // side: isBestRoute ? const BorderSide(color: primaryColor, width: 0) : BorderSide.none
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                // 1. ANIMATION: If the card is already showing, slide it UP first
                if (_showFloatingCard) {
                  setState(() { _showFloatingCard = false; });
                  // Wait for it to slide up out of view before changing the data
                  await Future.delayed(const Duration(milliseconds: 300)); 
                }
                
                setState(() { selectedRoute = result;});
                drawMapElements();

                // 3. Slide the sheet DOWN to get it out of the way
                if (sheetController.isAttached) {
                  sheetController.animateTo(
                    0.26, // Almost minimized, but leaves a grab handle visible
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
                
                // 4. ANIMATION: Slide the top card DOWN with the new data
                setState(() { _showFloatingCard = true; });

                // Fetch OSRM only if we haven't yet
                if (result.actualStartWalk == null && startPin != null && destinationPin != null) {
                  setState(() { result.isFetchingActualRoute = true; });

                  final routeData = allRoutes.firstWhere((r) => r.name == result.routeName);
                  final boardPoint = routeData.polylineData!.points[result.boardIndex];
                  final alightPoint = routeData.polylineData!.points[result.alightIndex];

                  // switched to ORS from OSRM
                  final startLeg = await _osrmService.fetchWalkingRoute(startPin!, boardPoint);
                  final endLeg = await _osrmService.fetchWalkingRoute(alightPoint, destinationPin!);

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
              },
              child: Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    isBestRoute ? Icon(Icons.star_outline, size: 35, color: fontColor) : Image.asset('assets/images/jeep_logo.png', width: 35, height: 35),
                    const SizedBox(width: 16,),
                    // 2. MIDDLE TEXT (Route Name & Tag)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center, // Vertically centers the texts inside the fixed 75px height
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible( // Flexible ensures the font shrinks if it hits the edges
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                result.routeName, 
                                style: TextStyle(
                                  color: fontColor, 
                                  fontSize: 25, 
                                  // fontFamily: 'Cubao',
                                  fontFamily: GoogleFonts.paytoneOne().fontFamily,
                                  height: 1.0, // <-- CRITICAL: Removes invisible font padding!
                                  shadows: [
                                    Shadow(
                                      offset: const Offset(1, 4),
                                      blurRadius: 7,
                                      color: Colors.black.withOpacity(0.5),
                                    )
                                  ] 
                                )
                              ),
                            ),
                          ),
                          // THE TAG: Fits neatly underneath without expanding the card
                          if (isBestRoute)
                          const Padding(
                            padding: EdgeInsets.only(top: 2.0),
                            child: Text(
                              'RECOMMENDED', 
                              style: TextStyle(
                                color: primaryColor, 
                                fontSize: 10, 
                                fontWeight: FontWeight.bold, 
                                height: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    result.isFetchingActualRoute
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward_ios, size: 16, color: fontColor),
                  ],
                ),
              )
            )
          );
        }
      ),
      const SizedBox(height: 80,)
    ];
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
          Text(
            'Kabalo Ba Ka?',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: primaryColor, fontFamily: GoogleFonts.paytoneOne().fontFamily),
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
      // const Text(
      //     'Discover the available jeepney routes in Davao City. Scroll or Search to find your specific route and Tap on the route.',
      //     style: TextStyle(color: fontColor),
      //   ),
      SizedBox(
        height: 40, 
        child: AutoSizeText(
          'Discover the available jeepney routes in Davao City. Scroll or Search to find your specific route and Tap on the route.',
          style: const TextStyle(
            color: fontColor, 
            fontSize: 16, // The starting maximum size
            height: 1.2,
          ),
          maxLines: 2, 
          minFontSize: 10, // Prevents it from becoming microscopically small
          overflow: TextOverflow.ellipsis, // Failsafe
        ),
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
              borderRadius: BorderRadius.circular(15),
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
      Text(
        'Asa Ta?',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: primaryColor, fontFamily: GoogleFonts.paytoneOne().fontFamily),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 40, 
        child: AutoSizeText(
          'Search a location by typing its name or pasting its coordinates from external maps using the Search Bar.',
          style: const TextStyle(
            color: fontColor, 
            fontSize: 16, // The starting maximum size
            height: 1.2,
          ),
          maxLines: 2, 
          minFontSize: 10, // Prevents it from becoming microscopically small
          overflow: TextOverflow.ellipsis, // Failsafe
        ),
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
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (value) async {
            // searchLocation(value);
            GeocodeResult? geocodeResult = await _geocodingService.searchLocation(value);

            if(geocodeResult != null){
              setState((){
                destinationPin = geocodeResult.coordinates;
                _clearRoutingData();
                _currentDestinationName = geocodeResult.name;
              });
                
              drawMapElements();

              if(sheetController.isAttached){
                sheetController.animateTo(0.26, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut,);
              }

              Future.delayed(const Duration(milliseconds: 400), (){
                maplibreController?.animateCamera(
                  maplibre.CameraUpdate.newLatLngZoom(
                    maplibre.LatLng(geocodeResult.coordinates.latitude, geocodeResult.coordinates.longitude), 16.0
                  )
                );
              });
                
              await _saveToHistory(geocodeResult.name, geocodeResult.coordinates); // Save to Hive
            }
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
  
  Future<void> _updateMainRouteWithArrows(String sourceId, String lineLayerId, String symbolLayerId, List<LatLng> points, String hexColor) async {
    // 1. Format the coordinates as a GeoJSON LineString
    Map<String, dynamic> geoJson = {
      "type": "FeatureCollection",
      "features": points.isEmpty ? [] : [
        {
          "type": "Feature",
          "geometry": {
            "type": "LineString",
            "coordinates": points.map((p) => [p.longitude, p.latitude]).toList()
          }
        }
      ]
    };

    try {
      // If the source exists, just update the data (Super fast!)
      await maplibreController?.setGeoJsonSource(sourceId, geoJson);
    } catch (e) {
      // --- THE FIX ---
      // If the source doesn't exist, and we are just passing an empty array to clear it,
      // simply return. Do NOT create a ghost layer with a #000000 default color!
      if (points.isEmpty) return;
      
      // If it fails, create the Source and both Layers once
      await maplibreController?.addSource(sourceId, maplibre.GeojsonSourceProperties(data: geoJson));

      // Layer 1: The Solid Route Line
      await maplibreController?.addLineLayer(
        sourceId, 
        lineLayerId, 
        maplibre.LineLayerProperties(
          lineColor: hexColor,
          lineWidth: 6.0,
        )
      );

      // Layer 2: The Directional Arrows tied to the exact same Source
      await maplibreController?.addSymbolLayer(
        sourceId, 
        symbolLayerId, 
        maplibre.SymbolLayerProperties(
          symbolPlacement: 'line',         // <-- The Mapbox/MapLibre magic property
          iconImage: 'route-arrow',        // Matches the ID from _loadCustomPins
          iconSize: 0.3,                   // Scale your PNG down or up here
          iconKeepUpright: false,          // Ensures the arrow points along the line, not strictly up
          symbolSpacing: 100,              // Adds padding between repeating arrows so it isn't cluttered
        )
      );
    }
  }
  
  void _handleTabChanged(int targetIndex) {                 
    setState(() {
      _selectedIndex = targetIndex;
    });

    drawMapElements();

    // if (sheetController.isAttached){
    //   sheetController.animateTo(
    //     _selectedIndex == 1 ? 0.26 : 0.96, 
    //     duration: const Duration(milliseconds: 300), 
    //     curve: Curves.easeInOut);
    // }

    if (sheetController.isAttached) {
      double targetSize = 0.96; // Default height for Explore (0) and Search (2)
      
      if (_selectedIndex == 1) {
        // If we are on Locate (1), check if we have routes!
        // If yes, peek at 0.26. If no, hide completely at 0.0.
        targetSize = suggestedRoutes.isNotEmpty ? 0.26 : 0.0;
      }

      sheetController.animateTo(
        targetSize, 
        duration: const Duration(milliseconds: 300), 
        curve: Curves.easeInOut
      );
    }
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
    FavoriteLocation? currentFav = _getCurrentFavorite();
    bool isSaved = currentFav != null;
    String displayTitle = isSaved ? currentFav.name : (destinationPin != null 
        ? '${destinationPin!.latitude.toStringAsFixed(4)}, ${destinationPin!.longitude.toStringAsFixed(4)}'
        : '');
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          // Map Section: Displays The Map of Davao City Using MapLibre
          maplibre.MapLibreMap(
            // MapLibre natively takes the MapTiler style URL!
            // styleString: 'https://api.maptiler.com/maps/streets-v4/style.json?key=${dotenv.env['MAPTILER_API_KEY']}',
            styleString: 'https://api.maptiler.com/maps/019d2d1a-6040-7d1b-be05-18e6303d1ff8/style.json?key=${dotenv.env['MAPTILER_API_KEY']}',
            
            // MapLibre has its own CameraPosition and LatLng classes, so we use our alias
            initialCameraPosition: const maplibre.CameraPosition(
              // target: maplibre.LatLng(7.0700, 125.6000),
              target: maplibre.LatLng(7.0640, 125.6080),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- App Header: Displays "SUROY TA!" which is the name of the app ---
                  AppHeader(
                    onClick: () {
                      showAppInfoSheet(context); 
                    }
                  ),
                  const SizedBox(height: 8),
                  // --- Legend for Explore tab: Displays the selected routes to Explore its coverage ---
                  // _buildLegendWidget(),
                  RoutesLegend(
                    visibleRoutes: allRoutes.where((r) => r.isVisible).toList(), 
                    selectedIndex: _selectedIndex,
                  ),
                  // --- The Favorite Card: Displays the coordinates of the destination pin and allows user to save it to favorites ---
                  FavoriteCard(
                    isVisible: (destinationPin != null && !_isSavePopupVisible && _selectedIndex != 0),
                    isSaved: isSaved,
                    displayTitle: displayTitle, 
                    onClick: () async{
                      if(isSaved){
                        await _hiveService.deleteLocation(currentFav.id);
                        setState(() {});
                        if(context.mounted){
                          // _showCustomToast("Removed from Favorites", icon: Icons.notifications);
                          Fluttertoast.showToast(msg: 'Removed from Favorites', backgroundColor: cardColor);
                        }
                      } else{
                        setState(() {
                          // Pre-fill the text field. If empty, keep it empty so the hint text shows.
                          _saveNameController.text = _currentDestinationName;
                          _isSavePopupVisible = true; // Trigger the drop-down animation!
                        });
                      }
                    }
                  ),
                ],
              )
            ),
          ),
          FloatingRouteCard(
            route: selectedRoute,
            isVisible: (_showFloatingCard && _selectedIndex == 1), 
            onClose: () async {
              setState(() { _showFloatingCard = false;});
              if (sheetController.isAttached) {
                sheetController.animateTo(0.4, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
              }

              // 3. THE FIX: Wait for the card to finish sliding off-screen
              await Future.delayed(const Duration(milliseconds: 300));

              // 4. Safely clear the data and redraw the map
              // The 'mounted' check is a best practice to ensure the screen still exists
              if (mounted) {
                setState(() { selectedRoute = null; });
                drawMapElements(); // Commands MapLibre to clear the jeepney line
              }
            }
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
                            CustomPinButton(
                              label: 'Start', 
                              imagePath: 'assets/images/start_pin.png', 
                              mode: PinMode.start,
                              currentMode: currentPinMode,
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
                            CustomPinButton(
                              label: 'Target', 
                              imagePath: 'assets/images/dest_pin.png', 
                              mode: PinMode.destination,
                              currentMode: currentPinMode,
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
                              onPressed: () async {
                                final LatLng? userLatLng = await _locationService.getGPSLocation();

                                if(userLatLng!= null){
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
                                  // _showCustomToast("Please select Start and Target on the map.", icon: Icons.notifications);
                                  Fluttertoast.showToast(msg: 'Please select Start and Target on the map.', backgroundColor: cardColor);
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
                                  _selectedIndex = 1;
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
                                    // _showCustomToast("No routes found.", icon: Icons.notifications);
                                    Fluttertoast.showToast(msg: 'No routes found.', backgroundColor: cardColor);
                                  }
                                }
                              } : () {
                                // If they tap the disabled button, gently tell them why
                                // _showCustomToast("Please place both Start and Target pins first.", icon: Icons.notifications);
                                Fluttertoast.showToast(msg: 'Please place both Start and Target pins first.', backgroundColor: cardColor);
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

          // The Swipe-Up Bottom Sheet
          DraggableScrollableSheet(
            controller: sheetController, // Attached the remote control here
            initialChildSize: 0.0, 
            minChildSize: 0.0,     
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
                    // if(_selectedIndex == 1) ..._buildLocateContent(),
                    if(_selectedIndex == 1 && suggestedRoutes.isNotEmpty) ..._suggestedRoutesSheet(),
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
                            FocusManager.instance.primaryFocus?.unfocus();
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
                            FocusManager.instance.primaryFocus?.unfocus();
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

                            // 3. THE FIX: Wait 300ms for the keyboard to physically leave the screen
                            // await Future.delayed(const Duration(milliseconds: 300));

                            // 4. Close the popup and notify user
                            setState(() {
                              _isSavePopupVisible = false;
                            });
                            
                            if (context.mounted) {
                              // _showCustomToast("Added to Favorites!", icon: Icons.notifications);
                              Fluttertoast.showToast(msg: 'Added to Favorites!', backgroundColor: cardColor);
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
              CustomNavigationBar(
                icon: Icons.map_outlined, 
                label: "Explore", 
                index: 0,
                selectedIndex: _selectedIndex, 
                onTap: () => _handleTabChanged(0)
              ),
              CustomNavigationBar(
                icon: Icons.location_on, 
                label: "Locate", 
                index: 1,
                selectedIndex: _selectedIndex, 
                onTap: () => _handleTabChanged(1)
              ),
              CustomNavigationBar(
                icon: Icons.search, 
                label: "Search", 
                index: 2,
                selectedIndex: _selectedIndex, 
                onTap: () => _handleTabChanged(2)
              )
            ],
          )
        ),
      )
    );
  }
}