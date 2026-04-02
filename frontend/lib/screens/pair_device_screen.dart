import 'dart:async';

import 'package:safeher/constants/app_theme.dart';
import 'package:safeher/constants/ble_constants.dart';
import 'package:safeher/models/paired_device.dart';
import 'package:safeher/services/ble_service.dart';
import 'package:safeher/services/storage_service.dart';
import 'package:safeher/utils/error_handler.dart';
import 'package:safeher/widgets/custom_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({
    super.key,
    required this.bleService,
    required this.storageService,
    required this.onSOSTrigger,
  });

  final BLEService bleService;
  final StorageService storageService;
  final Future<void> Function() onSOSTrigger;

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _connectingDeviceId;
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<BLEError>? _errorSubscription;
  late AnimationController _scanAnimationController;

  List<Permission> get _requiredPermissions => [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ];

  @override
  void initState() {
    super.initState();
    _scanAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _scanSubscription = widget.bleService.scanResultsStream.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      }
    });

    _connectionSubscription = widget.bleService.connectionStream.listen((connected) {
      if (mounted && connected && _isConnecting) {
        _onDeviceConnected();
      }
    });
    
    // Listen for BLE errors
    _errorSubscription = widget.bleService.errorStream.listen((error) {
      if (mounted) {
        _handleBLEError(error);
      }
    });
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    widget.bleService.stopScan();
    super.dispose();
  }

  void _handleBLEError(BLEError error) {
    // Don't show disconnect errors while connecting (we show a different message)
    if (_isConnecting && error.type == BLEErrorType.disconnected) return;
    
    // For critical errors, show a dialog
    if (error.type == BLEErrorType.bluetoothOff ||
        error.type == BLEErrorType.bluetoothUnavailable ||
        error.type == BLEErrorType.permissionDenied) {
      ErrorHandler.showBLEErrorDialog(
        context,
        error,
        onRetry: _startScan,
        onOpenSettings: () => openAppSettings(),
      );
    } else {
      // For other errors, show a snackbar
      ErrorHandler.showBLEErrorSnackBar(
        context,
        error,
        onAction: error.type == BLEErrorType.connectionFailed ? _startScan : null,
        actionLabel: 'Retry',
      );
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
    if (permission == Permission.bluetooth) return 'Bluetooth';
    if (permission == Permission.bluetoothScan) return 'Bluetooth Scan';
    if (permission == Permission.bluetoothConnect) return 'Bluetooth Connect';
    if (permission == Permission.location) return 'Location';
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
          title: const Text('Permissions Required'),
          content: Text(
            'Please enable $labels to pair with your SOS keychain.\n\n'
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

  Future<void> _startScan() async {
    final missingPermissions = await _getMissingPermissions();
    if (!mounted) return;
    if (missingPermissions.isNotEmpty) {
      await _showPermissionReminder(missingPermissions);
      return;
    }

    setState(() {
      _isScanning = true;
      _scanResults = [];
    });
    _scanAnimationController.repeat();

    await widget.bleService.startScan();

    // Auto-stop after 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _isScanning) {
        _stopScan();
      }
    });
  }

  void _stopScan() {
    widget.bleService.stopScan();
    _scanAnimationController.stop();
    _scanAnimationController.reset();
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _stopScan();
    
    setState(() {
      _isConnecting = true;
      _connectingDeviceId = device.remoteId.toString();
    });

    final success = await widget.bleService.connectToDevice(
      device,
      widget.onSOSTrigger,
    );

    if (!success && mounted) {
      setState(() {
        _isConnecting = false;
        _connectingDeviceId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to connect. Please try again.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
        ),
      );
    }
  }

  Future<void> _onDeviceConnected() async {
    await widget.storageService.savePairedDevice(
      PairedDevice(
        id: widget.bleService.connectedDeviceId!,
        name: widget.bleService.connectedDeviceName ?? BLEConstants.deviceName,
        pairedAt: DateTime.now(),
      ),
    );

    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _connectingDeviceId = null;
    });

    // Show success animation
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildSuccessDialog(),
    );

    if (mounted) {
      context.go('/contacts');
    }
  }

  Widget _buildSuccessDialog() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppTheme.successGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Connected!',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your SOS keychain is ready',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.backgroundLight,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pair Device',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          'Connect your SOS keychain',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.bleService.isConnected)
                    ConnectionStatusIndicator(isConnected: true),
                ],
              ),
            ),

            // Scan button area
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                children: [
                  // Animated scanning icon
                  AnimatedBuilder(
                    animation: _scanAnimationController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_isScanning) ...[
                            Container(
                              width: 120 + (_scanAnimationController.value * 40),
                              height: 120 + (_scanAnimationController.value * 40),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2 * (1 - _scanAnimationController.value)),
                                  width: 2,
                                ),
                              ),
                            ),
                            Container(
                              width: 100 + (_scanAnimationController.value * 20),
                              height: 100 + (_scanAnimationController.value * 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3 * (1 - _scanAnimationController.value)),
                                  width: 2,
                                ),
                              ),
                            ),
                          ],
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isScanning
                                  ? Icons.bluetooth_searching_rounded
                                  : Icons.bluetooth_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isScanning ? 'Scanning for devices...' : 'Ready to Scan',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isScanning
                        ? 'Make sure your keychain is powered on'
                        : 'Looking for "${BLEConstants.deviceName}"',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 180,
                    child: ElevatedButton(
                      onPressed: _isScanning ? _stopScan : _startScan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isScanning ? Icons.stop_rounded : Icons.search_rounded),
                          const SizedBox(width: 8),
                          Text(_isScanning ? 'Stop Scan' : 'Start Scan'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Device list
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Available Devices',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  if (_scanResults.isNotEmpty)
                    Text(
                      '${_scanResults.length} found',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Device list
            Expanded(
              child: _scanResults.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _scanResults.length,
                      itemBuilder: (context, index) {
                        final result = _scanResults[index];
                        return _buildDeviceCard(result);
                      },
                    ),
            ),

            // Continue button if already connected
            if (widget.bleService.isConnected)
              Padding(
                padding: const EdgeInsets.all(20),
                child: GradientButton(
                  onPressed: () => context.go('/contacts'),
                  text: 'Continue',
                  icon: Icons.arrow_forward_rounded,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bluetooth_disabled_rounded,
            size: 64,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            _isScanning ? 'Searching...' : 'No devices found',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isScanning
                ? 'Please wait while we scan for your keychain'
                : 'Tap "Start Scan" to find your SOS keychain',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(ScanResult result) {
    final device = result.device;
    final isSOSDevice = device.platformName == BLEConstants.deviceName;
    final isConnecting = _connectingDeviceId == device.remoteId.toString();
    final signalStrength = _getSignalStrength(result.rssi);

    return GradientCard(
      margin: const EdgeInsets.only(bottom: 12),
      gradient: isSOSDevice
          ? LinearGradient(
              colors: [
                AppTheme.primaryColor.withValues(alpha: 0.1),
                AppTheme.secondaryColor.withValues(alpha: 0.05),
              ],
            )
          : null,
      onTap: isConnecting ? null : () => _connectToDevice(device),
      child: Row(
        children: [
          // Device icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isSOSDevice
                  ? AppTheme.primaryColor.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isSOSDevice ? Icons.key_rounded : Icons.bluetooth_rounded,
              color: isSOSDevice ? AppTheme.primaryColor : AppTheme.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),

          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      device.platformName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isSOSDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      signalStrength.icon,
                      size: 14,
                      color: signalStrength.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${signalStrength.label} signal',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Connect button/indicator
          if (isConnecting)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textMuted,
            ),
        ],
      ),
    );
  }

  ({IconData icon, Color color, String label}) _getSignalStrength(int rssi) {
    if (rssi >= -50) {
      return (
        icon: Icons.signal_cellular_4_bar_rounded,
        color: AppTheme.success,
        label: 'Excellent',
      );
    } else if (rssi >= -60) {
      return (
        icon: Icons.signal_cellular_alt_rounded,
        color: AppTheme.success,
        label: 'Good',
      );
    } else if (rssi >= -70) {
      return (
        icon: Icons.signal_cellular_alt_2_bar_rounded,
        color: AppTheme.warning,
        label: 'Fair',
      );
    } else {
      return (
        icon: Icons.signal_cellular_alt_1_bar_rounded,
        color: AppTheme.error,
        label: 'Weak',
      );
    }
  }
}
