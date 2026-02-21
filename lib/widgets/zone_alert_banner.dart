import 'package:flutter/material.dart';
import '../services/zone_notification_service.dart';

// ---------------------------------------------------------------------------
// ZoneAlertBanner
//
// An animated in-app banner that appears at the top of the map whenever the
// user enters or exits a high-risk zone.  It auto-dismisses after 4 seconds.
// ---------------------------------------------------------------------------
class ZoneAlertBanner extends StatefulWidget {
  final ZoneProximityEvent event;
  final VoidCallback onDismiss;

  const ZoneAlertBanner({
    super.key,
    required this.event,
    required this.onDismiss,
  });

  @override
  State<ZoneAlertBanner> createState() => _ZoneAlertBannerState();
}

class _ZoneAlertBannerState extends State<ZoneAlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnim =
        CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();

    // Auto dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEntry = widget.event.isEntry;
    final zone = widget.event.zone;

    final bgColor = isEntry
        ? Colors.red.withOpacity(0.95)
        : Colors.green.withOpacity(0.95);

    final icon = isEntry ? Icons.warning_amber_rounded : Icons.check_circle_rounded;
    final title = isEntry ? '⚠️ High-Risk Zone Ahead' : '✅ Zone Cleared';
    final subtitle = isEntry
        ? '${zone.title}  •  ${zone.accidentCount} accidents recorded'
        : 'You\'ve left ${zone.title}';

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: GestureDetector(
          onTap: _dismiss,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (isEntry ? Colors.red : Colors.green).withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.close, color: Colors.white54, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}