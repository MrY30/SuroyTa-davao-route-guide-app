import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'dart:math';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakay_ta_mobile_app/providers/map_state_provider.dart';
import 'package:sakay_ta_mobile_app/providers/route_state_provider.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/app_info_sheet.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/favorite_card.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/routes_legend.dart';
import 'package:sakay_ta_mobile_app/models/favorite_location.dart';
import 'package:sakay_ta_mobile_app/services/hive_service.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';
import 'package:sakay_ta_mobile_app/models/jeepney_route.dart';
import 'package:sakay_ta_mobile_app/models/route_result.dart';
import 'package:sakay_ta_mobile_app/core/route_math.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/floating_route_card.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/custom_pin_button.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/app_header.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/custom_navigation_bar.dart';
import 'package:sakay_ta_mobile_app/services/location_service.dart';
import 'package:sakay_ta_mobile_app/ui/widgets/draggable_scrollable_sheet.dart';


enum PinMode { none, start, destination }

PinMode currentPinMode = PinMode.none;
bool enableGPS = false;

final HiveService _hiveService = HiveService();
final LocationService _locationService = LocationService();

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {

  final DraggableScrollableController sheetController = DraggableScrollableController();
  final MapController mapController = MapController();

  maplibre.MapLibreMapController?
  maplibreController;

  int _selectedIndex = 1;
  bool _showFloatingCard = false;

  @override
  void initState() {
    super.initState();
    // initializeRouteList();

    // --- THE STARTUP LOGIC ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(routeStateProvider.notifier).initializeRouteList();
      // Ask Hive: Does the user want to see the info?
      if (_hiveService.getShowInfoOnStartup()) {
        // If yes (or if it's their very first time), show it!
        // _showAppInfoModal(context);
        showAppInfoSheet(context);
      }
    });
  }


  bool _isSavePopupVisible = false;
  String _currentDestinationName = '';
  final TextEditingController _saveNameController = TextEditingController();

  @override
  void dispose() {
    // Always dispose controllers to prevent memory leaks!
    _saveNameController.dispose();
    super.dispose();
  }

  void _clearRoutingData() {
    ref.read(routeStateProvider.notifier).clearRoutingData();

    if (_selectedIndex == 1 && sheetController.isAttached) {
      sheetController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _updateDashedLine(
    String sourceId,
    String layerId,
    List<LatLng> points,
  ) async {
    // 1. Strict formatting: Ensure it's a FeatureCollection.
    // If we have less than 2 points, pass an empty map to clear the line safely.
    Map<String, dynamic> geoJson;

    if (points.length < 2) {
      geoJson = {"type": "FeatureCollection", "features": []};
    } else {
      geoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "LineString",
              "coordinates": points
                  .map((p) => [p.longitude, p.latitude])
                  .toList(),
            },
          },
        ],
      };
    }

    try {
      // 2. The Professional Way: Just update the data pipeline!
      await maplibreController?.setGeoJsonSource(sourceId, geoJson);
    } catch (e) {
      // 3. If it fails, the source doesn't exist yet. Create it once.
      await maplibreController?.addSource(
        sourceId,
        maplibre.GeojsonSourceProperties(data: geoJson),
      );
      await maplibreController?.addLineLayer(
        sourceId,
        layerId,
        maplibre.LineLayerProperties(
          lineColor: '#184A46',
          lineWidth: 5.0,
          lineDasharray: [2.0, 2.0],
        ),
      );
    }
  }

  // --- NEW LOGIC: MapLibre Imperative Drawing ---
  void drawMapElements() async {

    // 1. Read the current pins directly from Riverpod!
    final mapState = ref.read(mapStateProvider);
    final startPin = mapState.startPin;
    final destinationPin = mapState.destinationPin;

    // 2. THE FIX: Read the route data directly from Riverpod!
    final routeState = ref.read(routeStateProvider);
    final allRoutes = routeState.allRoutes;
    final selectedRoute = routeState.selectedRoute;

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
    await _updateMainRouteWithArrows(
      'main-route-source',
      'main-route-line-layer',
      'main-route-arrow-layer',
      [],
      '#000000',
    );

    // 4. SAFELY CLEAR all Explore Mode lines (This ensures unchecked routes disappear)
    for (var route in allRoutes) {
      await _updateMainRouteWithArrows(
        'explore-source-${route.name}',
        'explore-line-${route.name}',
        'explore-arrow-${route.name}',
        [],
        '#FFFFFF',
      );
    }

    // --- CONTEXTUAL RENDERING GATEKEEPER ---
    if (_selectedIndex == 0) {
      // ==========================================
      // TAB 0: EXPLORE MODE
      // Goal: Only draw catalog routes from the checklist.
      // Ignore start/dest pins and suggested routes.
      // ==========================================
      final visibleRoutes = allRoutes.where(
        (r) => r.isVisible && r.polylineData != null,
      );
      for (var route in visibleRoutes) {
        String hexColor =
            '#${route.color.value.toRadixString(16).substring(2)}';

        // Command the GPU to draw the solid jeepney line AND the arrows
        // Use dynamic IDs based on the route name so they don't overwrite each other!
        String sourceId = 'explore-source-${route.name}';
        String lineId = 'explore-line-${route.name}';
        String arrowId = 'explore-arrow-${route.name}';

        await _updateMainRouteWithArrows(
          sourceId,
          lineId,
          arrowId,
          route
              .polylineData!
              .points,
          hexColor,
        );
      }
    } else {
      // ==========================================
      // TAB 1 & 2: ROUTING MODE (Locate & Search)
      // Goal: Only draw pins and the A-to-B suggested routing lines.
      // ==========================================

      // Draw Start Pin
      if (startPin != null) {
        maplibreController?.addSymbol(
          maplibre.SymbolOptions(
            geometry: maplibre.LatLng(startPin.latitude, startPin.longitude),
            iconImage: 'start-icon',
            iconSize: 0.7,
            iconAnchor: 'bottom',
          ),
        );
      }

      // Draw Destination Pin
      if (destinationPin != null) {
        maplibreController?.addSymbol(
          maplibre.SymbolOptions(
            geometry: maplibre.LatLng(
              destinationPin.latitude,
              destinationPin.longitude,
            ),
            iconImage: 'dest-icon',
            iconSize: 0.7,
            iconAnchor: 'bottom',
          ),
        );
      }

      // 3. Draw the Selected Route
      if (selectedRoute != null && startPin != null && destinationPin != null) {
        final routeData = allRoutes.firstWhere(
          (r) => r.name == selectedRoute.routeName,
        );
        final points = routeData.polylineData!.points;

        // Calculate Jeepney Ride Points (Handling your Loop logic!)
        List<LatLng> ridePoints;
        if (selectedRoute.boardIndex < selectedRoute.alightIndex) {
          ridePoints = points.sublist(
            selectedRoute.boardIndex,
            selectedRoute.alightIndex + 1,
          );
        } else {
          ridePoints = [
            ...points.sublist(selectedRoute.boardIndex),
            ...points.sublist(0, selectedRoute.alightIndex + 1),
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
          hexColor,
        );

        // Draw the Walking Paths (Start and End)
        final startWalkPoints =
            selectedRoute.actualWalkPathStart ??
            [startPin, points[selectedRoute.boardIndex]];
        final endWalkPoints =
            selectedRoute.actualWalkPathEnd ??
            [points[selectedRoute.alightIndex], destinationPin];

        await _updateDashedLine(
          'start-walk-source',
          'start-walk-layer',
          startWalkPoints,
        );
        await _updateDashedLine(
          'end-walk-source',
          'end-walk-layer',
          endWalkPoints,
        );
      }
    }
  }

  void _handleLocationFound(LatLng coords, String name) {
    ref.read(mapStateProvider.notifier).setDestinationPin(coords);
    setState(() {
      _clearRoutingData();
      _currentDestinationName = name;
    });
    
    drawMapElements();

    if (sheetController.isAttached) {
      sheetController.animateTo(
        0.26,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }

    Future.delayed(const Duration(milliseconds: 400), () {
      maplibreController?.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(coords.latitude, coords.longitude),
          16.0,
        ),
      );
    });
  }
  
  Future<void> _handleShowFloatingCard() async {
    // 1. If it is already showing, slide it up out of view first
    if (_showFloatingCard) {
      setState(() { _showFloatingCard = false; });
      await Future.delayed(const Duration(milliseconds: 300));
    }
    
    // 2. Slide it down with the fresh data
    setState(() { _showFloatingCard = true; });
  }
  // --- NEW LOGIC: Load Custom Images into MapLibre ---
  Future<void> _loadCustomPins() async {
    // Load Start Pin
    final ByteData startBytes = await rootBundle.load(
      'assets/images/start_pin.png',
    );
    final Uint8List startList = startBytes.buffer.asUint8List();
    await maplibreController?.addImage('start-icon', startList);

    // Load Destination Pin
    final ByteData destBytes = await rootBundle.load(
      'assets/images/dest_pin.png',
    );
    final Uint8List destList = destBytes.buffer.asUint8List();
    await maplibreController?.addImage('dest-icon', destList);

    // --- NEW: Load the Directional Arrow ---
    final ByteData arrowBytes = await rootBundle.load(
      'assets/images/arrow.png',
    );
    final Uint8List arrowList = arrowBytes.buffer.asUint8List();
    await maplibreController?.addImage('route-arrow', arrowList);
  }

  Future<void> _updateMainRouteWithArrows(
    String sourceId,
    String lineLayerId,
    String symbolLayerId,
    List<LatLng> points,
    String hexColor,
  ) async {
    // 1. Format the coordinates as a GeoJSON LineString
    Map<String, dynamic> geoJson = {
      "type": "FeatureCollection",
      "features": points.isEmpty
          ? []
          : [
              {
                "type": "Feature",
                "geometry": {
                  "type": "LineString",
                  "coordinates": points
                      .map((p) => [p.longitude, p.latitude])
                      .toList(),
                },
              },
            ],
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
      await maplibreController?.addSource(
        sourceId,
        maplibre.GeojsonSourceProperties(data: geoJson),
      );

      // Layer 1: The Solid Route Line
      await maplibreController?.addLineLayer(
        sourceId,
        lineLayerId,
        maplibre.LineLayerProperties(lineColor: hexColor, lineWidth: 6.0),
      );

      // Layer 2: The Directional Arrows tied to the exact same Source
      await maplibreController?.addSymbolLayer(
        sourceId,
        symbolLayerId,
        maplibre.SymbolLayerProperties(
          symbolPlacement: 'line', // <-- The Mapbox/MapLibre magic property
          iconImage: 'route-arrow', // Matches the ID from _loadCustomPins
          iconSize: 0.3, // Scale your PNG down or up here
          iconKeepUpright:
              false, // Ensures the arrow points along the line, not strictly up
          symbolSpacing:
              100, // Adds padding between repeating arrows so it isn't cluttered
        ),
      );
    }
  }

  void _handleTabChanged(int targetIndex) {
    final suggestedRoutes = ref.read(routeStateProvider).suggestedRoutes;

    setState(() {
      _selectedIndex = targetIndex;
    });

    drawMapElements();

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
        curve: Curves.easeInOut,
      );
    }
  }

  // --- NEW LOGIC: Check if current pin is a Favorite ---
  FavoriteLocation? _getCurrentFavorite(LatLng? currentDestPin) {
    if (currentDestPin == null) return null;

    final favorites = _hiveService.getFavorites();

    for (var fav in favorites) {
      // Compare coordinates up to 4 decimal places to avoid micro-precision bugs
      if (fav.latitude.toStringAsFixed(4) ==
              currentDestPin.latitude.toStringAsFixed(4) &&
          fav.longitude.toStringAsFixed(4) ==
              currentDestPin.longitude.toStringAsFixed(4)) {
        return fav; // Found a match!
      }
    }
    return null; // No match found
  }

  // Temporarily placed here for the Find Button background math!
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
    return Polyline(points: points, strokeWidth: 4.0, color: routeColor);
  }

  @override
  Widget build(BuildContext context) {

    final mapState = ref.watch(mapStateProvider);
    final LatLng? startPin = mapState.startPin;
    final LatLng? destinationPin = mapState.destinationPin;

    final routeState = ref.watch(routeStateProvider);
    final List<JeepneyRoute> allRoutes = routeState.allRoutes;
    final List<RouteResult> suggestedRoutes = routeState.suggestedRoutes;
    final RouteResult? selectedRoute = routeState.selectedRoute;

    FavoriteLocation? currentFav = _getCurrentFavorite(destinationPin);
    bool isSaved = currentFav != null;
    String displayTitle = isSaved ? currentFav.name : (destinationPin != null ? '${destinationPin.latitude.toStringAsFixed(4)}, ${destinationPin.longitude.toStringAsFixed(4)}' : '');
    
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
            styleString:
                'https://api.maptiler.com/maps/019d2d1a-6040-7d1b-be05-18e6303d1ff8/style.json?key=${dotenv.env['MAPTILER_API_KEY']}',

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

            onStyleLoadedCallback: () {
              _loadCustomPins(); // Load our custom pin images into the GPU's memory
            },

            // Tap handling for dropping pins (using MapLibre's math)
            onMapClick: (Point<double> point, maplibre.LatLng coordinates) {
              // We convert MapLibre's LatLng back to our app's standard latlong2 format
              LatLng standardCoords = LatLng(
                coordinates.latitude,
                coordinates.longitude,
              );

              if (currentPinMode == PinMode.start) {
                // Tell Riverpod to save the pin
                ref.read(mapStateProvider.notifier).setStartPin(standardCoords);

                // You still need setState for local UI variables!
                setState(() {
                  currentPinMode = PinMode.none;
                  _clearRoutingData();
                });
              } else if (currentPinMode == PinMode.destination) {
                ref
                    .read(mapStateProvider.notifier)
                    .setDestinationPin(standardCoords);

                setState(() {
                  _currentDestinationName = '';
                  currentPinMode = PinMode.none;
                  _clearRoutingData();
                });
              }
              drawMapElements();
            },
            // This code limits the app to Davao City only
            // This prevents MapLibre to render parts of the map outside Davao City
            cameraTargetBounds: maplibre.CameraTargetBounds(
              maplibre.LatLngBounds(
                southwest: maplibre.LatLng(
                  6.9000,
                  125.4000,
                ), // Southwest corner of Davao City
                northeast: maplibre.LatLng(
                  7.2500,
                  125.9000,
                ), // Northeast corner of Davao City
              ),
            ),

            minMaxZoomPreference: const maplibre.MinMaxZoomPreference(
              11.0,
              22.0,
            ),
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
                    },
                  ),
                  const SizedBox(height: 8),
                  // --- Legend for Explore tab: Displays the selected routes to Explore its coverage ---
                  RoutesLegend(
                    visibleRoutes: allRoutes.where((r) => r.isVisible).toList(),
                    selectedIndex: _selectedIndex,
                  ),
                  // --- The Favorite Card: Displays the coordinates of the destination pin and allows user to save it to favorites ---
                  FavoriteCard(
                    isVisible:
                        (destinationPin != null &&
                        !_isSavePopupVisible &&
                        _selectedIndex != 0),
                    isSaved: isSaved,
                    displayTitle: displayTitle,
                    onClick: () async {
                      if (isSaved) {
                        await _hiveService.deleteLocation(currentFav.id);
                        setState(() {});
                        if (context.mounted) {
                          Fluttertoast.showToast(
                            msg: 'Removed from Favorites',
                            backgroundColor: cardColor,
                          );
                        }
                      } else {
                        setState(() {
                          // Pre-fill the text field. If empty, keep it empty so the hint text shows.
                          _saveNameController.text = _currentDestinationName;
                          _isSavePopupVisible =
                              true; // Trigger the drop-down animation!
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          
          FloatingRouteCard(
            route: selectedRoute,
            isVisible: (_showFloatingCard && _selectedIndex == 1),
            onClose: () async {
              setState(() {
                _showFloatingCard = false;
              });
              if (sheetController.isAttached) {
                sheetController.animateTo(
                  0.4,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }

              // 3. THE FIX: Wait for the card to finish sliding off-screen
              await Future.delayed(const Duration(milliseconds: 300));

              // 4. Safely clear the data and redraw the map
              // The 'mounted' check is a best practice to ensure the screen still exists
              if (mounted) {
                ref.read(routeStateProvider.notifier).setSelectedRoute(null);
                drawMapElements(); // Commands MapLibre to clear the jeepney line
              }
            },
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
                right:
                    16, // Stretching across the screen allows us to use MainAxisAlignment.spaceBetween
                child: AnimatedOpacity(
                  opacity: _selectedIndex == 0 ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: _selectedIndex == 0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment
                          .end, // Aligns bottoms of both sides
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
                              onTap: () {
                                if (startPin != null) {
                                  ref.read(mapStateProvider.notifier).setStartPin(null,); // Clear it in Riverpod
                                  setState(() {
                                    enableGPS = false;
                                    currentPinMode = PinMode.none;
                                    _clearRoutingData();
                                  });
                                } else if (currentPinMode == PinMode.start) {
                                  // Action 2: Cancel selection
                                  currentPinMode = PinMode.none;
                                } else {
                                  // Action 1: Enter selection mode
                                  setState(() {
                                    if (currentPinMode == PinMode.start) {
                                      currentPinMode = PinMode.none;
                                    } else {
                                      currentPinMode = PinMode.start;
                                      enableGPS = false;
                                    }
                                  });
                                }
                                drawMapElements();
                              },
                            ),
                            const SizedBox(width: 10),
                            CustomPinButton(
                              label: 'Target',
                              imagePath: 'assets/images/dest_pin.png',
                              mode: PinMode.destination,
                              currentMode: currentPinMode,
                              pinData: destinationPin,
                              onTap: () {
                                if (destinationPin != null) {
                                  ref.read(mapStateProvider.notifier).setDestinationPin(null,); // Clear it in Riverpod
                                  setState(() {
                                    enableGPS = false;
                                    currentPinMode = PinMode.none;
                                    _clearRoutingData();
                                  });
                                } else if (currentPinMode == PinMode.destination) {
                                  currentPinMode = PinMode.none;
                                } else {
                                  // THE FIX: Wrap the mode toggles in setState here too!
                                  setState(() {
                                    if (currentPinMode == PinMode.destination) {
                                      currentPinMode = PinMode.none;
                                    } else {
                                      currentPinMode = PinMode.destination;
                                    }
                                  });
                                }
                                drawMapElements();
                              },
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
                              backgroundColor: enableGPS
                                  ? btnColor
                                  : disableColor,
                              onPressed: () async {
                                final LatLng? userLatLng =
                                    await _locationService.getGPSLocation();

                                if (userLatLng != null) {
                                  ref
                                      .read(mapStateProvider.notifier)
                                      .setStartPin(
                                        userLatLng,
                                      ); // Save to Riverpod
                                  setState(() {
                                    enableGPS = true;
                                    _clearRoutingData();
                                  });

                                  maplibreController?.animateCamera(
                                    maplibre.CameraUpdate.newLatLngZoom(
                                      maplibre.LatLng(
                                        userLatLng.latitude,
                                        userLatLng.longitude,
                                      ),
                                      16.0,
                                    ),
                                  );

                                  drawMapElements();
                                }
                              },
                              // Make sure enableGPS and fontColor are defined in your state
                              child: Icon(
                                enableGPS ? Icons.gps_fixed : Icons.gps_off,
                                color: fontColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FloatingActionButton.extended(
                              heroTag: "btnFind",
                              backgroundColor: canFind
                                  ? btnColor
                                  : disableColor,
                              onPressed: () async {
                                // Check if pins are missing FIRST
                                if (startPin == null || destinationPin == null) {
                                  Fluttertoast.showToast(
                                    msg: 'Please select Start and Target on the map.',
                                    backgroundColor: cardColor,
                                  );
                                  return; // Stop the function here!
                                }

                                // If we made it here, both pins exist. Proceed with routing!
                                Map<String, List<LatLng>> routePayload = {};

                                for (var route in allRoutes) {
                                  route.polylineData ??= await parseRoute(
                                    route.filePath,
                                    route.color,
                                  );
                                  routePayload[route.name] = route.polylineData!.points;
                                }

                                List<RouteResult> bestRoutes = await compute(
                                  processRoutesInBackground,
                                  {
                                    'start': startPin,
                                    'dest': destinationPin,
                                    'routes': routePayload,
                                  },
                                );

                                // Tell Riverpod about the results!
                                ref.read(routeStateProvider.notifier).setSuggestedRoutes(bestRoutes);

                                setState(() {
                                  _selectedIndex = 1;
                                });

                                if (bestRoutes.isNotEmpty) {
                                  sheetController.animateTo(
                                    0.96,
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeInOut,
                                  );
                                } else {
                                  if (context.mounted) {
                                    Fluttertoast.showToast(
                                      msg: 'No routes found.',
                                      backgroundColor: cardColor,
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.navigation, color: fontColor),
                              label: const Text(
                                "Find",
                                style: TextStyle(
                                  color: fontColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
          
          // The Swipe-Up Bottom Sheet (Now modular!)
          MainBottomSheet(
            sheetController: sheetController,
            selectedIndex: _selectedIndex,
            hasSuggestedRoutes: suggestedRoutes.isNotEmpty,
            onDrawMapElements: drawMapElements,
            onLocationFound: _handleLocationFound,
            onShowFloatingCard: _handleShowFloatingCard,
          ),
          
          // --- NEW LAYER: The Animated Drop-Down Overlay ---
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut, // That premium bounce effect
            top: _isSavePopupVisible
                ? 120
                : -300, // Slides from off-screen to just below the header
            left: 16,
            right: 16,
            child: Card(
              color: btnColor,
              elevation: 15,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Save to Favorites?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: fontColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // The Name Input Field
                    TextField(
                      controller: _saveNameController,
                      style: const TextStyle(
                        color: sheetBackgroundColor,
                        fontSize: 14,
                      ),
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
                          ? '${destinationPin.latitude.toStringAsFixed(4)}, ${destinationPin.longitude.toStringAsFixed(4)}'
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
                            setState(
                              () => _isSavePopupVisible = false,
                            ); // Dismiss
                          },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            // 1. Fallback name if they left it blank
                            final finalName =
                                _saveNameController.text.trim().isEmpty
                                ? 'Saved Location'
                                : _saveNameController.text.trim();

                            // 2. Create the Hive Object
                            final newFav = FavoriteLocation(
                              id: DateTime.now().millisecondsSinceEpoch
                                  .toString(),
                              name: finalName,
                              latitude: destinationPin!.latitude,
                              longitude: destinationPin.longitude,
                              iconCodePoint: Icons
                                  .star
                                  .codePoint, // Default to a star icon
                              isFavorite: true,
                            );

                            // 3. Save to database
                            await _hiveService.saveLocation(newFav);

                            // 4. Close the popup and notify user
                            setState(() {
                              _isSavePopupVisible = false;
                            });

                            if (context.mounted) {
                              Fluttertoast.showToast(
                                msg: 'Added to Favorites!',
                                backgroundColor: cardColor,
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
                blurRadius: 20,
              ),
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
                onTap: () => _handleTabChanged(0),
              ),
              CustomNavigationBar(
                icon: Icons.location_on,
                label: "Locate",
                index: 1,
                selectedIndex: _selectedIndex,
                onTap: () => _handleTabChanged(1),
              ),
              CustomNavigationBar(
                icon: Icons.search,
                label: "Search",
                index: 2,
                selectedIndex: _selectedIndex,
                onTap: () => _handleTabChanged(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}