import 'package:dt/models/paired_device.dart';
import 'package:dt/services/ble_service.dart';
import 'package:dt/services/storage_service.dart';
import 'package:dt/widgets/connection_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({
    super.key,
    required this.bleService,
    required this.storageService,
  });

  final BLEService bleService;
  final StorageService storageService;

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  bool _isConnecting = false;

  List<Permission> get _requiredPermissions => [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ];

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
          title: const Text('Permissions Required'),
          content: Text(
            'Please enable $labels to pair with your SOS key.\n\n'
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

  Future<void> _scanAndPair() async {
    final missingPermissions = await _getMissingPermissions();
    if (!context.mounted) return;
    if (missingPermissions.isNotEmpty) {
      await _showPermissionReminder(missingPermissions);
      return;
    }

    setState(() => _isConnecting = true);
    await widget.bleService.scanAndConnect(() async {});

    await Future.delayed(const Duration(seconds: 2));
    if (widget.bleService.isConnected && widget.bleService.connectedDeviceId != null) {
      await widget.storageService.savePairedDevice(
        PairedDevice(
          id: widget.bleService.connectedDeviceId!,
          name: 'SOS-Key',
          pairedAt: DateTime.now(),
        ),
      );
      if (mounted) {
        context.go('/contacts');
      }
    }

    if (mounted) {
      setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Device')),
      body: StreamBuilder<bool>(
        stream: widget.bleService.connectionStream,
        initialData: widget.bleService.isConnected,
        builder: (context, snapshot) {
          final isConnected = snapshot.data ?? false;
          return Column(
            children: [
              ConnectionStatusBanner(isConnected: isConnected),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Looking for device name: SOS-Key'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isConnecting ? null : _scanAndPair,
                        child: Text(_isConnecting ? 'Scanning...' : 'Scan & Pair'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isConnected)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => context.go('/contacts'),
                          child: const Text('Continue'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
