import 'package:dt/models/sos_log.dart';
import 'package:dt/screens/contacts_screen.dart';
import 'package:dt/screens/home_screen.dart';
import 'package:dt/screens/onboarding_screen.dart';
import 'package:dt/screens/pair_device_screen.dart';
import 'package:dt/screens/sos_triggered_screen.dart';
import 'package:dt/services/ble_service.dart';
import 'package:dt/services/sos_service.dart';
import 'package:dt/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

final _storageService = StorageService.instance;
final _bleService = BLEService();
final _sosService = SOSService(storageService: StorageService.instance);
final _localNotifications = FlutterLocalNotificationsPlugin();

late final GoRouter _router;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  initForegroundTask();
  await _initLocalNotifications();

  final onboardingDone = await _storageService.isOnboardingDone();
  final pairedDevice = await _storageService.getPairedDevice();

  _router = _buildRouter(onboardingDone: onboardingDone);
  await _bleService.init(pairedDevice?.id, _handleSOSTrigger);

  runApp(const SOSKeychainApp());
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
        ),
      ),
      GoRoute(
        path: '/contacts',
        builder: (context, state) => ContactsScreen(storageService: _storageService),
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
  final log = await _sosService.triggerSOS();
  await _localNotifications.show(
    1001,
    'SOS Triggered',
    'Emergency alert sent to your contacts',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'sos_keychain_alerts',
        'SOS Alerts',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );

  _router.go('/sos', extra: log);
}

Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const settings = InitializationSettings(android: androidSettings);
  await _localNotifications.initialize(settings);
}

void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'sos_keychain',
      channelName: 'SOS Keychain',
      channelDescription: 'SOS Keychain active — protecting you',
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

class SOSKeychainApp extends StatelessWidget {
  const SOSKeychainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SOS Keychain Companion',
      routerConfig: _router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
        useMaterial3: true,
      ),
    );
  }
}
