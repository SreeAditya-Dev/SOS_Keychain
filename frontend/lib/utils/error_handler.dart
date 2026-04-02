import 'package:flutter/material.dart';
import 'package:safeher/constants/app_theme.dart';
import 'package:safeher/services/ble_service.dart';

/// Utility class for showing error dialogs and snackbars
class ErrorHandler {
  ErrorHandler._();

  /// Show a BLE error dialog with detailed information
  static Future<void> showBLEErrorDialog(
    BuildContext context,
    BLEError error, {
    VoidCallback? onRetry,
    VoidCallback? onOpenSettings,
  }) async {
    final icon = _getErrorIcon(error.type);
    final color = _getErrorColor(error.type);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _getErrorTitle(error.type),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.message,
              style: const TextStyle(fontSize: 16),
            ),
            if (error.suggestion != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: AppTheme.info,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error.suggestion!,
                        style: TextStyle(
                          color: AppTheme.info,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Dismiss'),
          ),
          if (error.type == BLEErrorType.bluetoothOff ||
              error.type == BLEErrorType.permissionDenied)
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onOpenSettings?.call();
              },
              child: const Text('Open Settings'),
            ),
          if (onRetry != null &&
              error.type != BLEErrorType.bluetoothUnavailable)
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onRetry();
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  /// Show a snackbar for BLE errors
  static void showBLEErrorSnackBar(
    BuildContext context,
    BLEError error, {
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    final color = _getErrorColor(error.type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              _getErrorIcon(error.type),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error.message,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (error.suggestion != null)
                    Text(
                      error.suggestion!,
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        action: onAction != null
            ? SnackBarAction(
                label: actionLabel ?? 'Action',
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Show a general error snackbar
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        action: onAction != null
            ? SnackBarAction(
                label: actionLabel ?? 'Retry',
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Show a success snackbar
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  /// Show a warning snackbar
  static void showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  static IconData _getErrorIcon(BLEErrorType type) {
    switch (type) {
      case BLEErrorType.bluetoothOff:
        return Icons.bluetooth_disabled_rounded;
      case BLEErrorType.bluetoothUnavailable:
        return Icons.bluetooth_rounded;
      case BLEErrorType.permissionDenied:
        return Icons.lock_rounded;
      case BLEErrorType.deviceNotFound:
        return Icons.search_off_rounded;
      case BLEErrorType.connectionFailed:
      case BLEErrorType.connectionTimeout:
        return Icons.link_off_rounded;
      case BLEErrorType.serviceNotFound:
      case BLEErrorType.characteristicNotFound:
        return Icons.settings_bluetooth_rounded;
      case BLEErrorType.disconnected:
        return Icons.bluetooth_disabled_rounded;
      case BLEErrorType.unknown:
        return Icons.error_outline_rounded;
    }
  }

  static Color _getErrorColor(BLEErrorType type) {
    switch (type) {
      case BLEErrorType.bluetoothOff:
      case BLEErrorType.permissionDenied:
        return AppTheme.warning;
      case BLEErrorType.disconnected:
        return AppTheme.warning;
      case BLEErrorType.bluetoothUnavailable:
      case BLEErrorType.connectionFailed:
      case BLEErrorType.connectionTimeout:
      case BLEErrorType.serviceNotFound:
      case BLEErrorType.characteristicNotFound:
      case BLEErrorType.deviceNotFound:
      case BLEErrorType.unknown:
        return AppTheme.error;
    }
  }

  static String _getErrorTitle(BLEErrorType type) {
    switch (type) {
      case BLEErrorType.bluetoothOff:
        return 'Bluetooth Off';
      case BLEErrorType.bluetoothUnavailable:
        return 'Bluetooth Unavailable';
      case BLEErrorType.permissionDenied:
        return 'Permission Required';
      case BLEErrorType.deviceNotFound:
        return 'Device Not Found';
      case BLEErrorType.connectionFailed:
        return 'Connection Failed';
      case BLEErrorType.connectionTimeout:
        return 'Connection Timeout';
      case BLEErrorType.serviceNotFound:
        return 'Service Not Found';
      case BLEErrorType.characteristicNotFound:
        return 'Invalid Device';
      case BLEErrorType.disconnected:
        return 'Disconnected';
      case BLEErrorType.unknown:
        return 'Error';
    }
  }
}
