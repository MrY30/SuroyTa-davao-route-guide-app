import 'package:latlong2/latlong.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';
import 'package:sakay_ta_mobile_app/models/route_result.dart';


// 2. The Isolate Function
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

    List<double> cumulativeDistances = [0.0];
    double totalRouteDistance = 0.0;
    for (int i = 0; i < coordinates.length - 1; i++) {
      totalRouteDistance += haversine.as(LengthUnit.Meter, coordinates[i], coordinates[i+1]);
      cumulativeDistances.add(totalRouteDistance);
    }

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

    int bestStartIdx = -1;
    int bestDestIdx = -1;
    double lowestPenaltyScore = double.infinity;
    
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
        } else {
          rideDist = (totalRouteDistance - cumulativeDistances[sIdx]) + cumulativeDistances[dIdx];
        }

        if (rideDist < minRideDistance) continue; 

        // Calculate Walk Distances
        double sWalk = haversine.as(LengthUnit.Meter, start, coordinates[sIdx]);
        double dWalk = haversine.as(LengthUnit.Meter, dest, coordinates[dIdx]);
        double totalWalk = sWalk + dWalk;

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
      double fare = regularBaseFare; 
      if (ridingDistanceKm > 4.0) {
        fare += (ridingDistanceKm - 4.0) * regularPerKm; 
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
        ),
      );
    }
  });

  validRoutes.sort((a, b) => (a.estimatedStartWalk + a.estimatedEndWalk).compareTo(b.estimatedStartWalk + b.estimatedEndWalk));
  
  return validRoutes;
}