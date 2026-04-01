import 'package:latlong2/latlong.dart';
import '../core/constants.dart';

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

  // --- THE NEW MATH PROPERTY ---
  // Safely calculates the discounted fare using the 4km base threshold
  double get estimatedDiscountedFare {
    if (ridingDistanceKm <= 4.0) {
      return discountedBaseFare; // Base fare for first 4km
    } else {
      // Base fare + (excess kilometers * 1.44)
      return discountedBaseFare + ((ridingDistanceKm - 4.0) * discountedPerKm);
    }
  }
}