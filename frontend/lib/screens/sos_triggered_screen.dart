import 'package:safeher/constants/app_theme.dart';
import 'package:safeher/models/sos_log.dart';
import 'package:safeher/services/ble_service.dart';
import 'package:safeher/services/sos_service.dart';
import 'package:safeher/widgets/custom_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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

class _SOSTriggeredScreenState extends State<SOSTriggeredScreen>
    with SingleTickerProviderStateMixin {
  bool _isCancelling = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _cancelAlert() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.check_circle_outline_rounded,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Cancel SOS'),
          ],
        ),
        content: const Text(
          'Are you safe? This will send a "False Alarm" message to all your emergency contacts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Active'),
          ),
          GradientButton(
            onPressed: () => Navigator.pop(context, true),
            text: 'I\'m Safe',
            gradient: AppTheme.successGradient,
            width: 120,
            height: 44,
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    await widget.sosService.cancelSOS(widget.log);
    await widget.bleService.cancelSOS();
    if (!mounted) return;
    setState(() => _isCancelling = false);

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 12),
            Text('SOS cancelled - contacts notified'),
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

  Future<void> _openMap() async {
    if (widget.log.lat == null || widget.log.lng == null) return;
    
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${widget.log.lat},${widget.log.lng}',
    );
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = widget.log.lat != null && widget.log.lng != null;
    final isCancelled = widget.log.wasCancelled;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header with pulse animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: isCancelled
                        ? AppTheme.successGradient
                        : AppTheme.sosGradient,
                    boxShadow: isCancelled
                        ? null
                        : [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.3 * _pulseController.value,
                              ),
                              blurRadius: 30 * _pulseController.value,
                              spreadRadius: 10 * _pulseController.value,
                            ),
                          ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        child: Icon(
                          isCancelled
                              ? Icons.check_circle_rounded
                              : Icons.warning_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        isCancelled ? 'SOS Cancelled' : 'SOS ACTIVE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isCancelled
                            ? 'Your contacts have been notified that you\'re safe'
                            : 'Emergency alert sent to your contacts',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            ),

            // Details section
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Alert details card
                    GradientCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alert Details',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 20),

                          // Time
                          _buildDetailRow(
                            icon: Icons.access_time_rounded,
                            label: 'Time',
                            value: _formatTime(widget.log.timestamp),
                            color: AppTheme.info,
                          ),
                          const SizedBox(height: 16),

                          // Location
                          _buildDetailRow(
                            icon: Icons.location_on_rounded,
                            label: 'Location',
                            value: hasLocation
                                ? '${widget.log.lat!.toStringAsFixed(6)}, ${widget.log.lng!.toStringAsFixed(6)}'
                                : 'Unavailable',
                            color: AppTheme.success,
                            onTap: hasLocation ? _openMap : null,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Contacts notified card
                    GradientCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Contacts Notified',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${widget.log.contactsNotified.length} contacts',
                                  style: TextStyle(
                                    color: AppTheme.success,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...widget.log.contactsNotified.map((name) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: AppTheme.heroGradient,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        name.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    name,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: AppTheme.success,
                                    size: 20,
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Location map preview (if available)
                    if (hasLocation)
                      GestureDetector(
                        onTap: _openMap,
                        child: Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                            image: DecorationImage(
                              image: NetworkImage(
                                'https://maps.googleapis.com/maps/api/staticmap'
                                '?center=${widget.log.lat},${widget.log.lng}'
                                '&zoom=15&size=600x300&maptype=roadmap'
                                '&markers=color:red%7C${widget.log.lat},${widget.log.lng}',
                              ),
                              fit: BoxFit.cover,
                              onError: (_, __) {},
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.6),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            alignment: Alignment.bottomLeft,
                            padding: const EdgeInsets.all(16),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.map_rounded,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Tap to open in Maps',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (!isCancelled)
                    GradientButton(
                      onPressed: _isCancelling ? null : _cancelAlert,
                      text: 'I\'m Safe - Cancel SOS',
                      icon: Icons.check_circle_outline_rounded,
                      gradient: AppTheme.successGradient,
                      isLoading: _isCancelling,
                    ),
                  if (isCancelled)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        border: Border.all(
                          color: AppTheme.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: AppTheme.success,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Marked as false alarm',
                            style: TextStyle(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.open_in_new_rounded,
              color: AppTheme.textMuted,
              size: 18,
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    return '$hour:$minute • $day/$month/$year';
  }
}
