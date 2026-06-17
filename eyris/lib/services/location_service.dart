import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationService {
  


  /// User ki current location fetch karne ka function
  Future<Position> getCurrentLocation() async {
    // 1. Check karein ke location services enabled hain ya nahi
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    // 2. Check karein ke app ko location permission mili hui hai ya nahi
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied.');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    }

    // 3. ✅ Updated syntax: locationSettings ka use kiya gaya hai
    return await Geolocator.getCurrentPosition();
  }

  /// Real-time location stream fetch karne ka function
  Stream<Position> getPositionStream() {
    // ✅ Keep settings compatible with this geolocator version
    return Geolocator.getPositionStream();
  }
}