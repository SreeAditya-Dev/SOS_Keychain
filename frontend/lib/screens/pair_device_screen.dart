import 'dart:async';
import 'dart:math' as math;

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
    with TickerProviderStateMixin {
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _connectingDeviceId;
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<BLEError>? _errorSubscription;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _waveController;
  late AnimationController _particleController;

  // Animations
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  // Device management
  PairedDevice? _currentDevice;
  List<PairedDevice> _pairedDevices = [];
  bool _showDeviceMenu = false;

  List<Permission> get _requiredPermissions => [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadDevices();
    _setupListeners();
  }

  void _initAnimations() {
    // Pulse animation for the central icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Rotation animation for scanning indicator
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    // Wave animation for ripple effects
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _waveController, curve: Curves.easeOut));

    // Particle animation
    _particleController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
  }

  void _setupListeners() {
    _scanSubscription = widget.bleService.scanResultsStream.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults =
              results.where((r) => r.device.platformName.isNotEmpty).toList()
                ..sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      }
    });

    _connectionSubscription = widget.bleService.connectionStream.listen((
      connected,
    ) {
      if (mounted && connected && _isConnecting) {
        _onDeviceConnected();
      }
    });

    _errorSubscription = widget.bleService.errorStream.listen((error) {
      if (mounted) {
        _handleBLEError(error);
      }
    });
  }

  Future<void> _loadDevices() async {
    final current = await widget.storageService.getPairedDevice();
    final history = await _loadDeviceHistory();
    if (mounted) {
      setState(() {
        _currentDevice = current;
        _pairedDevices = history;
      });
    }
  }

  Future<List<PairedDevice>> _loadDeviceHistory() async {
    // Load from storage - for now we just return empty, but this can be extended
    // to store multiple devices
    final current = await widget.storageService.getPairedDevice();
    if (current != null) {
      return [current];
    }
    return [];
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _waveController.dispose();
    _particleController.dispose();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    widget.bleService.stopScan();
    super.dispose();
  }

  void _handleBLEError(BLEError error) {
    if (_isConnecting && error.type == BLEErrorType.disconnected) return;

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
      ErrorHandler.showBLEErrorSnackBar(
        context,
        error,
        onAction: error.type == BLEErrorType.connectionFailed
            ? _startScan
            : null,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? AppTheme.cardDark : AppTheme.cardLight,
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

    // Start animations
    _pulseController.repeat(reverse: true);
    _rotationController.repeat();
    _waveController.repeat();
    _particleController.repeat();

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
    _pulseController.stop();
    _pulseController.reset();
    _rotationController.stop();
    _rotationController.reset();
    _waveController.stop();
    _waveController.reset();
    _particleController.stop();
    _particleController.reset();
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

    // Start connecting animation
    _pulseController.repeat(reverse: true);

    final success = await widget.bleService.connectToDevice(
      device,
      widget.onSOSTrigger,
    );

    if (!success && mounted) {
      _pulseController.stop();
      _pulseController.reset();
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
    _pulseController.stop();

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

    if (!mounted) return;

    final contacts = await widget.storageService.getContacts();
    if (contacts.isNotEmpty) {
      context.go('/home');
    } else {
      context.go('/contacts');
    }
  }

  void _showDeviceManagement() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _DeviceManagementSheet(
        currentDevice: _currentDevice,
        pairedDevices: _pairedDevices,
        isConnected: widget.bleService.isConnected,
        isDark: isDark,
        onDisconnect: () async {
          Navigator.pop(context);
          await widget.bleService.forceDisconnect();
          await widget.storageService.clearPairedDevice();
          _loadDevices();
        },
        onReconnect: () async {
          Navigator.pop(context);
          if (_currentDevice != null) {
            _startScan();
          }
        },
      ),
    );
  }

  Widget _buildSuccessDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });

    return Dialog(
      backgroundColor: isDark ? AppTheme.cardDark : AppTheme.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated success icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: AppTheme.successGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.success.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  Text(
                    'Connected!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your SOS keychain is ready to protect you',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.backgroundDark
          : AppTheme.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Header with device menu
            _buildHeader(isDark),

            // Main scanning area with impressive animations
            _buildScanningArea(isDark),

            const SizedBox(height: 20),

            // Device list header
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_scanResults.length} found',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Device list
            Expanded(
              child: _scanResults.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _scanResults.length,
                      itemBuilder: (context, index) {
                        final result = _scanResults[index];
                        return _buildDeviceCard(result, isDark, index);
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

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/home'),
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
                    color: isDark
                        ? AppTheme.textSecondaryDark
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Device management menu button
          GestureDetector(
            onTap: _showDeviceManagement,
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.more_vert_rounded,
                    color: isDark
                        ? AppTheme.textPrimaryDark
                        : AppTheme.textPrimary,
                  ),
                  if (widget.bleService.isConnected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? AppTheme.surfaceDark
                                : AppTheme.surfaceLight,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningArea(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Animated scanning visualization
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background waves
                if (_isScanning) ..._buildWaveRipples(),

                // Rotating particles
                if (_isScanning) _buildParticles(),

                // Rotating ring
                if (_isScanning)
                  AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotationController.value * 2 * math.pi,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.white.withOpacity(0.5),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                // Center icon with pulse
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isScanning || _isConnecting
                          ? _pulseAnimation.value
                          : 1.0,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                          boxShadow: [
                            if (_isScanning || _isConnecting)
                              BoxShadow(
                                color: Colors.white.withOpacity(0.4),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                          ],
                        ),
                        child: Icon(
                          _isConnecting
                              ? Icons.bluetooth_connected_rounded
                              : _isScanning
                              ? Icons.bluetooth_searching_rounded
                              : Icons.bluetooth_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Status text with animation
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _isConnecting
                  ? 'Connecting...'
                  : _isScanning
                  ? 'Scanning for Devices'
                  : 'Ready to Scan',
              key: ValueKey(
                _isConnecting
                    ? 'connecting'
                    : _isScanning
                    ? 'scanning'
                    : 'ready',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isConnecting
                ? 'Please wait while we establish connection'
                : _isScanning
                ? 'Keep your keychain nearby and powered on'
                : 'Looking for "${BLEConstants.deviceName}"',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 14,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Scan button with micro-interaction
          _buildScanButton(isDark),
        ],
      ),
    );
  }

  List<Widget> _buildWaveRipples() {
    return List.generate(3, (index) {
      return AnimatedBuilder(
        animation: _waveController,
        builder: (context, child) {
          final delay = index * 0.33;
          final progress = ((_waveController.value + delay) % 1.0);
          return Container(
            width: 100 + (progress * 80),
            height: 100 + (progress * 80),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.4 * (1 - progress)),
                width: 2,
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildParticles() {
    return AnimatedBuilder(
      animation: _particleController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: List.generate(8, (index) {
            final angle =
                (index / 8) * 2 * math.pi +
                (_particleController.value * 2 * math.pi);
            final radius =
                70.0 +
                math.sin(_particleController.value * 2 * math.pi + index) * 10;
            return Transform.translate(
              offset: Offset(
                math.cos(angle) * radius,
                math.sin(angle) * radius,
              ),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildScanButton(bool isDark) {
    return GestureDetector(
      onTap: _isConnecting ? null : (_isScanning ? _stopScan : _startScan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: _isConnecting
              ? Colors.white.withOpacity(0.3)
              : isDark
              ? const Color(0xFF1E1E1E)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isConnecting)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.white : AppTheme.primaryDark,
                  ),
                ),
              )
            else
              Icon(
                _isScanning ? Icons.stop_circle_rounded : Icons.radar_rounded,
                size: 22,
                color: AppTheme.primaryDark,
              ),
            const SizedBox(width: 10),
            Text(
              _isConnecting
                  ? 'Connecting'
                  : _isScanning
                  ? 'Stop Scan'
                  : 'Start Scan',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: _isConnecting ? Colors.white : AppTheme.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon container
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.9, end: 1.0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isScanning
                              ? Icons.bluetooth_searching_rounded
                              : Icons.bluetooth_disabled_rounded,
                          size: 44,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              _isScanning ? 'Searching...' : 'No Devices Found',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _isScanning
                  ? 'Please wait while we scan for your keychain.\nMake sure it\'s powered on and nearby.'
                  : 'Tap "Start Scan" to find your SOS keychain.\nMake sure Bluetooth is enabled.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppTheme.textSecondaryDark
                    : AppTheme.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            if (_isScanning) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(ScanResult result, bool isDark, int index) {
    final device = result.device;
    final isSOSDevice = device.platformName == BLEConstants.deviceName;
    final isConnecting = _connectingDeviceId == device.remoteId.toString();
    final signalStrength = _getSignalStrength(result.rssi);

    // Staggered animation for list items
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: isSOSDevice
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryColor.withOpacity(isDark ? 0.15 : 0.08),
                    AppTheme.primaryColor.withOpacity(isDark ? 0.08 : 0.12),
                  ],
                )
              : null,
          color: !isSOSDevice
              ? (isDark ? AppTheme.cardDark : AppTheme.cardLight)
              : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSOSDevice
                ? AppTheme.primaryColor.withOpacity(0.4)
                : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
            width: isSOSDevice ? 2 : 1,
          ),
          boxShadow: isSOSDevice
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isConnecting ? null : () => _connectToDevice(device),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  // Device icon with gradient
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: isSOSDevice
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.primaryColor,
                                AppTheme.primaryColor.withOpacity(0.8),
                              ],
                            )
                          : null,
                      color: !isSOSDevice
                          ? (isDark
                                ? AppTheme.surfaceDark
                                : AppTheme.surfaceLight)
                          : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isSOSDevice
                          ? [
                              BoxShadow(
                                color: AppTheme.primaryColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      isSOSDevice ? Icons.key_rounded : Icons.bluetooth_rounded,
                      color: isSOSDevice
                          ? Colors.white
                          : (isDark
                                ? AppTheme.textSecondaryDark
                                : AppTheme.textSecondary),
                      size: 28,
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
                            Flexible(
                              child: Text(
                                device.platformName,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSOSDevice) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primaryColor,
                                      AppTheme.primaryColor.withOpacity(0.85),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withOpacity(
                                        0.3,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'RECOMMENDED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: signalStrength.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    signalStrength.icon,
                                    size: 14,
                                    color: signalStrength.color,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    signalStrength.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: signalStrength.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Connect button/indicator
                  if (isConnecting)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSOSDevice
                            ? AppTheme.primaryColor.withOpacity(0.15)
                            : (isDark
                                  ? AppTheme.surfaceDark
                                  : AppTheme.surfaceLight),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: isSOSDevice
                            ? AppTheme.primaryColor
                            : (isDark
                                  ? AppTheme.textMutedDark
                                  : AppTheme.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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

// Device Management Bottom Sheet
class _DeviceManagementSheet extends StatelessWidget {
  const _DeviceManagementSheet({
    required this.currentDevice,
    required this.pairedDevices,
    required this.isConnected,
    required this.isDark,
    required this.onDisconnect,
    required this.onReconnect,
  });

  final PairedDevice? currentDevice;
  final List<PairedDevice> pairedDevices;
  final bool isConnected;
  final bool isDark;
  final VoidCallback onDisconnect;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppTheme.heroGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.devices_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device Management',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Manage connected devices',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isDark
                                      ? AppTheme.textSecondaryDark
                                      : AppTheme.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Current Device Section
                Text(
                  'CURRENT DEVICE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.textMutedDark : AppTheme.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),

                if (currentDevice != null)
                  _buildDeviceItem(
                    context,
                    currentDevice!,
                    isConnected: isConnected,
                    isCurrent: true,
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.surfaceDark
                          : AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.borderDark
                            : AppTheme.borderLight,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bluetooth_disabled_rounded,
                          color: isDark
                              ? AppTheme.textMutedDark
                              : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'No device paired',
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.textMutedDark
                                : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (currentDevice != null) ...[
                  const SizedBox(height: 20),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isConnected ? onDisconnect : onReconnect,
                          icon: Icon(
                            isConnected
                                ? Icons.link_off_rounded
                                : Icons.link_rounded,
                            size: 20,
                          ),
                          label: Text(isConnected ? 'Disconnect' : 'Reconnect'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isConnected
                                ? AppTheme.error
                                : AppTheme.primaryColor,
                            side: BorderSide(
                              color: isConnected
                                  ? AppTheme.error
                                  : AppTheme.primaryColor,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(
    BuildContext context,
    PairedDevice device, {
    required bool isConnected,
    required bool isCurrent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? AppTheme.success.withOpacity(0.5)
              : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
          width: isConnected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isConnected
                  ? AppTheme.success.withOpacity(0.15)
                  : AppTheme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.key_rounded,
              color: isConnected ? AppTheme.success : AppTheme.primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Paired ${_formatDate(device.pairedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppTheme.textMutedDark : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isConnected
                  ? AppTheme.success.withOpacity(0.15)
                  : AppTheme.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected ? AppTheme.success : AppTheme.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isConnected ? AppTheme.success : AppTheme.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
