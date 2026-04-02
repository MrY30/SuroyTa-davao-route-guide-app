import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';

class LocationService {
  // --- NEW LOGIC: Hardware GPS ---
  Future<LatLng?> getGPSLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Check if GPS hardware is turned on
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // _showCustomToast("Please enable GPS.", icon: Icons.notifications);
      Fluttertoast.showToast(msg: 'Please enable GPS.', backgroundColor: cardColor);
      return null;
    }

    // 2. Check and request permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // _showCustomToast("Location permissions denied.", icon: Icons.notifications);
        Fluttertoast.showToast(msg: 'Location permissions denied.', backgroundColor: cardColor);
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // _showCustomToast("Permissions permanently denied.", icon: Icons.notifications);
      Fluttertoast.showToast(msg: 'Permissions permanently denied.', backgroundColor: cardColor);
      return null;
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    return LatLng(position.latitude, position.longitude);
  }
}

