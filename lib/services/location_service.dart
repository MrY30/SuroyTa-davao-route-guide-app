import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';

class LocationService {
  Future<LatLng?> getGPSLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if GPS hardware is turned on
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Fluttertoast.showToast(msg: 'Please enable GPS.', backgroundColor: cardColor);
      return null;
    }

    // Request permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        Fluttertoast.showToast(msg: 'Location permissions denied.', backgroundColor: cardColor);
        return null;
      }
    }
    
    // Permanently Deny upon Request
    if (permission == LocationPermission.deniedForever) {
      Fluttertoast.showToast(msg: 'Permissions permanently denied.', backgroundColor: cardColor);
      return null;
    }

    // GPS Location is accessed
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    return LatLng(position.latitude, position.longitude);
  }
}

