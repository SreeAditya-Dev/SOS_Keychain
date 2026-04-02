import 'dart:convert';

import 'package:safeher/models/emergency_contact.dart';
import 'package:safeher/models/paired_device.dart';
import 'package:safeher/models/sos_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  static const _contactsKey = 'emergency_contacts';
  static const _pairedDeviceKey = 'paired_device';
  static const _sosLogsKey = 'sos_logs';
  static const _onboardingDoneKey = 'onboarding_done';
  static const _settingsKey = 'app_settings';

  Future<void> setOnboardingDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingDoneKey, value);
  }

  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingDoneKey) ?? false;
  }

  Future<List<EmergencyContact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_contactsKey) ?? [];
    return rawList
        .map((entry) => EmergencyContact.fromJson(jsonDecode(entry) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = contacts.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_contactsKey, encoded);
  }

  Future<PairedDevice?> getPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pairedDeviceKey);
    if (raw == null) return null;
    return PairedDevice.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> savePairedDevice(PairedDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairedDeviceKey, jsonEncode(device.toJson()));
  }

  Future<List<SOSLog>> getSOSLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_sosLogsKey) ?? [];
    return rawList
        .map((entry) => SOSLog.fromJson(jsonDecode(entry) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSOSLog(SOSLog log) async {
    final current = await getSOSLogs();
    final updated = [...current.where((l) => l.id != log.id), log]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _sosLogsKey,
      updated.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  /// Get app settings
  Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) {
      return {
        'notificationsEnabled': true,
        'connectionAlerts': true,
        'autoReconnect': true,
        'vibrationEnabled': true,
      };
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Save app settings
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings));
  }

  /// Clear all stored data
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_contactsKey);
    await prefs.remove(_pairedDeviceKey);
    await prefs.remove(_sosLogsKey);
    // Keep onboarding status and settings
  }

  /// Clear paired device
  Future<void> clearPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairedDeviceKey);
  }

  /// Delete a specific SOS log
  Future<void> deleteSOSLog(String logId) async {
    final logs = await getSOSLogs();
    final updated = logs.where((l) => l.id != logId).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _sosLogsKey,
      updated.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  /// Clear all SOS logs
  Future<void> clearSOSLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sosLogsKey);
  }
}
