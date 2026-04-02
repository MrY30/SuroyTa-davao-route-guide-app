import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';

class GeocodeResult {
  final LatLng coordinates;
  final String name;

  GeocodeResult({required this.coordinates, required this.name});
}

class GeocodingService {
  Future<GeocodeResult?> searchLocation(String query) async {
    if (query.isEmpty) return null;

    final RegExp coordRegExp = RegExp(r'^([-+]?\d{1,2}(?:\.\d+)?),\s*([-+]?\d{1,3}(?:\.\d+)?)$');
    final match = coordRegExp.firstMatch(query);

    if (match != null) {
      final lat = double.parse(match.group(1)!);
      final lon = double.parse(match.group(2)!);
      LatLng searchResult = LatLng(lat, lon);

      Fluttertoast.showToast(msg: 'Coordinate dropped!', backgroundColor: cardColor);
      return GeocodeResult(coordinates: searchResult, name: "Recent Searched");
    }

    Fluttertoast.showToast(msg: 'Searching for "$query" ...', backgroundColor: cardColor);

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
          final displayName = data[0]['name'] ?? query;
          LatLng searchResult = LatLng(lat, lon);

          return GeocodeResult(coordinates: searchResult, name: displayName);
        } else {
          Fluttertoast.showToast(msg: 'Location not found in Davao City.', backgroundColor: cardColor);
          return null;
        }
      }
    } catch (e) {
      debugPrint("Geocoding Error: $e");
      return null;
    }
    return null;
  }
}
