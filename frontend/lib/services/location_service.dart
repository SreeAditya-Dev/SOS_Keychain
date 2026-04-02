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
        
        // Try to get last known position as fallback
        try {
          final lastPosition = await Geolocator.getLastKnownPosition();
          if (lastPosition != null) {
            debugPrint('Using last known position: ${lastPosition.latitude}, ${lastPosition.longitude}');
            return lastPosition;
          }
        } catch (e) {
          debugPrint('Error getting last known position: $e');
        }
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
        
        // Try to get last known position even if permission is denied
        try {
          final lastPosition = await Geolocator.getLastKnownPosition();
          if (lastPosition != null) {
            debugPrint('Using last known position (permission denied): ${lastPosition.latitude}, ${lastPosition.longitude}');
            return lastPosition;
          }
        } catch (e) {
          debugPrint('Error getting last known position: $e');
        }
        return null;
      }

      // Get last known position first (faster fallback)
      Position? lastPosition;
      try {
        lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          debugPrint('Last known position available: ${lastPosition.latitude}, ${lastPosition.longitude}');
        }
      } catch (e) {
        debugPrint('Error getting last known position: $e');
      }
      
      // Try to get current position with high accuracy
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
        
        debugPrint('Current location obtained: ${position.latitude}, ${position.longitude}');
        return position;
      } catch (e) {
        debugPrint('Error getting current position: $e');
        
        // Fall back to last known position if available
        if (lastPosition != null) {
          debugPrint('Falling back to last known position: ${lastPosition.latitude}, ${lastPosition.longitude}');
          return lastPosition;
        }
        
        // Last resort: try one more time with lower accuracy
        try {
          debugPrint('Attempting to get location with lower accuracy...');
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
          debugPrint('Location obtained with medium accuracy: ${position.latitude}, ${position.longitude}');
          return position;
        } catch (e2) {
          debugPrint('Failed to get location with medium accuracy: $e2');
          return null;
        }
      }
    } catch (e) {
      debugPrint('Location service error: $e');
      
      // Final fallback attempt
      try {
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          debugPrint('Using last known position (final fallback): ${lastPosition.latitude}, ${lastPosition.longitude}');
          return lastPosition;
        }
      } catch (e2) {
        debugPrint('Final fallback failed: $e2');
      }
      
      return null;
    }
  }
}
