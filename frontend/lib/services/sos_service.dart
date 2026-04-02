import 'package:flutter/foundation.dart';
import 'package:safeher/models/emergency_contact.dart';
import 'package:safeher/models/sos_log.dart';
import 'package:safeher/services/location_service.dart';
import 'package:safeher/services/messaging_service.dart';
import 'package:safeher/services/storage_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

class SOSService {
  SOSService({
    LocationService? locationService,
    MessagingService? messagingService,
    StorageService? storageService,
  })  : _locationService = locationService ?? LocationService(),
        _messagingService = messagingService ?? MessagingService(),
        _storageService = storageService ?? StorageService.instance;

  final LocationService _locationService;
  final MessagingService _messagingService;
  final StorageService _storageService;

  /// Triggers SOS alert INSTANTLY without waiting for location
  /// Location is fetched in parallel and sent as a follow-up message
  Future<SOSLog> triggerSOS() async {
    debugPrint('🚨 SOS TRIGGERED INSTANTLY!');
    
    final now = DateTime.now();
    final timeString = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final sosId = const Uuid().v4();
    
    // Get contacts immediately
    final List<EmergencyContact> contacts = await _storageService.getContacts();
    final List<String> notified = [];
    
    // STEP 1: Send INSTANT alert (no location yet)
    debugPrint('📱 Sending INSTANT alerts to ${contacts.length} contacts...');
    
    const instantWhatsapp = '🚨 *EMERGENCY SOS ALERT*\n\n'
        'I need help immediately!\n'
        'This is an *automated emergency alert*.\n\n'
        '📍 Location coming shortly...\n'
        '— Sent from SafeHer app';

    const instantSms = 'EMERGENCY SOS! I need help immediately! '
        'Location will follow shortly. - SafeHer';

    // Send instant messages to ALL contacts first (parallel)
    await Future.wait(
      contacts.map((contact) async {
        try {
          if (contact.sendSMS) {
            await _messagingService.sendSMS(contact.phone, instantSms);
            debugPrint('✅ INSTANT SMS sent to ${contact.name}');
          }
          notified.add(contact.name);
        } catch (e) {
          debugPrint('❌ Error sending instant alert to ${contact.name}: $e');
        }
      }),
    );
    
    debugPrint('✅ INSTANT alerts sent in < 1 second!');

    // STEP 2: Get location in background (don't block)
    Position? position;
    _getLocationAndSendUpdate(contacts, timeString);
    
    // Try to get cached location for log (instant)
    try {
      position = await Geolocator.getLastKnownPosition();
      debugPrint('📍 Using cached location: ${position?.latitude}, ${position?.longitude}');
    } catch (e) {
      debugPrint('⚠️ No cached location available');
    }

    // STEP 3: Create log immediately
    final log = SOSLog(
      id: sosId,
      timestamp: now,
      lat: position?.latitude,
      lng: position?.longitude,
      contactsNotified: notified,
    );
    await _storageService.saveSOSLog(log);
    
    debugPrint('✅ SOS Log created - Screen should show NOW!');

    return log;
  }

  /// Fetches accurate location and sends follow-up message with Google Maps link
  Future<void> _getLocationAndSendUpdate(List<EmergencyContact> contacts, String timeString) async {
    debugPrint('🗺️ Fetching accurate location in background...');
    
    Position? position;
    try {
      position = await _locationService.getLocation().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          debugPrint('⚠️ Location timeout - using cached');
          return null;
        },
      );
    } catch (e) {
      debugPrint('❌ Location error: $e');
    }
    
    if (position == null) {
      // Try cached as fallback
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (e) {
        debugPrint('❌ No cached location either');
      }
    }
    
    if (position == null) {
      debugPrint('❌ Could not get any location');
      return;
    }
    
    final mapsLink = 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
    debugPrint('📍 Location obtained: $mapsLink');
    
    // Send follow-up message with location
    final locationWhatsapp = '📍 *SOS LOCATION UPDATE*\n\n'
        'My location: $mapsLink\n'
        '🕐 Time: $timeString\n\n'
        '— SafeHer app';

    final locationSms = 'SOS LOCATION: $mapsLink - Time: $timeString - SafeHer';
    
    for (final contact in contacts) {
      try {
        if (contact.sendSMS) {
          await _messagingService.sendSMS(contact.phone, locationSms);
          debugPrint('✅ Location SMS sent to ${contact.name}');
        }
        if (contact.sendWhatsApp) {
          await _messagingService.sendWhatsApp(contact.phone, locationWhatsapp);
          debugPrint('✅ Location WhatsApp sent to ${contact.name}');
        }
      } catch (e) {
        debugPrint('❌ Error sending location to ${contact.name}: $e');
      }
    }
    
    debugPrint('✅ Location follow-up messages sent!');
  }

  Future<void> cancelSOS(SOSLog log) async {
    final contacts = await _storageService.getContacts();
    const cancelMessage =
        '✅ FALSE ALARM — I am safe. Please ignore the previous SOS alert.';

    for (final contact in contacts) {
      if (contact.sendWhatsApp) {
        await _messagingService.sendWhatsApp(contact.phone, cancelMessage);
      }
      if (contact.sendSMS) {
        await _messagingService.sendSMS(contact.phone, cancelMessage);
      }
    }

    log.wasCancelled = true;
    await _storageService.saveSOSLog(log);
  }
}
