import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sakay_ta_mobile_app/models/jeepney_route.dart';
import 'package:sakay_ta_mobile_app/models/route_result.dart';

// 1. The State Object (Holds the data)
class RouteState {
  final List<JeepneyRoute> allRoutes;
  final List<RouteResult> suggestedRoutes;
  final RouteResult? selectedRoute;

  RouteState({
    required this.allRoutes,
    required this.suggestedRoutes,
    this.selectedRoute,
  });
}

// 2. The Notifier (The Controller that manages the data)
class RouteStateNotifier extends Notifier<RouteState> {
  @override
  RouteState build() {
    // Start with empty lists when the app opens
    return RouteState(allRoutes: [], suggestedRoutes: [], selectedRoute: null);
  }

  // --- Action 1: Load Catalog ---
  Future<void> initializeRouteList() async {
    try {
      final String response = await rootBundle.loadString('assets/routes_catalog.json');
      final List<dynamic> catalogData = json.decode(response);

      List<JeepneyRoute> tempRoutes = [];
      for (var item in catalogData) {
        String hexString = item['color'].toString().replaceAll('#', '');
        Color parsedColor = Color(int.parse('0xFF$hexString'));

        tempRoutes.add(JeepneyRoute(
          name: item['name'],
          filePath: item['file'],
          color: parsedColor,
        ));
      }
      state = RouteState(allRoutes: tempRoutes, suggestedRoutes: state.suggestedRoutes, selectedRoute: state.selectedRoute);
    } catch (e) {
      debugPrint("Error loading catalog: $e");
    }
  }

  // --- Helper: Parse GeoJSON Coordinates ---
  Future<Polyline> _parseRoute(String filePath, Color routeColor) async {
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

  // --- Action 2: Toggle a Single Route ---
  Future<void> handleRouteToggle(JeepneyRoute route) async {
    bool newState = !route.isVisible;

    // Load coordinates from the file ONLY if they haven't been loaded yet
    if (newState == true && route.polylineData == null) {
      route.polylineData = await _parseRoute(route.filePath, route.color);
    }

    route.isVisible = newState;

    // Force UI rebuild by creating a new copy of the list
    state = RouteState(
      allRoutes: List.from(state.allRoutes),
      suggestedRoutes: state.suggestedRoutes,
      selectedRoute: null,
    );
  }

  // --- Action 3: Toggle All Routes ---
  Future<void> toggleAllRoutes(bool showAll) async {
    for (var route in state.allRoutes) {
      if (showAll && route.polylineData == null) {
        route.polylineData = await _parseRoute(route.filePath, route.color);
      }
      route.isVisible = showAll;
    }
    state = RouteState(
      allRoutes: List.from(state.allRoutes),
      suggestedRoutes: state.suggestedRoutes,
      selectedRoute: null,
    );
  }

  // --- Action 4: Set Suggested Routes (From Find Button) ---
  void setSuggestedRoutes(List<RouteResult> routes) {
    for (var r in state.allRoutes) {
      r.isVisible = false; // Hide explore routes when doing A-to-B routing
    }
    state = RouteState(
      allRoutes: List.from(state.allRoutes),
      suggestedRoutes: routes,
      selectedRoute: null,
    );
  }

  // --- Action 5: Select a Route to view details ---
  void setSelectedRoute(RouteResult? route) {
    state = RouteState(
      allRoutes: state.allRoutes,
      suggestedRoutes: state.suggestedRoutes,
      selectedRoute: route,
    );
  }

  // --- Action 6: Clear everything ---
  void clearRoutingData() {
    for (var route in state.allRoutes) {
      route.isVisible = false;
    }
    state = RouteState(
      allRoutes: List.from(state.allRoutes),
      suggestedRoutes: [],
      selectedRoute: null,
    );
  }
}

// 3. The Provider Object (The Pipe)
final routeStateProvider = NotifierProvider<RouteStateNotifier, RouteState>(() {
  return RouteStateNotifier();
});