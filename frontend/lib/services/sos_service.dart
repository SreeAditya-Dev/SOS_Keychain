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

  Future<SOSLog> triggerSOS() async {
    debugPrint('🚨 SOS Triggered - Starting location fetch...');
    
    // Get location with longer timeout for better accuracy
    Position? position;
    try {
      position = await _locationService.getLocation().timeout(
        const Duration(seconds: 25), // Increased timeout
        onTimeout: () {
          debugPrint('⚠️ Location timeout after 25 seconds - proceeding without location');
          return null;
        },
      );
      
      if (position != null) {
        debugPrint('✅ Location obtained: ${position.latitude}, ${position.longitude}');
        debugPrint('📍 Accuracy: ${position.accuracy}m');
      } else {
        debugPrint('❌ No location available');
      }
    } catch (e) {
      debugPrint('❌ Error getting location: $e');
      position = null;
    }

    // Create Google Maps link with proper formatting
    final mapsLink = position != null
        ? 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}'
        : 'Location unavailable';

    debugPrint('🗺️ Maps link: $mapsLink');

    final now = DateTime.now();
    final timeString = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    final whatsappMessage = '🚨 *SOS ALERT*\n\n'
        'This is an *automated emergency alert*.\n\n'
        '📍 Location: $mapsLink\n'
        '🕐 Time: $timeString\n\n'
        '— Sent from SafeHer app';

    final smsMessage = 'SOS ALERT! Need help immediately. '
      'Location: $mapsLink '
      'Time: $timeString - SafeHer';

    debugPrint('📱 Sending alerts to contacts...');
    final List<EmergencyContact> contacts = await _storageService.getContacts();
    final List<String> notified = [];

    for (final contact in contacts) {
      debugPrint('Sending to ${contact.name} (${contact.phone})...');
      try {
        if (contact.sendSMS) {
          await _messagingService.sendSMS(contact.phone, smsMessage);
          debugPrint('✅ SMS sent to ${contact.name}');
        }
        if (contact.sendWhatsApp) {
          await _messagingService.sendWhatsApp(contact.phone, whatsappMessage);
          debugPrint('✅ WhatsApp sent to ${contact.name}');
        }
        notified.add(contact.name);
      } catch (e) {
        debugPrint('❌ Error sending to ${contact.name}: $e');
      }
    }

    debugPrint('✅ SOS alerts sent to ${notified.length} contacts');

    final log = SOSLog(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      lat: position?.latitude,
      lng: position?.longitude,
      contactsNotified: notified,
    );
    await _storageService.saveSOSLog(log);

    return log;
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
