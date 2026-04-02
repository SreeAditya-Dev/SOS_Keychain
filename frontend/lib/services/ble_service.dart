import 'dart:async';

import 'package:dt/constants/ble_constants.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _sosChar;
  StreamSubscription<List<int>>? _notifSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  bool _isConnected = false;
  bool _disposed = false;

  final _connectionController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _isConnected;
  String? get connectedDeviceId => _device?.remoteId.toString();

  Future<void> init(String? savedDeviceId, Future<void> Function() onSOSTrigger) async {
    if (savedDeviceId != null) {
      await _reconnect(savedDeviceId, onSOSTrigger);
    }
  }

  Future<void> scanAndConnect(Future<void> Function() onSOSTrigger) async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (final result in results) {
        if (result.device.platformName == BLEConstants.deviceName) {
          await FlutterBluePlus.stopScan();
          await _connectToDevice(result.device, onSOSTrigger);
          break;
        }
      }
    });
  }

  Future<void> _connectToDevice(
    BluetoothDevice device,
    Future<void> Function() onSOSTrigger,
  ) async {
    if (_disposed) return;

    _device = device;

    try {
      await device.connect(autoConnect: true);
    } catch (_) {}

    _isConnected = true;
    _connectionController.add(true);

    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid.toString().toUpperCase() == BLEConstants.serviceUUID) {
        for (final char in service.characteristics) {
          if (char.uuid.toString().toUpperCase() == BLEConstants.sosCharUUID) {
            _sosChar = char;
            await char.setNotifyValue(true);
            await _notifSubscription?.cancel();
            _notifSubscription = char.lastValueStream.listen((value) async {
              if (value.isNotEmpty && value.first == BLEConstants.sosTriggerValue) {
                await onSOSTrigger();
              }
            });
          }
        }
      }
    }

    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _isConnected = false;
        _connectionController.add(false);
        Future.delayed(const Duration(seconds: 10), () {
          if (!_disposed) {
            _connectToDevice(device, onSOSTrigger);
          }
        });
      }
    });
  }

  Future<void> cancelSOS() async {
    await _sosChar?.write([0x00]);
  }

  Future<void> _reconnect(
    String deviceId,
    Future<void> Function() onSOSTrigger,
  ) async {
    final systemDevices = await FlutterBluePlus.systemDevices([]);
    for (final device in systemDevices) {
      if (device.remoteId.toString() == deviceId) {
        await _connectToDevice(device, onSOSTrigger);
        return;
      }
    }

    await scanAndConnect(onSOSTrigger);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _scanSubscription?.cancel();
    await _notifSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _connectionController.close();
  }
}
