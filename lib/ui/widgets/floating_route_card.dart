import 'package:flutter/material.dart';
import 'package:sakay_ta_mobile_app/models/route_result.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';

class FloatingRouteCard extends StatelessWidget {
  final RouteResult? route;
  final VoidCallback onClose;
  final bool isVisible;

  const FloatingRouteCard({
    super.key, 
    required this.route, 
    required this.onClose,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    if (route == null) return const SizedBox.shrink();
    final totalStartWalk = route!.actualStartWalk ?? route!.estimatedStartWalk;
    final totalEndWalk = route!.actualEndWalk ?? route!.estimatedEndWalk;
    final totalWalk = totalStartWalk + totalEndWalk;
    
    final isExactWalk = route!.actualStartWalk != null && route!.actualEndWalk != null;
    final walkPrefix = isExactWalk ? '' : '~';
    final walkText = '$walkPrefix${totalWalk.toStringAsFixed(0)}m';

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          Icon(Icons.directions_bus, color: fontColor, size: 18),
                          const SizedBox(width: 6),
                          Text(rideDistanceText, style: TextStyle(color: fontColor, fontSize: 15)),
                        ],
                      ),
                    ],
                  ),
                  
                  Row(
                    children: [
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