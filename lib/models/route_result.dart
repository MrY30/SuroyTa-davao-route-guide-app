import 'package:latlong2/latlong.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';

class RouteResult {
  final String routeName;
  final double estimatedStartWalk;
  final double estimatedEndWalk;
  final int boardIndex; 
  final int alightIndex; 
  
  // --- THE NEW MATH PROPERTIES ---
  final double ridingDistanceKm; 
  final double estimatedFare;

  // --- OSRM PROPERTIES ---
  double? actualStartWalk;
  double? actualEndWalk;
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

  double get totalEstimatedWalk => estimatedStartWalk + estimatedEndWalk;

  // Safely calculates the discounted fare using the 4km base threshold
  double get estimatedDiscountedFare {
    if (ridingDistanceKm <= 4.0) {
      return discountedBaseFare; // Base fare for first 4km
    } else {
      // Base fare + (excess kilometers * rate per km)
      return discountedBaseFare + ((ridingDistanceKm - 4.0) * discountedPerKm);
    }
  }
}