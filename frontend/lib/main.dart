import 'package:safeher/constants/app_theme.dart';
import 'package:safeher/models/sos_log.dart';
import 'package:safeher/screens/contacts_screen.dart';
import 'package:safeher/screens/history_screen.dart';
import 'package:safeher/screens/home_screen.dart';
import 'package:safeher/screens/onboarding_screen.dart';
import 'package:safeher/screens/pair_device_screen.dart';
import 'package:safeher/screens/settings_screen.dart';
import 'package:safeher/screens/sos_triggered_screen.dart';
import 'package:safeher/services/ble_service.dart';
import 'package:safeher/services/notification_service.dart';
import 'package:safeher/services/sos_service.dart';
import 'package:safeher/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:go_router/go_router.dart';

final _storageService = StorageService.instance;
final _bleService = BLEService();
final _sosService = SOSService(storageService: StorageService.instance);
final _notificationService = NotificationService.instance;

late final GoRouter _router;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style for a cleaner look
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppTheme.backgroundLight,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  initForegroundTask();
  await _notificationService.initialize(
    onNotificationTap: _handleNotificationTap,
  );
  await _notificationService.requestPermissions();

  final onboardingDone = await _storageService.isOnboardingDone();
  final pairedDevice = await _storageService.getPairedDevice();

  _router = _buildRouter(onboardingDone: onboardingDone);
  await _bleService.init(pairedDevice?.id, _handleSOSTrigger);
  
  // Listen for connection changes to show notifications
  _bleService.connectionStream.listen(_handleConnectionChange);

  runApp(const SafeHerApp());
}

GoRouter _buildRouter({required bool onboardingDone}) {
  return GoRouter(
    initialLocation: onboardingDone ? '/home' : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => OnboardingScreen(storageService: _storageService),
      ),
      GoRoute(
        path: '/pair',
        builder: (context, state) => PairDeviceScreen(
          bleService: _bleService,
          storageService: _storageService,
          onSOSTrigger: _handleSOSTrigger,
        ),
      ),
      GoRoute(
        path: '/contacts',
        builder: (context, state) => ContactsScreen(storageService: _storageService),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => SettingsScreen(storageService: _storageService),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => HistoryScreen(storageService: _storageService),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => HomeScreen(
          bleService: _bleService,
          storageService: _storageService,
          onTestSOS: _handleSOSTrigger,
        ),
      ),
      GoRoute(
        path: '/sos',
        builder: (context, state) {
          final log = state.extra;
          if (log is! SOSLog) {
            return HomeScreen(
              bleService: _bleService,
              storageService: _storageService,
              onTestSOS: _handleSOSTrigger,
            );
          }

          return SOSTriggeredScreen(
            log: log,
            sosService: _sosService,
            bleService: _bleService,
          );
        },
      ),
    ],
  );
}

Future<void> _handleSOSTrigger() async {
  final contacts = await _storageService.getContacts();
  final log = await _sosService.triggerSOS();
  
  // Show enhanced notification
  String? locationInfo;
  if (log.lat != null && log.lng != null) {
    locationInfo = 'Location: ${log.lat!.toStringAsFixed(4)}, ${log.lng!.toStringAsFixed(4)}';
  }
  
  await _notificationService.showSOSTriggered(
    contactCount: contacts.length,
    locationInfo: locationInfo,
  );

  _router.go('/sos', extra: log);
}

void _handleNotificationTap(dynamic response) {
  // Handle notification taps - navigate to appropriate screen
  if (response.actionId == 'cancel_sos') {
    // User tapped "I'm Safe" action - will be handled in SOS screen
  } else {
    // Navigate to home screen on notification tap
    _router.go('/home');
  }
}

bool _wasConnected = false;

void _handleConnectionChange(bool isConnected) async {
  final pairedDevice = await _storageService.getPairedDevice();
  final deviceName = pairedDevice?.name ?? 'SOS Keychain';
  
  if (isConnected && !_wasConnected) {
    await _notificationService.showDeviceConnected(deviceName);
  } else if (!isConnected && _wasConnected) {
    await _notificationService.showDeviceDisconnected(deviceName);
  }
  _wasConnected = isConnected;
}

void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'safeher_protection',
      channelName: 'SafeHer Protection',
      channelDescription: 'SafeHer is active — protecting you',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: const ForegroundTaskOptions(
      interval: 15000,
      isOnceEvent: false,
      autoRunOnBoot: true,
    ),
  );
}

class SafeHerApp extends StatelessWidget {
  const SafeHerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SafeHer',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: AppTheme.lightTheme,
    );
  }
}
