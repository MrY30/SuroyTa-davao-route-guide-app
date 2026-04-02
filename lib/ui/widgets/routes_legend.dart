import 'package:flutter/material.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';
import 'package:sakay_ta_mobile_app/models/jeepney_route.dart';

class RoutesLegend extends StatelessWidget{
  final List<JeepneyRoute> visibleRoutes;
  final int selectedIndex;

  const RoutesLegend({
    required this.visibleRoutes,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Filter out only the routes the user has actively checked
    // final visibleRoutes = allRoutes.where((r) => r.isVisible).toList();
    // 2. Determine if the legend should be shown
    final bool showLegend = selectedIndex == 0 && visibleRoutes.isNotEmpty;
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (Widget child, Animation<double> animation){
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: animation, 
                curve: Curves.easeOutBack, 
                reverseCurve: Curves.easeIn
              ),
              alignment: Alignment.centerLeft,
              child: child,
            )
          );
        },
        child: showLegend ? ConstrainedBox(
          key: const ValueKey('legend_card'),
          constraints: const BoxConstraints(maxWidth: 180),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: btnColor.withOpacity(0.8),
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, 
              children: [
                const Text(
                  'Legend',
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.bold, 
                    color: fontColor,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                // --- NEW: THE SCROLLABLE CAP ---
                ConstrainedBox(
                  // Set the maximum height. 200.0 is roughly 6-7 routes before scrolling starts.
                  constraints: const BoxConstraints(maxHeight: 75.0), 
                  child: SingleChildScrollView(
                    // This inner column holds the actual route items
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: visibleRoutes.map((route) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // The Route Color Indicator
                              Container(
                                width: 16,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: route.color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // The Route Name
                              Expanded(
                                child: Text(
                                  route.name,
                                  style: const TextStyle(
                                    fontSize: 10, 
                                    color: fontColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(), // .toList() is added back here for the inner Column
                    ),
                  ),
                ),
              ],
            ),
          )
        ) : const SizedBox.shrink(key: ValueKey('empty_legend'))
      )
    );
  }
}