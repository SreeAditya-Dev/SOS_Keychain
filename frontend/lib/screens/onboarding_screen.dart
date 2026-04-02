import 'package:dt/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({
    super.key,
    required this.storageService,
  });

  final StorageService storageService;

  List<Permission> get _requiredPermissions => [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
    Permission.sms,
    Permission.notification,
  ];

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

  Future<void> _showPermissionReminder(
    BuildContext context,
    List<Permission> missing,
  ) async {
    final labels = missing.map(_permissionName).join(', ');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enable Permissions'),
          content: Text(
            'To use SOS reliably, please enable: $labels.\n\n'
            'You can enable them from app settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Not now'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS Keychain Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connect your SOS key and configure emergency contacts.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text('Permissions needed:'),
            const SizedBox(height: 8),
            const Text('• Bluetooth\n• Location\n• SMS\n• Notifications'),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _requestPermissions();
                  final missing = await _getMissingPermissions();

                  if (missing.isNotEmpty) {
                    if (!context.mounted) return;
                    await _showPermissionReminder(context, missing);
                    return;
                  }

                  await storageService.setOnboardingDone(true);
                  if (context.mounted) {
                    context.go('/pair');
                  }
                },
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
