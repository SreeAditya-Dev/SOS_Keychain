import 'dart:async';
import 'dart:convert';

import 'package:safeher/constants/ble_constants.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE Connection Error Types
enum BLEErrorType {
  bluetoothOff,
  bluetoothUnavailable,
  permissionDenied,
  deviceNotFound,
  connectionFailed,
  connectionTimeout,
  serviceNotFound,
  characteristicNotFound,
  disconnected,
  unknown,
}

/// BLE Error with detailed information
class BLEError {
  final BLEErrorType type;
  final String message;
  final String? suggestion;
  final dynamic originalError;

  BLEError({
    required this.type,
    required this.message,
    this.suggestion,
    this.originalError,
  });

  static BLEError fromException(dynamic e) {
    if (e.toString().contains('bluetooth adapter is not available')) {
      return BLEError(
        type: BLEErrorType.bluetoothUnavailable,
        message: 'Bluetooth is not available on this device',
        suggestion: 'This device may not support Bluetooth Low Energy',
        originalError: e,
      );
    }
    if (e.toString().contains('bluetooth is off') || 
        e.toString().contains('Bluetooth is turned off')) {
      return BLEError(
        type: BLEErrorType.bluetoothOff,
        message: 'Bluetooth is turned off',
        suggestion: 'Please turn on Bluetooth in your device settings',
        originalError: e,
      );
    }
    if (e.toString().contains('permission')) {
      return BLEError(
        type: BLEErrorType.permissionDenied,
        message: 'Bluetooth permission denied',
        suggestion: 'Please grant Bluetooth permissions in app settings',
        originalError: e,
      );
    }
    if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
      return BLEError(
        type: BLEErrorType.connectionTimeout,
        message: 'Connection timed out',
        suggestion: 'Make sure your keychain is powered on and nearby',
        originalError: e,
      );
    }
    return BLEError(
      type: BLEErrorType.unknown,
      message: 'An unexpected error occurred',
      suggestion: 'Try turning Bluetooth off and on again',
      originalError: e,
    );
  }
}

class BLEService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _sosChar;
  StreamSubscription<List<int>>? _notifSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  bool _isConnected = false;
  bool _disposed = false;
  bool _isScanning = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  final _connectionController = StreamController<bool>.broadcast();
  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  final _errorController = StreamController<BLEError>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<List<ScanResult>> get scanResultsStream => _scanResultsController.stream;
  Stream<BLEError> get errorStream => _errorController.stream;
  
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  String? get connectedDeviceId => _device?.remoteId.toString();
  String? get connectedDeviceName => _device?.platformName;

  Future<void> init(String? savedDeviceId, Future<void> Function() onSOSTrigger) async {
    // Check Bluetooth state first
    final isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) {
      _errorController.add(BLEError(
        type: BLEErrorType.bluetoothUnavailable,
        message: 'Bluetooth is not supported on this device',
      ));
      return;
    }

    if (savedDeviceId != null) {
      await _reconnect(savedDeviceId, onSOSTrigger);
    }
  }

  /// Check if Bluetooth is ready
  Future<bool> isBluetoothReady() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return false;
      
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      return false;
    }
  }

  Future<void> startScan() async {
    if (_isScanning) return;
    
    try {
      // Check Bluetooth state
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        _errorController.add(BLEError(
          type: BLEErrorType.bluetoothOff,
          message: 'Bluetooth is turned off',
          suggestion: 'Please enable Bluetooth to scan for devices',
        ));
        return;
      }
      
      _isScanning = true;
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      
      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          _scanResultsController.add(results);
        },
        onError: (e) {
          _errorController.add(BLEError.fromException(e));
        },
      );
      
      // Auto-stop scanning flag after timeout
      Future.delayed(const Duration(seconds: 15), () {
        _isScanning = false;
      });
    } catch (e) {
      _isScanning = false;
      _errorController.add(BLEError.fromException(e));
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      // Ignore stop scan errors
    }
    _isScanning = false;
  }

  Future<void> scanAndConnect(Future<void> Function() onSOSTrigger) async {
    try {
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
    } catch (e) {
      _errorController.add(BLEError.fromException(e));
    }
  }

  Future<bool> connectToDevice(
    BluetoothDevice device,
    Future<void> Function() onSOSTrigger,
  ) async {
    await stopScan();
    _reconnectAttempts = 0; // Reset reconnect attempts on manual connect
    return await _connectToDevice(device, onSOSTrigger);
  }

  Future<bool> _connectToDevice(
    BluetoothDevice device,
    Future<void> Function() onSOSTrigger,
  ) async {
    if (_disposed) return false;

    _device = device;

    try {
      // IMPORTANT: Disconnect first if there's an existing connection
      // This helps avoid Android BLE connection issues
      try {
        await device.disconnect();
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        // Ignore disconnect errors - device may not be connected
      }
      
      // IMPORTANT: Use autoConnect: false for initial connection on Android
      // autoConnect: true can cause indefinite connection attempts and timeouts
      // Increase timeout to 30 seconds for more reliability
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 30),
      );
      
      // Small delay after connection for Android stability
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Request higher MTU for better data transfer (Android specific)
      // ESP32 typically supports up to 517 bytes, but 512 is a safe value
      try {
        await device.requestMtu(512);
      } catch (e) {
        // MTU request may fail on some devices, continue anyway
        print('MTU request failed (non-critical): $e');
      }
      
    } catch (e) {
      final error = BLEError.fromException(e);
      _errorController.add(error);
      
      // Attempt reconnect if not at max attempts
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _reconnectAttempts++;
        Future.delayed(_reconnectDelay, () {
          if (!_disposed && !_isConnected) {
            _connectToDevice(device, onSOSTrigger);
          }
        });
      } else {
        _errorController.add(BLEError(
          type: BLEErrorType.connectionFailed,
          message: 'Failed to connect after $_maxReconnectAttempts attempts',
          suggestion: 'Make sure your keychain is powered on and try again',
        ));
      }
      return false;
    }

    _isConnected = true;
    _reconnectAttempts = 0; // Reset on successful connection
    _connectionController.add(true);

    try {
      // Another small delay before service discovery for stability
      await Future.delayed(const Duration(milliseconds: 300));
      
      final services = await device.discoverServices();
      bool serviceFound = false;
      bool characteristicFound = false;
      
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() == BLEConstants.serviceUUID.toLowerCase()) {
          serviceFound = true;
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == BLEConstants.sosCharUUID.toLowerCase()) {
              characteristicFound = true;
              _sosChar = char;
              await char.setNotifyValue(true);
              await _notifSubscription?.cancel();
              _notifSubscription = char.lastValueStream.listen(
                (value) async {
                  if (value.isNotEmpty) {
                    // ESP32 sends string data, convert bytes to string
                    final message = utf8.decode(value);
                    if (message == BLEConstants.sosTriggerMessage) {
                      await onSOSTrigger();
                    }
                  }
                },
                onError: (e) {
                  _errorController.add(BLEError(
                    type: BLEErrorType.unknown,
                    message: 'Error receiving data from keychain',
                    originalError: e,
                  ));
                },
              );
            }
          }
        }
      }
      
      if (!serviceFound) {
        _errorController.add(BLEError(
          type: BLEErrorType.serviceNotFound,
          message: 'SOS service not found on device',
          suggestion: 'Make sure you are connecting to a SafeHer keychain',
        ));
        await disconnect();
        return false;
      }
      
      if (!characteristicFound) {
        _errorController.add(BLEError(
          type: BLEErrorType.characteristicNotFound,
          message: 'SOS characteristic not found',
          suggestion: 'The keychain firmware may need to be updated',
        ));
        await disconnect();
        return false;
      }
    } catch (e) {
      _errorController.add(BLEError.fromException(e));
      return false;
    }

    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.disconnected) {
        _isConnected = false;
        _connectionController.add(false);
        
        _errorController.add(BLEError(
          type: BLEErrorType.disconnected,
          message: 'Keychain disconnected',
          suggestion: 'Attempting to reconnect...',
        ));
        
        // Attempt reconnection with exponential backoff
        if (!_disposed && _reconnectAttempts < _maxReconnectAttempts) {
          _reconnectAttempts++;
          final delay = Duration(seconds: 3 * _reconnectAttempts);
          await Future.delayed(delay);
          if (!_disposed && !_isConnected) {
            // For reconnection, we can use autoConnect: true
            // This allows the system to reconnect when device becomes available
            try {
              await device.connect(
                autoConnect: true,
                timeout: const Duration(seconds: 30),
              );
            } catch (e) {
              // Will retry via this same listener
              print('Reconnection attempt $_reconnectAttempts failed: $e');
            }
          }
        }
      } else if (state == BluetoothConnectionState.connected) {
        // Handle successful reconnection
        if (!_isConnected) {
          _isConnected = true;
          _reconnectAttempts = 0;
          _connectionController.add(true);
          
          // Re-setup notifications after reconnection
          try {
            await Future.delayed(const Duration(milliseconds: 500));
            final services = await device.discoverServices();
            for (final service in services) {
              if (service.uuid.toString().toLowerCase() == BLEConstants.serviceUUID.toLowerCase()) {
                for (final char in service.characteristics) {
                  if (char.uuid.toString().toLowerCase() == BLEConstants.sosCharUUID.toLowerCase()) {
                    _sosChar = char;
                    await char.setNotifyValue(true);
                    await _notifSubscription?.cancel();
                    _notifSubscription = char.lastValueStream.listen(
                      (value) async {
                        if (value.isNotEmpty) {
                          final message = utf8.decode(value);
                          if (message == BLEConstants.sosTriggerMessage) {
                            await onSOSTrigger();
                          }
                        }
                      },
                    );
                  }
                }
              }
            }
          } catch (e) {
            print('Failed to re-setup notifications: $e');
          }
        }
      }
    });

    return true;
  }

  Future<void> disconnect() async {
    _reconnectAttempts = _maxReconnectAttempts; // Prevent auto-reconnect
    
    try {
      // Cancel subscriptions first
      await _notifSubscription?.cancel();
      _notifSubscription = null;
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      
      // Disconnect the device
      if (_device != null) {
        await _device!.disconnect();
        // Give the BLE stack time to clean up
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      // Ignore disconnect errors
      print('Disconnect error (ignored): $e');
    }
    
    _device = null;
    _sosChar = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  /// Force disconnect and clear all BLE state
  /// Use this when unpairing a device
  Future<void> forceDisconnect() async {
    _reconnectAttempts = _maxReconnectAttempts; // Prevent auto-reconnect
    _disposed = true; // Prevent any reconnection attempts
    
    try {
      await _notifSubscription?.cancel();
      _notifSubscription = null;
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      
      if (_device != null) {
        // Try to gracefully disconnect
        try {
          await _device!.disconnect();
        } catch (e) {
          print('Device disconnect error: $e');
        }
        
        // Give time for BLE stack cleanup
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Stop any ongoing scans
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print('Force disconnect error: $e');
    }
    
    _device = null;
    _sosChar = null;
    _isConnected = false;
    _disposed = false; // Reset for future connections
    _reconnectAttempts = 0;
    _connectionController.add(false);
  }

  Future<bool> cancelSOS() async {
    if (_sosChar == null) {
      _errorController.add(BLEError(
        type: BLEErrorType.characteristicNotFound,
        message: 'Not connected to keychain',
        suggestion: 'Please reconnect to your keychain',
      ));
      return false;
    }
    
    try {
      // ESP32 expects string data
      await _sosChar?.write(utf8.encode('CANCEL_SOS'));
      return true;
    } catch (e) {
      _errorController.add(BLEError(
        type: BLEErrorType.unknown,
        message: 'Failed to send cancel signal',
        originalError: e,
      ));
      return false;
    }
  }

  Future<void> _reconnect(
    String deviceId,
    Future<void> Function() onSOSTrigger,
  ) async {
    if (_disposed) return;
    
    try {
      // First, check if Bluetooth is ready
      final isReady = await isBluetoothReady();
      if (!isReady) {
        _errorController.add(BLEError(
          type: BLEErrorType.bluetoothOff,
          message: 'Bluetooth is not ready',
          suggestion: 'Please enable Bluetooth',
        ));
        return;
      }
      
      // Try to find the device in system bonded devices first
      final systemDevices = await FlutterBluePlus.systemDevices([]);
      for (final device in systemDevices) {
        if (device.remoteId.toString() == deviceId) {
          print('Found device in system devices, attempting connection...');
          final success = await _connectToDevice(device, onSOSTrigger);
          if (success) return;
        }
      }

      // If not found in system devices, scan for it
      print('Device not in system devices, scanning...');
      await _scanAndReconnect(deviceId, onSOSTrigger);
    } catch (e) {
      _errorController.add(BLEError.fromException(e));
    }
  }
  
  Future<void> _scanAndReconnect(
    String deviceId,
    Future<void> Function() onSOSTrigger,
  ) async {
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      
      bool found = false;
      await for (final results in FlutterBluePlus.scanResults) {
        if (found || _disposed) break;
        
        for (final result in results) {
          // Match by device ID or device name
          if (result.device.remoteId.toString() == deviceId ||
              result.device.platformName == BLEConstants.deviceName) {
            found = true;
            await FlutterBluePlus.stopScan();
            print('Found device via scan, connecting...');
            await _connectToDevice(result.device, onSOSTrigger);
            break;
          }
        }
      }
      
      if (!found) {
        await FlutterBluePlus.stopScan();
        print('Device not found during scan');
      }
    } catch (e) {
      await FlutterBluePlus.stopScan();
      _errorController.add(BLEError.fromException(e));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _scanSubscription?.cancel();
    await _notifSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _connectionController.close();
    await _scanResultsController.close();
    await _errorController.close();
  }
}
