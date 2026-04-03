import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
import 'package:flutter_foreground_task/models/notification_visibility.dart'
    as fft;
import 'package:go_router/go_router.dart';
import 'package:workmanager/workmanager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final _storageService = StorageService.instance;
final _bleService = BLEService();
final _sosService = SOSService(storageService: StorageService.instance);
final _notificationService = NotificationService.instance;

late final GoRouter _router;

/// Global theme notifier for dark mode toggle
class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _updateSystemUI();
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    _updateSystemUI();
    notifyListeners();
  }

  void _updateSystemUI() {
    if (_themeMode == ThemeMode.dark) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppTheme.backgroundDark,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppTheme.backgroundLight,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );
    }
  }

  Future<void> loadFromStorage() async {
    final isDark = await _storageService.getSetting<bool>('dark_mode') ?? true;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _updateSystemUI();
    notifyListeners();
  }

  Future<void> saveToStorage() async {
    await _storageService.saveSetting('dark_mode', isDarkMode);
  }
}

final themeNotifier = ThemeNotifier();

// WorkManager callback - runs in background even if app is killed
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) {
    debugPrint('🔄 WorkManager task executing: $task');
    // The native KeepAliveWorker will restart the service
    // This callback ensures WorkManager is registered
    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved theme preference
  await themeNotifier.loadFromStorage();

  // Initialize WorkManager for background task management
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

  initForegroundTask();
  await _notificationService.initialize(
    onNotificationTap: _handleNotificationTap,
  );
  await _notificationService.requestPermissions();

  final onboardingDone = await _storageService.isOnboardingDone();
  final pairedDevice = await _storageService.getPairedDevice();

  _router = _buildRouter(onboardingDone: onboardingDone);

  // Run the app first, then init BLE in background
  runApp(const SafeHerApp());

  // Initialize BLE and start foreground service if device is paired
  Future.microtask(() async {
    await _bleService.init(pairedDevice?.id, _handleSOSTrigger);
    // Listen for connection changes to show notifications
    _bleService.connectionStream.listen(_handleConnectionChange);

    // Start foreground service if device is paired to keep app alive
    if (pairedDevice != null) {
      await _startForegroundService();
      await _startNativeKeepAliveService();
      await _schedulePeriodicKeepAlive();
    }
  });
}

GoRouter _buildRouter({required bool onboardingDone}) {
  return GoRouter(
    initialLocation: onboardingDone ? '/home' : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            OnboardingScreen(storageService: _storageService),
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
        builder: (context, state) =>
            ContactsScreen(storageService: _storageService),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => SettingsScreen(
          storageService: _storageService,
          themeNotifier: themeNotifier,
          bleService: _bleService,
        ),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) =>
            HistoryScreen(storageService: _storageService),
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

// Store last SOS log for notification tap handling
SOSLog? _lastSOSLog;

// Method channel for native KeepAlive service
const _keepAliveChannel = MethodChannel('com.safeher.app/lifecycle');

/// Start the native KeepAlive service (survives app death)
Future<void> _startNativeKeepAliveService() async {
  try {
    await _keepAliveChannel.invokeMethod('startKeepAliveService');
    debugPrint('✅ Native KeepAlive service started');
  } catch (e) {
    debugPrint('❌ Failed to start native KeepAlive service: $e');
  }
}

/// Schedule periodic WorkManager task to ensure service stays alive
Future<void> _schedulePeriodicKeepAlive() async {
  try {
    await Workmanager().registerPeriodicTask(
      'keepalive-check',
      'keepAliveCheck',
      frequency: const Duration(
        minutes: 15,
      ), // Minimum interval allowed by Android
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
    debugPrint('✅ WorkManager periodic task scheduled');
  } catch (e) {
    debugPrint('❌ Failed to schedule WorkManager task: $e');
  }
}

Future<void> _handleSOSTrigger() async {
  // Enable WakeLock to keep device awake during SOS trigger
  try {
    await WakelockPlus.enable();
    debugPrint('🔒 WakeLock enabled for SOS trigger');
  } catch (e) {
    debugPrint('⚠️ Failed to enable WakeLock: $e');
  }

  final contacts = await _storageService.getContacts();
  final log = await _sosService.triggerSOS();

  // Store for notification tap
  _lastSOSLog = log;

  // Show enhanced notification with SOS log ID
  String? locationInfo;
  if (log.lat != null && log.lng != null) {
    locationInfo =
        'Location: ${log.lat!.toStringAsFixed(4)}, ${log.lng!.toStringAsFixed(4)}';
  }

  await _notificationService.showSOSTriggered(
    contactCount: contacts.length,
    locationInfo: locationInfo,
    sosLogId: log.id, // Pass the SOS log ID
  );

  _router.go('/sos', extra: log);

  // Keep WakeLock active for 30 seconds during SOS
  Future.delayed(const Duration(seconds: 30), () async {
    try {
      await WakelockPlus.disable();
      debugPrint('🔓 WakeLock disabled after SOS');
    } catch (e) {
      debugPrint('⚠️ Failed to disable WakeLock: $e');
    }
  });
}

void _handleNotificationTap(NotificationResponse response) async {
  debugPrint(
    '📱 Notification tapped: action=${response.actionId}, payload=${response.payload}',
  );

  // Handle "I'm Safe" action
  if (response.actionId == 'cancel_sos') {
    if (_lastSOSLog != null) {
      await _sosService.cancelSOS(_lastSOSLog!);
      await _notificationService.showSOSCancelled();
      _lastSOSLog = null;
    }
    _router.go('/home');
    return;
  }

  // Handle notification tap or "View SOS" action
  if (_lastSOSLog != null && !(_lastSOSLog!.wasCancelled)) {
    // Navigate to SOS screen with the log
    _router.go('/sos', extra: _lastSOSLog);
  } else if (response.payload != null && response.payload!.isNotEmpty) {
    // Try to load SOS log from storage using payload ID
    final logs = await _storageService.getSOSLogs();
    final log = logs.where((l) => l.id == response.payload).firstOrNull;
    if (log != null && !log.wasCancelled) {
      _router.go('/sos', extra: log);
      return;
    }
    _router.go('/home');
  } else {
    // No active SOS, navigate to home
    _router.go('/home');
  }
}

bool _wasConnected = false;

void _handleConnectionChange(bool isConnected) async {
  final pairedDevice = await _storageService.getPairedDevice();
  final deviceName = pairedDevice?.name ?? 'SOS Keychain';

  if (isConnected && !_wasConnected) {
    await _notificationService.showDeviceConnected(deviceName);
    // Start foreground service when connected to keep app alive
    _startForegroundService();
  } else if (!isConnected && _wasConnected) {
    await _notificationService.showDeviceDisconnected(deviceName);
  }
  _wasConnected = isConnected;
}

Future<void> _startForegroundService() async {
  // Check if service is already running
  if (await FlutterForegroundTask.isRunningService) {
    return;
  }

  // Check if battery optimization is already disabled before requesting
  final isBatteryOptimizationDisabled =
      await FlutterForegroundTask.isIgnoringBatteryOptimizations;

  if (!isBatteryOptimizationDisabled) {
    // Only request if not already granted
    debugPrint('📋 Requesting battery optimization exemption...');
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  } else {
    debugPrint('✅ Battery optimization already disabled');
  }

  await FlutterForegroundTask.startService(
    notificationTitle: 'SafeHer Active',
    notificationText: 'Your SOS keychain is connected and monitoring',
    callback: _foregroundTaskCallback,
  );
}

Future<void> _stopForegroundService() async {
  await FlutterForegroundTask.stopService();
}

// This callback runs in background
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_SafeHerTaskHandler());
}

class _SafeHerTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {
    print('Foreground service started');
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // This runs every interval (as configured in initForegroundTask)
    // The BLE service auto-reconnect handles reconnection
    // This just keeps the app alive in background
    print('Background check: ${DateTime.now()}');
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    print('Foreground service destroyed');
  }
}

void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'safeher_protection',
      channelName: 'SafeHer Protection',
      channelDescription: 'SafeHer is active — protecting you',
      channelImportance: NotificationChannelImportance.DEFAULT,
      priority: NotificationPriority.DEFAULT,
      showWhen: false,
      visibility: fft.NotificationVisibility.VISIBILITY_PUBLIC,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: const ForegroundTaskOptions(
      interval: 5000, // Check every 5 seconds
      isOnceEvent: false,
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

class SafeHerApp extends StatefulWidget {
  const SafeHerApp({super.key});

  @override
  State<SafeHerApp> createState() => _SafeHerAppState();
}

class _SafeHerAppState extends State<SafeHerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Don't request here - it's requested when foreground service starts
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('App lifecycle state: $state');
    // When app goes to background, the foreground service keeps it alive
    // BLE service continues to run and trigger SOS when button is pressed
  }

  @override
  Widget build(BuildContext context) {
    // WithForegroundTask keeps the Dart VM alive even when UI is minimized
    return WithForegroundTask(
      child: ListenableBuilder(
        listenable: themeNotifier,
        builder: (context, child) {
          return MaterialApp.router(
            title: 'SafeHer',
            debugShowCheckedModeBanner: false,
            routerConfig: _router,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeNotifier.themeMode,
          );
        },
      ),
    );
  }
}
