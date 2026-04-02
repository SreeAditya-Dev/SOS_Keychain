import 'package:dt/models/sos_log.dart';
import 'package:dt/services/ble_service.dart';
import 'package:dt/services/sos_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SOSTriggeredScreen extends StatefulWidget {
  const SOSTriggeredScreen({
    super.key,
    required this.log,
    required this.sosService,
    required this.bleService,
  });

  final SOSLog log;
  final SOSService sosService;
  final BLEService bleService;

  @override
  State<SOSTriggeredScreen> createState() => _SOSTriggeredScreenState();
}

class _SOSTriggeredScreenState extends State<SOSTriggeredScreen> {
  bool _isCancelling = false;

  Future<void> _cancelAlert() async {
    setState(() => _isCancelling = true);
    await widget.sosService.cancelSOS(widget.log);
    await widget.bleService.cancelSOS();
    if (!mounted) return;
    setState(() => _isCancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    final location = (widget.log.lat != null && widget.log.lng != null)
        ? '${widget.log.lat}, ${widget.log.lng}'
        : 'Unavailable';

    return Scaffold(
      appBar: AppBar(title: const Text('SOS Triggered')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Emergency alert has been sent to your configured contacts.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text('Time: ${widget.log.timestamp.toLocal()}'),
            const SizedBox(height: 8),
            Text('Location: $location'),
            const SizedBox(height: 8),
            Text('Contacts notified: ${widget.log.contactsNotified.join(', ')}'),
            const Spacer(),
            if (!widget.log.wasCancelled)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCancelling ? null : _cancelAlert,
                  child: Text(_isCancelling ? 'Cancelling...' : 'Cancel SOS (False Alarm)'),
                ),
              )
            else
              const Text('SOS marked as false alarm.'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
