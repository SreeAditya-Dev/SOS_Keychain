import 'package:dt/models/emergency_contact.dart';
import 'package:dt/models/sos_log.dart';
import 'package:dt/services/location_service.dart';
import 'package:dt/services/messaging_service.dart';
import 'package:dt/services/storage_service.dart';
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
    final Position? position = await _locationService.getLocation().timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    final mapsLink = position != null
        ? 'https://maps.google.com/?q=${position.latitude},${position.longitude}'
        : 'Location unavailable';

    final whatsappMessage = '🚨 SOS ALERT\n'
        'This is an automated emergency alert.\n'
        'Location: $mapsLink\n'
        'Time: ${DateTime.now().toLocal()}\n'
        '— Sent from SOS Keychain app';

    final smsMessage = 'SOS ALERT. Need help immediately. '
      'Location: $mapsLink '
      'Time: ${DateTime.now().toLocal()}';

    final List<EmergencyContact> contacts = await _storageService.getContacts();
    final List<String> notified = [];

    for (final contact in contacts) {
      if (contact.sendSMS) {
        await _messagingService.sendSMS(contact.phone, smsMessage);
      }
      if (contact.sendWhatsApp) {
        await _messagingService.sendWhatsApp(contact.phone, whatsappMessage);
      }
      notified.add(contact.name);
    }

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
