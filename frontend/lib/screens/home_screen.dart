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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.2),
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
    return Scaffold(
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
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: AppTheme.heroGradient,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
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
                                  color: AppTheme.textSecondary,
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
                  child: _buildConnectionCard(connected),
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
                      childAspectRatio: 1.1,
                    ),
                    delegate: SliverChildListDelegate([
                      _buildActionCard(
                        icon: Icons.bluetooth_connected_rounded,
                        title: 'Pair Device',
                        subtitle: _pairedDevice != null ? 'Connected' : 'Not paired',
                        color: AppTheme.info,
                        onTap: () => context.go('/pair'),
                      ),
                      _buildActionCard(
                        icon: Icons.people_rounded,
                        title: 'Contacts',
                        subtitle: '$_contactCount configured',
                        color: AppTheme.secondaryColor,
                        onTap: () async {
                          await context.push('/contacts');
                          _loadData();
                        },
                      ),
                      _buildActionCard(
                        icon: Icons.history_rounded,
                        title: 'SOS History',
                        subtitle: 'View past alerts',
                        color: AppTheme.warning,
                        onTap: () => context.push('/history'),
                      ),
                      _buildActionCard(
                        icon: Icons.settings_rounded,
                        title: 'Settings',
                        subtitle: 'App preferences',
                        color: AppTheme.textSecondary,
                        onTap: () => context.push('/settings'),
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
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        GradientButton(
                          onPressed: _isTestingSOS ? null : _testSOS,
                          text: 'Test SOS Alert',
                          icon: Icons.warning_rounded,
                          isLoading: _isTestingSOS,
                          gradient: AppTheme.sosGradient,
                        ),
                      ],
                    ),
                  ),
                ),

                // Safety Tips
                SliverToBoxAdapter(
                  child: _buildSafetyTips(),
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

  Widget _buildConnectionCard(bool connected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: connected ? AppTheme.successGradient : AppTheme.heroGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
          boxShadow: AppTheme.softShadow,
        ),
        child: Row(
          children: [
            // Status Icon with animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    boxShadow: connected
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(
                                alpha: 0.3 * _pulseController.value,
                              ),
                              blurRadius: 20 * _pulseController.value,
                              spreadRadius: 5 * _pulseController.value,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    connected
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_disabled_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                );
              },
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? 'Keychain Connected' : 'Keychain Disconnected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    connected
                        ? 'Your SOS keychain is active and monitoring'
                        : 'Connect your keychain to enable protection',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                  ),
                  if (_pairedDevice != null && connected) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _pairedDevice!.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
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
  }) {
    return GradientCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 26,
            ),
          ),
          const Spacer(),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyTips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: AppTheme.info.withValues(alpha: 0.2),
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
                    color: AppTheme.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.lightbulb_rounded,
                    color: AppTheme.info,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Safety Tip',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.info,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Hold the SOS button on your keychain for 2 seconds to trigger an emergency alert. '
              'Your location will be automatically sent to all your emergency contacts.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
