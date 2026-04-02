import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position?> getLocation() async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        // Try to open location settings
        await Geolocator.openLocationSettings();
        return null;
      }

      // Check and request permissions
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions denied: $permission');
        return null;
      }

      // Try to get the last known position first (faster)
      Position? lastPosition = await Geolocator.getLastKnownPosition();
      
      // Get current position with high accuracy
      // Use a longer timeout for better accuracy
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      ).catchError((e) {
        debugPrint('Error getting current position: $e');
        return lastPosition ?? Future.error(e);
      });

      debugPrint('Location obtained: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      debugPrint('Location service error: $e');
      return null;
    }
  }
}
