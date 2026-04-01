// lib/services/osrm_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class OsrmService {
  Future<Map<String, dynamic>?> fetchWalkingRoute(LatLng start, LatLng end) async {
    // 1. Establish our baseline straight-line distance
    final Distance haversine = const Distance(); // Or Distance() depending on your package version
    final double straightLineDist = haversine.as(LengthUnit.Meter, start, end);

    // 2. Add 'overview=full' to force smooth, highly-accurate road curves
    final url = 'https://router.project-osrm.org/route/v1/foot/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson&overview=full';
    
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        final osrmDistance = data['routes'][0]['distance'] as num;
        
        // 3. THE SANITY CHECK: Protect against the "Missing Gate" trap
        // If OSRM forces a massive detour (more than 3x the straight line), ignore it.
        if (osrmDistance > (straightLineDist * 3) && straightLineDist < 500) {
          debugPrint("OSRM returned a massive detour. Falling back to straight line.");
          return {
            'path': [start, end],
            'distance': straightLineDist,
          };
        }

        // Convert GeoJSON [lon, lat] back to FlutterMap LatLng
        List<LatLng> path = coords.map((c) => LatLng(c[1], c[0])).toList();
        
        return {
          'path': path,
          'distance': osrmDistance.toDouble(),
        };
      }
    } catch (e) {
      debugPrint("OSRM Request Failed or Timed Out: $e");
    }
    
    // 4. THE FAILSAFE: If the API fails completely, don't break the UI!
    // Just return a straight line so the user still sees a path.
    return {
      'path': [start, end],
      'distance': straightLineDist,
    };
  }
}