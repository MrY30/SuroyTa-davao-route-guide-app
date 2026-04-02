import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakay_ta_mobile_app/models/favorite_location.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';
import 'package:sakay_ta_mobile_app/ui/map/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Hive.initFlutter();
  Hive.registerAdapter(FavoriteLocationAdapter());
  await Hive.openBox<FavoriteLocation>('locations_box');
  await Hive.openBox('settings_box');

  runApp(const ProviderScope(child: SuroyTaApp()));
}

class SuroyTaApp extends StatelessWidget {
  const SuroyTaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Suroy Ta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: btnColor),
        useMaterial3: true,
        fontFamily: GoogleFonts.outfit().fontFamily,
      ),
      home: const MapScreen(),
    );
  }
}

