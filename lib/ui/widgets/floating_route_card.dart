import 'package:flutter/material.dart';
// Don't forget to import your RouteResult model and constants here!
import '../../models/route_result.dart';
import '../../core/constants.dart';

class FloatingRouteCard extends StatelessWidget {
  // 1. Declare what this widget NEEDS to function.
  final RouteResult? route; // The data to display
  final VoidCallback onClose; // The remote control to close the card
  final bool isVisible;

  // 2. The Constructor: This forces the parent to provide the required data.
  const FloatingRouteCard({
    super.key, 
    required this.route, 
    required this.onClose,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    // If there is no route, don't draw anything
    if (route == null) return const SizedBox.shrink();

    // Paste your existing AnimatedPositioned and Container UI code here.
    
    // IMPORTANT: Inside your UI, where you have the GestureDetector for the close button:
    // Replace your `setState` logic with just calling the remote control:
    // onTap: onClose, 
    // 1. Calculate combined walking distance
    final totalStartWalk = route!.actualStartWalk ?? route!.estimatedStartWalk;
    final totalEndWalk = route!.actualEndWalk ?? route!.estimatedEndWalk;
    final totalWalk = totalStartWalk + totalEndWalk;
    
    // Only show '~' if we are still relying on estimates
    final isExactWalk = route!.actualStartWalk != null && route!.actualEndWalk != null;
    final walkPrefix = isExactWalk ? '' : '~';
    final walkText = '$walkPrefix${totalWalk.toStringAsFixed(0)}m';

    // 2. Format texts
    final rideDistanceText = '${route!.ridingDistanceKm.toStringAsFixed(1)}km';
    final regularFareText = '₱ ${route!.estimatedFare.toStringAsFixed(2)}';
    final discountedFareText = '₱ ${route!.estimatedDiscountedFare.toStringAsFixed(2)}';

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      top: isVisible ? 40.0 : -200.0, 
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 15),
        // Removed the global padding here to allow for the two-tone split!
        decoration: BoxDecoration(
          color: btnColor, 
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              offset: const Offset(0, 10),
              blurRadius: 20
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          crossAxisAlignment: CrossAxisAlignment.stretch, // Stretches children horizontally
          children: [
            // ==========================================
            // TOP ROW: Route Name & Close Button
            // ==========================================
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        route!.routeName,
                        style: TextStyle(
                          fontSize: 45, 
                          fontFamily: 'Cubao',
                          color: primaryColor,
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
                  const SizedBox(width: 30),
                  GestureDetector(
                    onTap: onClose,
                    child: Icon(Icons.close, color: fontColor),
                  )
                ],
              ),
            ),
            
            // ==========================================
            // BOTTOM ROW: Distances and Fares (Dual-Tone effect)
            // ==========================================
            Container(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // --- LEFT: Distances ---
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.directions_walk, color: fontColor, size: 18),
                          const SizedBox(width: 6),
                          Text(walkText, style: TextStyle(color: fontColor, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.directions_bus, color: fontColor, size: 18), // Change to Icons.airport_shuttle if you prefer!
                          const SizedBox(width: 6),
                          Text(rideDistanceText, style: TextStyle(color: fontColor, fontSize: 15)),
                        ],
                      ),
                    ],
                  ),
                  
                  // --- RIGHT: Fares ---
                  Row(
                    children: [
                      // Discounted Fare Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Discounted', style: TextStyle(color: fontColor.withOpacity(0.8), fontSize: 12)),
                          Text(
                            discountedFareText,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: fontColor),
                          ),
                        ],
                      ),
                      const SizedBox(width: 25),
                      // Regular Fare Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Regular', style: TextStyle(color: fontColor.withOpacity(0.8), fontSize: 12)),
                          Text(
                            regularFareText,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: fontColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

  }
}