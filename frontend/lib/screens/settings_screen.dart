import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:safeher/constants/app_theme.dart';
import 'package:safeher/main.dart';
import 'package:safeher/services/ble_service.dart';
import 'package:safeher/services/notification_service.dart';
import 'package:safeher/services/storage_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.storageService,
    required this.themeNotifier,
    required this.bleService,
  });

  final StorageService storageService;
  final ThemeNotifier themeNotifier;
  final BLEService bleService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _connectionAlerts = true;
  bool _autoReconnect = true;
  bool _vibrationEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = widget.storageService;
    final settings = await prefs.getSettings();
    
    if (mounted) {
      setState(() {
        _notificationsEnabled = settings['notificationsEnabled'] ?? true;
        _connectionAlerts = settings['connectionAlerts'] ?? true;
        _autoReconnect = settings['autoReconnect'] ?? true;
        _vibrationEnabled = settings['vibrationEnabled'] ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    await widget.storageService.saveSettings({
      'notificationsEnabled': _notificationsEnabled,
      'connectionAlerts': _connectionAlerts,
      'autoReconnect': _autoReconnect,
      'vibrationEnabled': _vibrationEnabled,
    });
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  Future<void> _checkPermissions() async {
    final statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.sms,
      Permission.notification,
    ].request();

    if (!mounted) return;

    final deniedPermissions = statuses.entries
        .where((e) => !e.value.isGranted)
        .map((e) => _permissionName(e.key))
        .toList();

    if (deniedPermissions.isEmpty) {
      _showSnackBar('All permissions granted!', isSuccess: true);
    } else {
      _showSnackBar(
        'Missing: ${deniedPermissions.join(", ")}',
        isSuccess: false,
      );
    }
  }

  String _permissionName(Permission permission) {
    switch (permission) {
      case Permission.location:
        return 'Location';
      case Permission.bluetooth:
      case Permission.bluetoothScan:
      case Permission.bluetoothConnect:
        return 'Bluetooth';
      case Permission.sms:
        return 'SMS';
      case Permission.notification:
        return 'Notifications';
      default:
        return permission.toString();
    }
  }

  void _showSnackBar(String message, {bool isSuccess = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.warning_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isSuccess ? AppTheme.success : AppTheme.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  Future<void> _unpairDevice() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pairedDevice = await widget.storageService.getPairedDevice();
    
    if (pairedDevice == null) {
      _showSnackBar('No device paired', isSuccess: false);
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.bluetooth_disabled_rounded,
                color: AppTheme.warning,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Unpair Device'),
          ],
        ),
        content: Text(
          'Are you sure you want to unpair "${pairedDevice.name}"?\n\n'
          'You will need to pair again to use SOS features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Force disconnect from device (prevents auto-reconnect)
      await widget.bleService.forceDisconnect();
      
      // Give ESP32 time to restart advertising
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Clear paired device from storage
      await widget.storageService.clearPairedDevice();
      
      if (mounted) {
        _showSnackBar('Device unpaired successfully', isSuccess: true);
        
        // Navigate to pair screen
        context.go('/pair');
      }
    }
  }

  Future<void> _clearAllData() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: AppTheme.error,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Clear All Data'),
          ],
        ),
        content: const Text(
          'This will delete all your contacts, paired devices, and SOS history. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.storageService.clearAllData();
      if (mounted) {
        _showSnackBar('All data cleared', isSuccess: true);
      }
    }
  }

  Future<void> _testNotifications() async {
    await NotificationService.instance.showSafetyReminder(
      title: 'Test Notification',
      message: 'This is a test notification from SafeHer. Notifications are working correctly!',
    );
    _showSnackBar('Test notification sent!', isSuccess: true);
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse('https://safeher.app/privacy');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openTermsOfService() async {
    final uri = Uri.parse('https://safeher.app/terms');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _toggleDarkMode(bool value) {
    widget.themeNotifier.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
    widget.themeNotifier.saveToStorage();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primaryColor,
                ),
              )
            : CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                                ),
                              ),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Settings',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Appearance Section
                  SliverToBoxAdapter(
                    child: _buildSectionHeader('Appearance', isDark),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSettingsCard([
                      _buildSwitchTile(
                        icon: Icons.dark_mode_rounded,
                        title: 'Dark Mode',
                        subtitle: 'Switch to dark theme',
                        value: widget.themeNotifier.isDarkMode,
                        onChanged: _toggleDarkMode,
                        isDark: isDark,
                      ),
                    ], isDark),
                  ),

                  // Notification Settings Section
                  SliverToBoxAdapter(
                    child: _buildSectionHeader('Notifications', isDark),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSettingsCard([
                      _buildSwitchTile(
                        icon: Icons.notifications_rounded,
                        title: 'Push Notifications',
                        subtitle: 'Receive SOS and status alerts',
                        value: _notificationsEnabled,
                        onChanged: (val) {
                          setState(() => _notificationsEnabled = val);
                          _saveSettings();
                        },
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.bluetooth_connected_rounded,
                        title: 'Connection Alerts',
                        subtitle: 'Notify when keychain connects/disconnects',
                        value: _connectionAlerts,
                        onChanged: (val) {
                          setState(() => _connectionAlerts = val);
                          _saveSettings();
                        },
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildActionTile(
                        icon: Icons.notifications_active_rounded,
                        title: 'Test Notifications',
                        subtitle: 'Send a test notification',
                        onTap: _testNotifications,
                        isDark: isDark,
                      ),
                    ], isDark),
                  ),

                  // Device Settings Section
                  SliverToBoxAdapter(
                    child: _buildSectionHeader('Device', isDark),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSettingsCard([
                      _buildSwitchTile(
                        icon: Icons.autorenew_rounded,
                        title: 'Auto Reconnect',
                        subtitle: 'Automatically reconnect to paired device',
                        value: _autoReconnect,
                        onChanged: (val) {
                          setState(() => _autoReconnect = val);
                          _saveSettings();
                        },
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.vibration_rounded,
                        title: 'Vibration',
                        subtitle: 'Vibrate on SOS trigger',
                        value: _vibrationEnabled,
                        onChanged: (val) {
                          setState(() => _vibrationEnabled = val);
                          _saveSettings();
                        },
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildActionTile(
                        icon: Icons.bluetooth_disabled_rounded,
                        title: 'Unpair Device',
                        subtitle: 'Disconnect and remove paired keychain',
                        onTap: _unpairDevice,
                        isDestructive: true,
                        isDark: isDark,
                      ),
                    ], isDark),
                  ),

                  // Permissions Section
                  SliverToBoxAdapter(
                    child: _buildSectionHeader('Permissions', isDark),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSettingsCard([
                      _buildActionTile(
                        icon: Icons.security_rounded,
                        title: 'Check Permissions',
                        subtitle: 'Verify all required permissions',
                        onTap: _checkPermissions,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildActionTile(
                        icon: Icons.settings_rounded,
                        title: 'App Settings',
                        subtitle: 'Open system app settings',
                        onTap: _openAppSettings,
                        showArrow: true,
                        isDark: isDark,
                      ),
                    ], isDark),
                  ),

                  // Data Section
                  SliverToBoxAdapter(
                    child: _buildSectionHeader('Data & Privacy', isDark),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSettingsCard([
                      _buildActionTile(
                        icon: Icons.history_rounded,
                        title: 'SOS History',
                        subtitle: 'View past SOS alerts',
                        onTap: () => context.push('/history'),
                        showArrow: true,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildActionTile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Clear All Data',
                        subtitle: 'Delete contacts, devices, and history',
                        onTap: _clearAllData,
                        isDestructive: true,
                        isDark: isDark,
                      ),
                    ], isDark),
                  ),

                  // About Section
                  SliverToBoxAdapter(
                    child: _buildSectionHeader('About', isDark),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSettingsCard([
                      _buildActionTile(
                        icon: Icons.info_outline_rounded,
                        title: 'App Version',
                        subtitle: 'SafeHer v1.0.0',
                        onTap: () {},
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildActionTile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy Policy',
                        subtitle: 'Read our privacy policy',
                        onTap: _openPrivacyPolicy,
                        showArrow: true,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildActionTile(
                        icon: Icons.description_outlined,
                        title: 'Terms of Service',
                        subtitle: 'Read our terms of service',
                        onTap: _openTermsOfService,
                        showArrow: true,
                        isDark: isDark,
                      ),
                    ], isDark),
                  ),

                  // Footer
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.asset(
                                'assets/icons/safeher_logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'SafeHer',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your safety, our priority',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Made with love for women\'s safety',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark ? AppTheme.textMutedDark : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 40),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          ),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.subtleGoldDark : AppTheme.subtleGold,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: AppTheme.primaryColor,
              size: 20,
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
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showArrow = false,
    bool isDestructive = false,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDestructive
                    ? AppTheme.error.withValues(alpha: 0.1)
                    : (isDark ? AppTheme.subtleGoldDark : AppTheme.subtleGold),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isDestructive ? AppTheme.error : AppTheme.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isDestructive ? AppTheme.error : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (showArrow)
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? AppTheme.textMutedDark : AppTheme.textMuted,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 70,
      endIndent: 16,
      color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
    );
  }
}
