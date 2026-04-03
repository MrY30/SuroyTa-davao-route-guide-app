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
                                'Suroy Ta is designed to help Davaoeños navigate the city effortlessly. Our goal is to provide accurate PUJ routing, real-time fare estimation, and promote an efficient public transportation experience.',
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
                                  Text('1. Place your Start and Target pins on the map or use the Search tab.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 8),
                                  Text('2. Tap "Find" to generate the best jeepney routes.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                                  SizedBox(height: 8),
                                  Text('3. Select a route to view your exact walking distance and estimated fare.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
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