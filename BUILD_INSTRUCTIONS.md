# SafeHer Build & Testing Instructions

## Prerequisites

1. **Flutter SDK** (3.10.4 or higher)
   - Download from: https://flutter.dev/docs/get-started/install
   - Ensure `flutter` is in your PATH

2. **Android Studio** (for Android builds)
   - Install Android SDK
   - Install Android Build Tools
   - Create an emulator or connect a physical device

3. **ESP32 Hardware Setup**
   - Upload `hardware/main.ino` to your ESP32
   - Pins: SOS Button (GPIO 15), Control Button (GPIO 5), Buzzer (GPIO 4), LED (GPIO 2)

---

## Build Steps

### Step 1: Get Dependencies

```bash
cd frontend
flutter pub get
```

### Step 2: Generate App Icons (Optional - requires icon files)

First, create your icon files in `assets/icons/`:
- `app_icon.png` (1024x1024 px) - Full app icon
- `app_icon_foreground.png` (1024x1024 px) - Icon foreground for adaptive icons
- `splash_logo.png` (512x512 px) - Splash screen logo

Then run:
```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

### Step 3: Build Debug APK

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Step 4: Build Release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

---

## Testing Instructions

### 1. Hardware Testing (ESP32)

1. Power on the ESP32
2. The LED should blink once on startup
3. The device will advertise as "SOS_KEYCHAIN" via BLE

**Test SOS Trigger:**
- Hold the SOS button (GPIO 15) for 2 seconds
- Buzzer should beep rapidly
- LED should flash
- Device sends "SOS_ALERT_TRIGGERED" via BLE

**Test Cancel:**
- Press control button (GPIO 5)
- Buzzer stops
- LED returns to normal

### 2. App Testing

1. Install the APK on your Android device
2. Grant all requested permissions:
   - Bluetooth
   - Bluetooth Scan
   - Bluetooth Connect
   - Location
   - SMS
   - Notifications

**Onboarding Flow:**
1. Launch app → See onboarding screens
2. Swipe through 3 pages
3. Tap "Get Started"

**Device Pairing:**
1. Navigate to "Pair Device"
2. Tap "Start Scan"
3. Find "SOS_KEYCHAIN" in the list
4. Tap to connect
5. Wait for "Connected!" confirmation

**Add Emergency Contacts:**
1. Navigate to "Contacts"
2. Tap "+" to add a contact
3. Enter name and phone number
4. Enable SMS and/or WhatsApp
5. Save

**Test SOS Alert:**
1. Navigate to Home screen
2. Tap "Test SOS Alert"
3. Verify:
   - Notification appears
   - SOS triggered screen shows
   - SMS/WhatsApp is sent to contacts

**Test Hardware SOS:**
1. Ensure keychain is connected (green indicator)
2. Hold SOS button on keychain for 2 seconds
3. App should automatically:
   - Show notification
   - Navigate to SOS screen
   - Send alerts to contacts

---

## New Features Added

### Enhanced Notifications
- SOS triggered notification (high priority, ongoing)
- Device connected notification
- Device disconnected notification (with warning)
- "I'm Safe" action button on SOS notification

### Settings Screen (`/settings`)
- Toggle push notifications
- Toggle connection alerts
- Toggle auto-reconnect
- Toggle vibration
- Test notifications button
- Check permissions
- Clear all data
- View SOS history

### SOS History Screen (`/history`)
- View all past SOS alerts
- See which contacts were notified
- View location coordinates
- Open location in Google Maps
- Delete individual logs
- Clear all history

### Improved Error Handling
- Detailed BLE error messages
- Suggestions for fixing issues
- Automatic retry with exponential backoff (up to 5 attempts)
- Error dialogs for critical issues
- Snackbars for recoverable errors

---

## File Structure

```
frontend/
├── lib/
│   ├── main.dart                 # App entry point & routing
│   ├── constants/
│   │   ├── app_theme.dart        # Theme & colors
│   │   └── ble_constants.dart    # BLE UUIDs & constants
│   ├── models/
│   │   ├── emergency_contact.dart
│   │   ├── paired_device.dart
│   │   └── sos_log.dart
│   ├── screens/
│   │   ├── onboarding_screen.dart
│   │   ├── pair_device_screen.dart
│   │   ├── home_screen.dart
│   │   ├── contacts_screen.dart
│   │   ├── settings_screen.dart   # NEW
│   │   ├── history_screen.dart    # NEW
│   │   └── sos_triggered_screen.dart
│   ├── services/
│   │   ├── ble_service.dart       # Enhanced with error handling
│   │   ├── notification_service.dart # NEW
│   │   ├── sos_service.dart
│   │   ├── storage_service.dart   # Enhanced with settings
│   │   ├── location_service.dart
│   │   └── messaging_service.dart
│   ├── utils/
│   │   └── error_handler.dart     # NEW
│   └── widgets/
│       ├── custom_widgets.dart
│       ├── contact_card.dart
│       └── connection_status_banner.dart
├── assets/
│   └── icons/
│       └── ICON_INSTRUCTIONS.md   # Guide for creating icons
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml    # Updated with SafeHer label
│       └── res/values/
│           └── colors.xml         # NEW - SafeHer colors
└── pubspec.yaml                   # Updated dependencies
```

---

## Troubleshooting

### "Bluetooth is turned off"
- Enable Bluetooth in device settings
- Restart the app

### "Permission denied"
- Go to Settings > Apps > SafeHer > Permissions
- Grant all required permissions

### "Device not found"
- Ensure ESP32 is powered on
- Check if LED blinked on startup
- Move closer to the device
- Try rescanning

### "Connection failed"
- Power cycle the ESP32
- Turn Bluetooth off and on
- Uninstall and reinstall the app

### "SOS not triggering"
- Check that contacts are configured
- Verify SMS/WhatsApp permissions
- Test with "Test SOS Alert" first

---

## Version Info

- App Name: SafeHer
- Package: safeher
- Version: 1.0.0+1
- Min SDK: Android 21 (5.0)
