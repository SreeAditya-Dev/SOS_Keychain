import 'package:safeher/constants/app_theme.dart';
import 'package:safeher/models/paired_device.dart';
import 'package:safeher/services/ble_service.dart';
import 'package:safeher/services/storage_service.dart';
import 'package:safeher/widgets/custom_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.bleService,
    required this.storageService,
    required this.onTestSOS,
  });

  final BLEService bleService;
  final StorageService storageService;
  final Future<void> Function() onTestSOS;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  PairedDevice? _pairedDevice;
  int _contactCount = 0;
  bool _isTestingSOS = false;
  late AnimationController _pulseController;

  List<Permission> get _requiredPermissions => [
        Permission.location,
        Permission.sms,
        Permission.notification,
      ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _loadData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final pairedDevice = await widget.storageService.getPairedDevice();
    final contacts = await widget.storageService.getContacts();
    if (mounted) {
      setState(() {
        _pairedDevice = pairedDevice;
        _contactCount = contacts.length;
      });
    }
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
                ),
              ),
              const SizedBox(width: 12),
              const Text('Permissions Required'),
            ],
          ),
          content: Text(
            'Please enable $labels to send SOS alerts correctly.\n\n'
            'Open app settings to grant permissions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            GradientButton(
              onPressed: () async {
                await openAppSettings();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              text: 'Open Settings',
              width: 140,
              height: 44,
            ),
          ],
        );
      },
    );
  }

  Future<void> _testSOS() async {
    final missingPermissions = await _getMissingPermissions();
    if (!mounted) return;

    if (missingPermissions.isNotEmpty) {
      await _showPermissionReminder(missingPermissions);
      return;
    }

    final contacts = await widget.storageService.getContacts();
    if (!mounted) return;

    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text('No emergency contacts configured'),
            ],
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
        ),
      );
      return;
    }

    setState(() => _isTestingSOS = true);
    await widget.onTestSOS();
    if (mounted) {
      setState(() => _isTestingSOS = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      body: SafeArea(
        child: StreamBuilder<bool>(
          stream: widget.bleService.connectionStream,
          initialData: widget.bleService.isConnected,
          builder: (context, snapshot) {
            final connected = snapshot.data ?? false;
            return CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.shield_rounded,
                            color: AppTheme.textOnGold,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SafeHer',
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                              Text(
                                connected ? 'Ready to protect you' : 'Connect your keychain',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Connection Status Card
                SliverToBoxAdapter(
                  child: _buildConnectionCard(connected, isDark),
                ),

                // Quick Actions
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),

                // Action Cards Grid
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.15,
                    ),
                    delegate: SliverChildListDelegate([
                      _buildActionCard(
                        icon: Icons.bluetooth_connected_rounded,
                        title: 'Pair Device',
                        subtitle: _pairedDevice != null ? 'Connected' : 'Not paired',
                        color: AppTheme.info,
                        onTap: () => context.go('/pair'),
                        isDark: isDark,
                      ),
                      _buildActionCard(
                        icon: Icons.people_rounded,
                        title: 'Contacts',
                        subtitle: '$_contactCount configured',
                        color: AppTheme.primaryColor,
                        onTap: () async {
                          await context.push('/contacts');
                          _loadData();
                        },
                        isDark: isDark,
                      ),
                      _buildActionCard(
                        icon: Icons.history_rounded,
                        title: 'SOS History',
                        subtitle: 'View past alerts',
                        color: AppTheme.warning,
                        onTap: () => context.push('/history'),
                        isDark: isDark,
                      ),
                      _buildActionCard(
                        icon: Icons.settings_rounded,
                        title: 'Settings',
                        subtitle: 'App preferences',
                        color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
                        onTap: () => context.push('/settings'),
                        isDark: isDark,
                      ),
                    ]),
                  ),
                ),

                // Test SOS Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Test Your Setup',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Send a test alert to verify everything works',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isTestingSOS ? null : _testSOS,
                            icon: _isTestingSOS 
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.warning_rounded),
                            label: Text(_isTestingSOS ? 'Sending...' : 'Test SOS Alert'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.error,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Safety Tips
                SliverToBoxAdapter(
                  child: _buildSafetyTips(isDark),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 20),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildConnectionCard(bool connected, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: connected 
              ? AppTheme.success.withValues(alpha: isDark ? 0.15 : 0.1)
              : (isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: connected 
                ? AppTheme.success.withValues(alpha: 0.3)
                : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
          ),
        ),
        child: Row(
          children: [
            // Status Icon with animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected 
                        ? AppTheme.success.withValues(alpha: 0.15)
                        : AppTheme.primaryColor.withValues(alpha: 0.1),
                    border: connected
                        ? Border.all(
                            color: AppTheme.success.withValues(
                              alpha: 0.3 + (0.3 * _pulseController.value),
                            ),
                            width: 2,
                          )
                        : null,
                  ),
                  child: Icon(
                    connected
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_disabled_rounded,
                    color: connected ? AppTheme.success : AppTheme.primaryColor,
                    size: 28,
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? 'Keychain Connected' : 'Keychain Disconnected',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: connected ? AppTheme.success : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    connected
                        ? 'Your SOS keychain is active and monitoring'
                        : 'Connect your keychain to enable protection',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_pairedDevice != null && connected) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _pairedDevice!.name,
                        style: TextStyle(
                          color: AppTheme.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!connected)
              IconButton(
                onPressed: () => context.go('/pair'),
                icon: Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? AppTheme.textMutedDark : AppTheme.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const Spacer(),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildSafetyTips(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.subtleGoldDark : AppTheme.subtleGold,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.lightbulb_rounded,
                    color: AppTheme.primaryColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Safety Tip',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Hold the SOS button on your keychain for 2 seconds to trigger an emergency alert. '
              'Your location will be automatically sent to all your emergency contacts.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
