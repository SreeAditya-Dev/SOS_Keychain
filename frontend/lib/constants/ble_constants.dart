class BLEConstants {
  // Device name must match ESP32's BLEDevice::init("SOS_KEYCHAIN")
  static const String deviceName = 'SOS_KEYCHAIN';
  
  // UUIDs must match ESP32's SERVICE_UUID and CHARACTERISTIC_UUID
  static const String serviceUUID = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String sosCharUUID = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  
  // ESP32 sends string data, not bytes
  static const String sosTriggerMessage = 'SOS_ALERT_TRIGGERED';
  static const String sosCancelledMessage = 'SOS_CANCELLED';
}
