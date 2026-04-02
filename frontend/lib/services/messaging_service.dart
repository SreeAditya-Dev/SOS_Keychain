import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';

class MessagingService {
  final Telephony telephony = Telephony.instance;

  Future<bool> sendSMS(String phone, String message) async {
    try {
      if (defaultTargetPlatform != TargetPlatform.android) {
        debugPrint('Auto SMS is Android-only. Skipping for $phone');
        return false;
      }

      final smsPermission = await Permission.sms.status;
      var isGranted = smsPermission.isGranted;
      if (!isGranted) {
        final requested = await Permission.sms.request();
        isGranted = requested.isGranted;
      }

      if (!isGranted) {
        debugPrint('SMS permission not granted for $phone');
        return false;
      }

      await telephony.requestSmsPermissions;

      final smsCapable = await telephony.isSmsCapable ?? false;
      if (!smsCapable) {
        debugPrint('Device is not SMS capable for $phone');
        return false;
      }

      final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '').trim();

      final firstAttempt = await _sendDirectSms(cleanPhone, message);
      if (firstAttempt) {
        return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 600));
      final secondAttempt = await _sendDirectSms(cleanPhone, message);
      return secondAttempt;
    } catch (e) {
      debugPrint('Direct SMS failed to $phone: $e');
      return false;
    }
  }

  Future<bool> _sendDirectSms(String phone, String message) async {
    try {
      await telephony.sendSms(
        to: phone,
        message: message,
        isMultipart: true,
      );
      return true;
    } catch (error) {
      debugPrint('Direct SMS attempt failed for $phone: $error');
      return false;
    }
  }

  Future<bool> sendWhatsApp(String phone, String message) async {
    // Keep only digits and + sign, then ensure country code exists
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    
    // If phone doesn't start with +, add India country code (+91)
    // Remove leading 0 if present (common in local numbers)
    if (!cleanPhone.startsWith('+')) {
      if (cleanPhone.startsWith('0')) {
        cleanPhone = cleanPhone.substring(1);
      }
      // For WhatsApp, we need just digits with country code (no + sign)
      cleanPhone = '91$cleanPhone';
    } else {
      // Remove the + sign for WhatsApp URL (it just needs digits)
      cleanPhone = cleanPhone.substring(1);
    }
    
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encoded');
    final fallbackUri = Uri.parse('https://wa.me/$cleanPhone?text=$encoded');

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) {
        return true;
      }

      return await launchUrl(
        fallbackUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('WhatsApp launch failed for $phone: $e');
      return false;
    }
  }
}
