import 'package:flutter/material.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';
import 'package:sakay_ta_mobile_app/services/hive_service.dart';
import 'package:google_fonts/google_fonts.dart';

// --- NEW STATE: Database Service ---
final HiveService _hiveService = HiveService();

void showAppInfoSheet(BuildContext context) {
    // Temporary local state for the switch (until we wire up Hive)
    bool showOnStartup = _hiveService.getShowInfoOnStartup();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows the sheet to size itself perfectly to the content
      backgroundColor: sheetBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        // StatefulBuilder is REQUIRED here so the Switch can update its own UI
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.96,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Hugs the content tightly
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. THE DRAG HANDLE & HEADER
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Text(
                        'About SuroyTa!',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor, fontFamily: GoogleFonts.paytoneOne().fontFamily),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'version $version',
                        style: const TextStyle(color: Colors.white54, fontSize: 13, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 5),

                      // 2. THE FARE MATRIX CARD
                      Card(
                        color: btnColor,
                        elevation: 5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16.0, bottom: 32.0),
                          child: Column(
                            children: [
                              Text(
                                'Fare Matrix',
                                style: TextStyle(color: fontColor, fontSize: 25, fontFamily: GoogleFonts.paytoneOne().fontFamily),
                              ),
                              Text(
                                'As Of $fareEffectiveDate',
                                style: const TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Regular Fares
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Regular', style: TextStyle(color: primaryColor, fontSize: 20, fontFamily: GoogleFonts.paytoneOne().fontFamily)),
                                      const SizedBox(height: 4),
                                      Text('Base:', style: const TextStyle(color: fontColor, fontSize: 15)),
                                      Text('₱${regularBaseFare.toStringAsFixed(2)}', style: const TextStyle(color: fontColor, fontSize: 25, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text('Per Km:', style: const TextStyle(color: fontColor, fontSize: 15)),
                                      Text('₱${regularPerKm.toStringAsFixed(2)}', style: const TextStyle(color: fontColor, fontSize: 25, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  Container(width: 1, height: 150, color: Colors.white24), // Subtle Divider
                                  // Discounted Fares
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Discounted', style: TextStyle(color: primaryColor, fontSize: 20, fontFamily: GoogleFonts.paytoneOne().fontFamily)),
                                      const SizedBox(height: 4),
                                      Text('Base:', style: const TextStyle(color: fontColor, fontSize: 15)),
                                      Text('₱${discountedBaseFare.toStringAsFixed(2)}', style: const TextStyle(color: fontColor, fontSize: 25, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text('Per Km:', style: const TextStyle(color: fontColor, fontSize: 15)),
                                      Text('₱${discountedPerKm.toStringAsFixed(2)}', style: const TextStyle(color: fontColor, fontSize: 25, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. EXPANDABLE: OBJECTIVES
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent), // Removes default ugly borders
                        child: ExpansionTile(
                          iconColor: primaryColor,
                          collapsedIconColor: fontColor,
                          title: const Text('Project Objectives', style: TextStyle(color: fontColor, fontWeight: FontWeight.bold)),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              child: Text(
                                'The Suroy Ta! is a mobile-based geographic information system (GIS) and routing application engineered to optimize PUJ transit within Davao City. This system provides an interactive map interface allowing users to explore jeepney routes, identify optimal transit paths from a given origin to a destination, and estimate travel costs.',
                                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 4. EXPANDABLE: HOW TO USE
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          iconColor: primaryColor,
                          collapsedIconColor: fontColor,
                          title: const Text('How to Use Suroy Ta', style: TextStyle(color: fontColor, fontWeight: FontWeight.bold)),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // --- LOCATE TAB INSTRUCTIONS ---
                                  Text('📍 Finding a Route (Locate Tab)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 6),
                                  Text('1. Tap the GPS button for your current location, or tap the map to drop a Start pin.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 4),
                                  Text('2. Drop a Target pin for your destination. (Tip: Tap the coordinates to save it to Favorites!)', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 4),
                                  Text('3. Tap "Find" to calculate the best jeepney routes.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 4),
                                  Text('4. Select a route card to view your walking path, transit line, and estimated fare.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 16),

                                  // --- EXPLORE TAB INSTRUCTIONS ---
                                  Text('🗺️ Browsing Routes (Explore Tab)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 6),
                                  Text('• Scroll through or use the search bar to filter the catalog of PUJ routes.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 4),
                                  Text('• Tap any route card to draw its specific path on the map.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 4),
                                  Text('• Select multiple routes at once to compare them, then tap "Clear" to reset the map.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 16),

                                  // --- SEARCH TAB INSTRUCTIONS ---
                                  Text('🔍 Quick Search (Search Tab)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 6),
                                  Text('• Type a landmark name or exact coordinates to instantly pan the map.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 4),
                                  Text('• Quickly jump to your Recent Searches or your saved Favorite locations.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 5. THE STARTUP SWITCH
                      SwitchListTile(
                        activeThumbColor: primaryColor,
                        inactiveThumbColor: fontColor,
                        inactiveTrackColor: sheetBackgroundColor,
                        title: const Text('Show this on startup', style: TextStyle(color: fontColor, fontSize: 15)),
                        value: showOnStartup,
                        onChanged: (bool value) async {
                          setModalState(() {
                            showOnStartup = value; // Animates the switch toggle!
                          });
                          await _hiveService.toggleShowInfoOnStartup(value);
                        },
                      ),
                      
                      // SafeArea padding so it doesn't collide with the phone's home swipe bar
                      const SizedBox(height: 20),
                    ],
                  ),
                )
              ),
            );
          }
        );
      },
    );
  }