import 'package:dt/models/paired_device.dart';
import 'package:dt/services/ble_service.dart';
import 'package:dt/services/storage_service.dart';
import 'package:dt/widgets/connection_status_banner.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  PairedDevice? _pairedDevice;
  int _contactCount = 0;

  List<Permission> get _requiredPermissions => [
    Permission.location,
    Permission.sms,
    Permission.notification,
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
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
          title: const Text('Permissions Required'),
          content: Text(
            'Please enable $labels to send SOS alerts correctly.\n\n'
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS Keychain')),
      body: StreamBuilder<bool>(
        stream: widget.bleService.connectionStream,
        initialData: widget.bleService.isConnected,
        builder: (context, snapshot) {
          final connected = snapshot.data ?? false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConnectionStatusBanner(isConnected: connected),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paired device: ${_pairedDevice?.name ?? 'Not paired'}'),
                    const SizedBox(height: 8),
                    Text('Emergency contacts: $_contactCount'),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.go('/pair'),
                        child: const Text('Pair / Reconnect Device'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.go('/contacts'),
                        child: const Text('Manage Contacts'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final missingPermissions = await _getMissingPermissions();
                          if (!context.mounted) return;

                          if (missingPermissions.isNotEmpty) {
                            await _showPermissionReminder(missingPermissions);
                            return;
                          }

                          final contacts = await widget.storageService.getContacts();
                          if (!context.mounted) return;

                          if (contacts.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No emergency contacts configured'),
                              ),
                            );
                            return;
                          }

                          await widget.onTestSOS();
                        },
                        child: const Text('Test SOS'),
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
