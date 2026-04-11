import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sakay_ta_mobile_app/models/jeepney_route.dart';
import 'package:sakay_ta_mobile_app/models/route_result.dart';

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

class RouteStateNotifier extends Notifier<RouteState> {
  @override
  RouteState build() {
    return RouteState(allRoutes: [], suggestedRoutes: [], selectedRoute: null);
  }

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

  Future<void> handleRouteToggle(JeepneyRoute route) async {
    bool newState = !route.isVisible;

    if (newState == true && route.polylineData == null) {
      route.polylineData = await _parseRoute(route.filePath, route.color);
    }

    route.isVisible = newState;

    state = RouteState(
      allRoutes: List.from(state.allRoutes),
      suggestedRoutes: state.suggestedRoutes,
      selectedRoute: null,
    );
  }

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

  void setSuggestedRoutes(List<RouteResult> routes) {
    for (var r in state.allRoutes) {
      r.isVisible = false;
    }
    state = RouteState(
      allRoutes: List.from(state.allRoutes),
      suggestedRoutes: routes,
      selectedRoute: null,
    );
  }

  void setSelectedRoute(RouteResult? route) {
    state = RouteState(
      allRoutes: state.allRoutes,
      suggestedRoutes: state.suggestedRoutes,
      selectedRoute: route,
    );
  }

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

final routeStateProvider = NotifierProvider<RouteStateNotifier, RouteState>(() {
  return RouteStateNotifier();
});