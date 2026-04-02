import 'package:safeher/constants/app_theme.dart';
import 'package:safeher/services/storage_service.dart';
import 'package:safeher/widgets/custom_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.storageService,
  });

  final StorageService storageService;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  List<Permission> get _requiredPermissions => [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
    Permission.sms,
    Permission.notification,
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await _requiredPermissions.request();
  }

  Future<List<Permission>> _getMissingPermissions() async {
    final missing = <Permission>[];
    for (final permission in _requiredPermissions) {
      final status = await permission.status;
      if (!status.isGranted) {
        missing.add(permission);
      }
    }
    return missing;
  }

  String _permissionName(Permission permission) {
    if (permission == Permission.bluetooth) return 'Bluetooth';
    if (permission == Permission.bluetoothScan) return 'Bluetooth Scan';
    if (permission == Permission.bluetoothConnect) return 'Bluetooth Connect';
    if (permission == Permission.location) return 'Location';
    if (permission == Permission.sms) return 'SMS';
    if (permission == Permission.notification) return 'Notifications';
    return permission.toString();
  }

  Future<void> _showPermissionReminder(List<Permission> missing) async {
    final labels = missing.map(_permissionName).join(', ');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.warning_rounded,
                  color: AppTheme.warning,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Permissions Needed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For SafeHer to protect you effectively, please enable:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ...missing.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 12),
                    Text(_permissionName(p)),
                  ],
                ),
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Later',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await openAppSettings();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isLoading = true);
    
    await _requestPermissions();
    final missing = await _getMissingPermissions();

    if (missing.isNotEmpty) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      await _showPermissionReminder(missing);
      return;
    }

    await widget.storageService.setOnboardingDone(true);
    setState(() => _isLoading = false);
    
    if (mounted) {
      context.go('/pair');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Page indicator
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppTheme.primaryColor
                          : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  _buildWelcomePage(isDark),
                  _buildFeaturesPage(isDark),
                  _buildPermissionsPage(isDark),
                ],
              ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: _currentPage == 2
                  ? GradientButton(
                      onPressed: _isLoading ? null : _completeOnboarding,
                      text: 'Get Started',
                      icon: Icons.arrow_forward_rounded,
                      isLoading: _isLoading,
                    )
                  : Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            _pageController.jumpToPage(2);
                          },
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        GradientButton(
                          onPressed: _nextPage,
                          text: 'Next',
                          width: 120,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/icons/safeher_logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'SafeHer',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your personal safety companion',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'One press is all it takes to alert your loved ones and send your location in an emergency.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesPage(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'How It Works',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Simple, fast, and reliable protection',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          const FeatureItem(
            icon: Icons.bluetooth_connected_rounded,
            title: 'Connect Your Keychain',
            description: 'Pair your SOS keychain device via Bluetooth',
          ),
          const FeatureItem(
            icon: Icons.contact_phone_rounded,
            title: 'Add Emergency Contacts',
            description: 'Choose who gets notified when you need help',
          ),
          const FeatureItem(
            icon: Icons.touch_app_rounded,
            title: 'Press & Hold for SOS',
            description: 'Hold the button for 2 seconds to trigger alert',
          ),
          const FeatureItem(
            icon: Icons.location_on_rounded,
            title: 'Auto Location Sharing',
            description: 'Your GPS location is sent automatically',
          ),
          const FeatureItem(
            icon: Icons.message_rounded,
            title: 'Instant Notifications',
            description: 'Contacts receive SMS & WhatsApp alerts',
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsPage(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Permissions Needed',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We need a few permissions to keep you safe',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          _buildPermissionItem(
            icon: Icons.bluetooth_rounded,
            title: 'Bluetooth',
            description: 'Connect to your SOS keychain device',
            color: AppTheme.info,
            isDark: isDark,
          ),
          _buildPermissionItem(
            icon: Icons.location_on_rounded,
            title: 'Location',
            description: 'Share your location during emergencies',
            color: AppTheme.success,
            isDark: isDark,
          ),
          _buildPermissionItem(
            icon: Icons.sms_rounded,
            title: 'SMS',
            description: 'Send emergency text messages',
            color: AppTheme.primaryColor,
            isDark: isDark,
          ),
          _buildPermissionItem(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            description: 'Alert you when SOS is triggered',
            color: AppTheme.warning,
            isDark: isDark,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.subtleGoldDark : AppTheme.subtleGold,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.privacy_tip_rounded,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your privacy is important. These permissions are only used for emergency alerts.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
